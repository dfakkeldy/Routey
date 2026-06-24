import Foundation
import SQLiteData
import Testing
import RouteyImport
import RouteyModel
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
}
