import Foundation
import RouteyModel
import SQLiteData
import Testing
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct TemporaryRouteBuilderTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  @Test func addParcelToEmptyDatabaseCreatesTemporaryRouteGraph() throws {
    let database = try freshDB()

    let runID = try TemporaryRouteBuilder.addParcelToTemporaryRoute(sampleInput(), into: database)

    let graph = try database.read { db in
      (
        routes: try Route.all.fetchAll(db),
        stops: try Stop.all.fetchAll(db),
        addresses: try Address.all.fetchAll(db),
        deliveryPoints: try DeliveryPoint.all.fetchAll(db),
        links: try DeliveryPointAddress.all.fetchAll(db),
        runs: try TodaysRun.all.fetchAll(db),
        runStops: try RunStop.all.fetchAll(db),
        parcels: try Parcel.all.fetchAll(db)
      )
    }

    let route = try #require(graph.routes.first)
    #expect(graph.routes.count == 1)
    #expect(route.name == "Parcel Pile")

    let stop = try #require(graph.stops.first)
    #expect(graph.stops.count == 1)
    #expect(stop.routeID == route.id)
    #expect(stop.displayName == "31 Elm Street")
    #expect(stop.kind == "doorVisit")

    let address = try #require(graph.addresses.first)
    #expect(graph.addresses.count == 1)
    #expect(address.civicNumber == 31)
    #expect(address.street == "Elm Street")
    #expect(address.postalCode == "X0X 0X0")

    let deliveryPoint = try #require(graph.deliveryPoints.first)
    #expect(graph.deliveryPoints.count == 1)
    #expect(deliveryPoint.stopID == stop.id)

    let link = try #require(graph.links.first)
    #expect(graph.links.count == 1)
    #expect(link.deliveryPointID == deliveryPoint.id)
    #expect(link.addressID == address.id)

    let run = try #require(graph.runs.first)
    #expect(graph.runs.count == 1)
    #expect(run.id == runID)
    #expect(run.routeID == route.id)
    #expect(run.serviceDate == "2026-07-07")

    let runStop = try #require(graph.runStops.first)
    #expect(graph.runStops.count == 1)
    #expect(runStop.runID == runID)
    #expect(runStop.stopID == stop.id)
    #expect(runStop.displayName == stop.displayName)

    let parcel = try #require(graph.parcels.first)
    #expect(graph.parcels.count == 1)
    #expect(parcel.runID == runID)
    #expect(parcel.addressID == address.id)
    #expect(parcel.source == "ocr")
    #expect(parcel.labelSnapshot == "31 Elm Street\nAlex Example")
    #expect(parcel.trackingCode == "TRACK-001")
    #expect(parcel.trackingSymbology == "code128")
    #expect(parcel.requiresSignature)
    #expect(parcel.isCustoms)
    #expect(parcel.toDoor)
  }

  @Test func addParcelReusesTemporaryRouteForSameServiceDate() throws {
    let database = try freshDB()

    let firstRunID = try TemporaryRouteBuilder.addParcelToTemporaryRoute(sampleInput(), into: database)
    let secondRunID = try TemporaryRouteBuilder.addParcelToTemporaryRoute(
      sampleInput(
        civicNumber: 88,
        street: "Oak Road",
        trackingCode: "TRACK-002",
        labelSnapshot: "88 Oak Road",
        toDoor: false
      ),
      into: database
    )

    #expect(secondRunID == firstRunID)

    let graph = try database.read { db in
      (
        routes: try Route.all.fetchAll(db),
        runs: try TodaysRun.all.fetchAll(db),
        stops: try Stop.order { $0.sortIndex }.fetchAll(db),
        runStops: try RunStop.order { $0.sortIndex }.fetchAll(db),
        parcels: try Parcel.all.fetchAll(db)
      )
    }

    #expect(graph.routes.count == 1)
    #expect(graph.runs.count == 1)
    #expect(graph.stops.count == 2)
    #expect(graph.runStops.count == 2)
    #expect(graph.parcels.count == 2)
    #expect(graph.stops.map(\.displayName) == ["31 Elm Street", "88 Oak Road"])
    #expect(graph.stops.map(\.sortIndex) == [0.0, 1.0])
    #expect(graph.runStops.map(\.stopID) == graph.stops.map(\.id))
    #expect(graph.runStops.map(\.sortIndex) == [0.0, 1.0])
  }

  private func sampleInput() -> TemporaryParcelInput {
    TemporaryParcelInput(
      serviceDate: "2026-07-07",
      labelSnapshot: "31 Elm Street\nAlex Example",
      civicNumber: 31,
      street: "Elm Street",
      postalCode: "X0X 0X0",
      trackingCode: "TRACK-001",
      trackingSymbology: "code128",
      requiresSignature: true,
      isCustoms: true,
      toDoor: true
    )
  }

  private func sampleInput(
    civicNumber: Int?,
    street: String,
    trackingCode: String,
    labelSnapshot: String,
    toDoor: Bool
  ) -> TemporaryParcelInput {
    TemporaryParcelInput(
      serviceDate: "2026-07-07",
      labelSnapshot: labelSnapshot,
      civicNumber: civicNumber,
      street: street,
      postalCode: "X0X 0X0",
      trackingCode: trackingCode,
      trackingSymbology: "code128",
      requiresSignature: false,
      isCustoms: false,
      toDoor: toDoor
    )
  }
}
