import Foundation
import SQLiteData
import Testing
import RouteyImport
import RouteyModel
import RouteySearch
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RouteImporterTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func count(_ tableName: String, in database: DatabaseQueue) throws -> Int {
    try database.read { db in
      try Int.fetchOne(db, sql: "SELECT count(*) FROM \"\(tableName)\"") ?? -1
    }
  }

  @Test func importCreatesOrderedStopsWithAddressesAndPoints() throws {
    let database = try freshDB()
    let parsed = RouteParser.parse("10100 County Rd 12\n38 Northgate Rd\n")

    let summary = try RouteImporter.importRoute(named: "Riverbend", from: parsed, into: database)

    #expect(summary.stopsCreated == 2)
    #expect(summary.skipped.isEmpty)

    let routes = try database.read { db in try Route.all.fetchAll(db) }
    #expect(routes.count == 1)
    #expect(routes.first?.id == summary.routeID)
    #expect(routes.first?.name == "Riverbend")

    let stops = try database.read { db in
      try Stop.all.order { $0.sortIndex }.fetchAll(db)
    }
    #expect(stops.map(\.displayName) == ["10100 County Rd 12", "38 Northgate Rd"])
    #expect(stops.map(\.sortIndex) == [0.0, 1.0])
    #expect(stops.allSatisfy { $0.routeID == summary.routeID })

    #expect(try count("addresses", in: database) == 2)
    #expect(try count("deliveryPoints", in: database) == 2)
    #expect(try count("deliveryPointAddresses", in: database) == 2)
  }

  @Test func importPropagatesSkippedRows() throws {
    let database = try freshDB()
    let parsed = RouteParser.parse("---\n10100 County Rd 12\n")

    let summary = try RouteImporter.importRoute(named: "Riverbend", from: parsed, into: database)

    #expect(summary.stopsCreated == 1)
    #expect(summary.skipped.count == 1)
    #expect(summary.skipped[0].reason == "no civic number or street")
  }

  @Test func importPersistsPostalCodesFromCSV() throws {
    let database = try freshDB()
    let parsed = RouteParser.parse(
      """
      civic,street,postalCode
      10100,County Rd 12,A1A 1A1
      """
    )

    _ = try RouteImporter.importRoute(named: "Riverbend", from: parsed, into: database)

    let addresses = try database.read { db in
      try Address.all.fetchAll(db)
    }
    #expect(addresses.map(\.postalCode) == ["A1A 1A1"])
  }

  @Test func importGroupsSharedSiteCompartmentAndAttachesTags() throws {
    let database = try freshDB()
    let parsed = RouteParser.parse(
      """
      civic,street,site,module,compartment,tags,warnings
      10100,County Rd 12,Community Boxes,5,7,no-flyers,dog
      10102,County Rd 12,Community Boxes,5,7,,
      """
    )

    let summary = try RouteImporter.importRoute(named: "Riverbend", from: parsed, into: database)

    let graph = try database.read { db in
      (
        stops: try Stop.all.fetchAll(db),
        modules: try Module.all.fetchAll(db),
        deliveryPoints: try DeliveryPoint.all.fetchAll(db),
        addresses: try Address.all.fetchAll(db),
        pointLinks: try DeliveryPointAddress.all.fetchAll(db),
        tags: try Tag.all.fetchAll(db),
        tagLinks: try AddressTag.all.fetchAll(db)
      )
    }

    #expect(graph.stops.count == 1)
    #expect(summary.stopsCreated == 1)
    #expect(graph.stops.first?.displayName == "Community Boxes")
    #expect(graph.modules.count == 1)
    #expect(graph.modules.first?.name == "5")
    #expect(graph.deliveryPoints.count == 1)
    #expect(graph.deliveryPoints.first?.label == "7")
    #expect(graph.addresses.count == 2)
    #expect(graph.pointLinks.count == 2)
    #expect(graph.tags.map(\.name).sorted() == ["dog", "no-flyers"])
    #expect(graph.tags.first(where: { $0.name == "dog" })?.isWarning == true)
    #expect(graph.tags.first(where: { $0.name == "no-flyers" })?.isWarning == false)
    #expect(graph.tagLinks.count == 2)
  }

  @Test func importKeepsCompartmentWhenSiteNameIsUnknown() throws {
    let database = try freshDB()
    let parsed = RouteParser.parse(
      """
      civic,street,module,compartment
      10100,County Rd 12,5,7
      """
    )

    let summary = try RouteImporter.importRoute(named: "Riverbend", from: parsed, into: database)
    let context = try database.read { db in
      try #require(RouteAddressLookup.contexts(routeID: summary.routeID, in: db).first)
    }

    #expect(context.siteName == nil)
    #expect(context.moduleName == "5")
    #expect(context.compartmentLabel == "7")
    #expect(context.locator == "Module 5 · Compartment 7")
  }

  @Test func importedRouteIsImmediatelySearchable() throws {
    let database = try freshDB()
    try database.write { db in
      try SearchIndex.install(db)
    }

    let parsed = RouteParser.parse("10100 County Rd 12\n")

    _ = try RouteImporter.importRoute(named: "Riverbend", from: parsed, into: database)

    let hits = try database.read { db in
      try SearchIndex.match("10100", in: db)
    }

    #expect(hits.count == 1)
  }
}
