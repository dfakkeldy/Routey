import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RunGenerationTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func seedRoute(in database: DatabaseQueue) throws -> Route.ID {
    let routeID = UUID()
    let stops = [
      Stop(routeID: routeID, tieOut: "A", sortIndex: 0, kind: "pointOfCall", displayName: "Alpha Stop"),
      Stop(routeID: routeID, tieOut: "B", sortIndex: 1, kind: "cmbSite", displayName: "Beta Site"),
      Stop(routeID: routeID, tieOut: "C", sortIndex: 2, kind: "doorVisit", displayName: "Gamma Door"),
    ]

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      for stop in stops {
        try Stop.insert { stop }.execute(db)
      }
    }

    return routeID
  }

  @Test func generateCreatesOrderedSnapshotAndIsIdempotentForRouteDate() throws {
    let database = try freshDB()
    let routeID = try seedRoute(in: database)
    let now = Date(timeIntervalSince1970: 1_782_000_000)

    let firstRunID = try RunGeneration.generate(
      routeID: routeID,
      serviceDate: "2026-06-22",
      now: now,
      into: database
    )
    let secondRunID = try RunGeneration.generate(
      routeID: routeID,
      serviceDate: "2026-06-22",
      now: now.addingTimeInterval(60),
      into: database
    )

    #expect(secondRunID == firstRunID)

    let run = try #require(try database.read { db in
      try TodaysRun.find(firstRunID).fetchOne(db)
    })
    #expect(run.routeID == routeID)
    #expect(run.serviceDate == "2026-06-22")
    #expect(run.createdAt == now)

    let runStops = try database.read { db in
      try RunStop
        .where { $0.runID.eq(#bind(firstRunID)) }
        .order { $0.sortIndex }
        .fetchAll(db)
    }

    #expect(runStops.map(\.tieOut) == ["A", "B", "C"])
    #expect(runStops.map(\.displayName) == ["Alpha Stop", "Beta Site", "Gamma Door"])
    #expect(runStops.map(\.kind) == ["pointOfCall", "cmbSite", "doorVisit"])
    #expect(runStops.map(\.sortIndex) == [0.0, 1.0, 2.0])
    #expect(runStops.allSatisfy { !$0.isDone })
    #expect(runStops.count == 3)

    let firstMasterStopID = try #require(runStops.first?.stopID)
    try RouteEditing.updateStopDisplayName(firstMasterStopID, to: "Edited Master Stop", in: database)

    let updatedSnapshots = try database.read { db in
      try RunStop
        .where { $0.runID.eq(#bind(firstRunID)) }
        .order { $0.sortIndex }
        .fetchAll(db)
    }
    #expect(updatedSnapshots.map(\.displayName) == ["Alpha Stop", "Beta Site", "Gamma Door"])
  }
}
