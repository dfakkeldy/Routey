import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RunOptimizationTests {
  private struct RunFixture {
    var runID: TodaysRun.ID
    var eligibleRunStopID: RunStop.ID
    var unresolvedRunStopID: RunStop.ID
    var nonParcelRunStopID: RunStop.ID
  }

  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func seedRun(in database: DatabaseQueue) throws -> RunFixture {
    let routeID = UUID()
    let runID = UUID()
    let eligibleStopID = UUID()
    let unresolvedStopID = UUID()
    let nonParcelStopID = UUID()
    let eligibleRunStopID = UUID()
    let unresolvedRunStopID = UUID()
    let nonParcelRunStopID = UUID()
    let eligibleAddressID = UUID()
    let unresolvedAddressID = UUID()
    let nonParcelAddressID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try TodaysRun.insert {
        TodaysRun(id: runID, routeID: routeID, serviceDate: "2026-07-07")
      }
      .execute(db)

      try Stop.insert {
        Stop(
          id: eligibleStopID,
          routeID: routeID,
          tieOut: "A",
          sortIndex: 0,
          displayName: "Coordinate stop",
          latitude: 45.0,
          longitude: -63.0
        )
      }
      .execute(db)
      try Stop.insert {
        Stop(
          id: unresolvedStopID,
          routeID: routeID,
          tieOut: "B",
          sortIndex: 1,
          displayName: "Missing coordinate stop"
        )
      }
      .execute(db)
      try Stop.insert {
        Stop(
          id: nonParcelStopID,
          routeID: routeID,
          tieOut: "C",
          sortIndex: 2,
          displayName: "No parcel stop",
          latitude: 45.2,
          longitude: -63.2
        )
      }
      .execute(db)

      try RunStop.insert {
        RunStop(
          id: eligibleRunStopID,
          runID: runID,
          stopID: eligibleStopID,
          tieOut: "A",
          displayName: "Coordinate stop",
          sortIndex: 0
        )
      }
      .execute(db)
      try RunStop.insert {
        RunStop(
          id: unresolvedRunStopID,
          runID: runID,
          stopID: unresolvedStopID,
          tieOut: "B",
          displayName: "Missing coordinate stop",
          sortIndex: 1
        )
      }
      .execute(db)
      try RunStop.insert {
        RunStop(
          id: nonParcelRunStopID,
          runID: runID,
          stopID: nonParcelStopID,
          tieOut: "C",
          displayName: "No parcel stop",
          sortIndex: 2
        )
      }
      .execute(db)

      try seedAddressGraph(stopID: eligibleStopID, addressID: eligibleAddressID, in: db)
      try seedAddressGraph(stopID: unresolvedStopID, addressID: unresolvedAddressID, in: db)
      try seedAddressGraph(stopID: nonParcelStopID, addressID: nonParcelAddressID, in: db)

      try Parcel.insert {
        Parcel(runID: runID, addressID: eligibleAddressID, labelSnapshot: "Invented label A")
      }
      .execute(db)
      try Parcel.insert {
        Parcel(runID: runID, addressID: unresolvedAddressID, labelSnapshot: "Invented label B")
      }
      .execute(db)
    }

    return RunFixture(
      runID: runID,
      eligibleRunStopID: eligibleRunStopID,
      unresolvedRunStopID: unresolvedRunStopID,
      nonParcelRunStopID: nonParcelRunStopID
    )
  }

  @Test func suggestSeparatesEligibleAndUnresolvedParcelStops() throws {
    let database = try freshDB()
    let fixture = try seedRun(in: database)

    let suggestion = try RunOptimization.suggest(runID: fixture.runID, start: nil, in: database)

    #expect(suggestion.orderedRunStopIDs == [fixture.eligibleRunStopID])
    #expect(suggestion.unresolvedRunStopIDs == [fixture.unresolvedRunStopID])
    #expect(!suggestion.orderedRunStopIDs.contains(fixture.nonParcelRunStopID))
    #expect(suggestion.totalDistance == 0)
  }

  @Test func suggestOrdersCoordinateBackedParcelStops() throws {
    let database = try freshDB()
    let routeID = UUID()
    let runID = UUID()
    let firstStopID = UUID()
    let farStopID = UUID()
    let nearStopID = UUID()
    let firstRunStopID = UUID()
    let farRunStopID = UUID()
    let nearRunStopID = UUID()
    let firstAddressID = UUID()
    let farAddressID = UUID()
    let nearAddressID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try TodaysRun.insert {
        TodaysRun(id: runID, routeID: routeID, serviceDate: "2026-07-07")
      }
      .execute(db)

      try Stop.insert {
        Stop(
          id: firstStopID,
          routeID: routeID,
          tieOut: "A",
          sortIndex: 0,
          displayName: "First stop",
          latitude: 45.0,
          longitude: -63.0
        )
      }
      .execute(db)
      try Stop.insert {
        Stop(
          id: farStopID,
          routeID: routeID,
          tieOut: "B",
          sortIndex: 1,
          displayName: "Far stop",
          latitude: 45.30,
          longitude: -63.0
        )
      }
      .execute(db)
      try Stop.insert {
        Stop(
          id: nearStopID,
          routeID: routeID,
          tieOut: "C",
          sortIndex: 2,
          displayName: "Near stop",
          latitude: 45.01,
          longitude: -63.0
        )
      }
      .execute(db)

      try RunStop.insert {
        RunStop(
          id: firstRunStopID,
          runID: runID,
          stopID: firstStopID,
          tieOut: "A",
          displayName: "First stop",
          sortIndex: 0
        )
      }
      .execute(db)
      try RunStop.insert {
        RunStop(
          id: farRunStopID,
          runID: runID,
          stopID: farStopID,
          tieOut: "B",
          displayName: "Far stop",
          sortIndex: 1
        )
      }
      .execute(db)
      try RunStop.insert {
        RunStop(
          id: nearRunStopID,
          runID: runID,
          stopID: nearStopID,
          tieOut: "C",
          displayName: "Near stop",
          sortIndex: 2
        )
      }
      .execute(db)

      try seedAddressGraph(stopID: firstStopID, addressID: firstAddressID, in: db)
      try seedAddressGraph(stopID: farStopID, addressID: farAddressID, in: db)
      try seedAddressGraph(stopID: nearStopID, addressID: nearAddressID, in: db)

      for addressID in [firstAddressID, farAddressID, nearAddressID] {
        try Parcel.insert {
          Parcel(runID: runID, addressID: addressID, labelSnapshot: "Invented label")
        }
        .execute(db)
      }
    }

    let suggestion = try RunOptimization.suggest(runID: runID, start: nil, in: database)

    #expect(suggestion.orderedRunStopIDs == [firstRunStopID, nearRunStopID, farRunStopID])
    #expect(suggestion.unresolvedRunStopIDs.isEmpty)
    #expect(suggestion.totalDistance > 0)
  }

  @Test func applyReassignsOptimizedStopsBeforeRemainingStops() throws {
    let database = try freshDB()
    let routeID = UUID()
    let runID = UUID()
    let firstStopID = UUID()
    let farStopID = UUID()
    let nearStopID = UUID()
    let unresolvedStopID = UUID()
    let nonParcelStopID = UUID()
    let firstRunStopID = UUID()
    let farRunStopID = UUID()
    let nearRunStopID = UUID()
    let unresolvedRunStopID = UUID()
    let nonParcelRunStopID = UUID()
    let firstAddressID = UUID()
    let farAddressID = UUID()
    let nearAddressID = UUID()
    let unresolvedAddressID = UUID()
    let nonParcelAddressID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try TodaysRun.insert {
        TodaysRun(id: runID, routeID: routeID, serviceDate: "2026-07-07")
      }
      .execute(db)

      let stops = [
        Stop(
          id: firstStopID,
          routeID: routeID,
          tieOut: "A",
          sortIndex: 0,
          displayName: "First stop",
          latitude: 45.0,
          longitude: -63.0
        ),
        Stop(
          id: farStopID,
          routeID: routeID,
          tieOut: "B",
          sortIndex: 1,
          displayName: "Far stop",
          latitude: 45.30,
          longitude: -63.0
        ),
        Stop(
          id: nearStopID,
          routeID: routeID,
          tieOut: "C",
          sortIndex: 2,
          displayName: "Near stop",
          latitude: 45.01,
          longitude: -63.0
        ),
        Stop(
          id: unresolvedStopID,
          routeID: routeID,
          tieOut: "D",
          sortIndex: 3,
          displayName: "Unresolved stop"
        ),
        Stop(
          id: nonParcelStopID,
          routeID: routeID,
          tieOut: "E",
          sortIndex: 4,
          displayName: "No parcel stop",
          latitude: 45.4,
          longitude: -63.4
        ),
      ]
      for stop in stops {
        try Stop.insert { stop }.execute(db)
      }

      let runStops = [
        RunStop(
          id: firstRunStopID,
          runID: runID,
          stopID: firstStopID,
          tieOut: "A",
          displayName: "First stop",
          sortIndex: 0
        ),
        RunStop(
          id: farRunStopID,
          runID: runID,
          stopID: farStopID,
          tieOut: "B",
          displayName: "Far stop",
          sortIndex: 1
        ),
        RunStop(
          id: nearRunStopID,
          runID: runID,
          stopID: nearStopID,
          tieOut: "C",
          displayName: "Near stop",
          sortIndex: 2
        ),
        RunStop(
          id: unresolvedRunStopID,
          runID: runID,
          stopID: unresolvedStopID,
          tieOut: "D",
          displayName: "Unresolved stop",
          sortIndex: 3
        ),
        RunStop(
          id: nonParcelRunStopID,
          runID: runID,
          stopID: nonParcelStopID,
          tieOut: "E",
          displayName: "No parcel stop",
          sortIndex: 4
        ),
      ]
      for runStop in runStops {
        try RunStop.insert { runStop }.execute(db)
      }

      try seedAddressGraph(stopID: firstStopID, addressID: firstAddressID, in: db)
      try seedAddressGraph(stopID: farStopID, addressID: farAddressID, in: db)
      try seedAddressGraph(stopID: nearStopID, addressID: nearAddressID, in: db)
      try seedAddressGraph(stopID: unresolvedStopID, addressID: unresolvedAddressID, in: db)
      try seedAddressGraph(stopID: nonParcelStopID, addressID: nonParcelAddressID, in: db)

      for addressID in [firstAddressID, farAddressID, nearAddressID, unresolvedAddressID] {
        try Parcel.insert {
          Parcel(runID: runID, addressID: addressID, labelSnapshot: "Invented label")
        }
        .execute(db)
      }
    }

    let suggestion = try RunOptimization.suggest(runID: runID, start: nil, in: database)
    try RunOptimization.apply(suggestion, to: runID, in: database)

    let runStops = try database.read { db in
      try RunStop
        .where { $0.runID.eq(#bind(runID)) }
        .order { $0.sortIndex }
        .fetchAll(db)
    }

    #expect(runStops.map(\.id) == [
      firstRunStopID,
      nearRunStopID,
      farRunStopID,
      unresolvedRunStopID,
      nonParcelRunStopID,
    ])
    #expect(runStops.map(\.sortIndex) == [0, 1, 2, 3, 4])
  }

  private func seedAddressGraph(
    stopID: Stop.ID,
    addressID: Address.ID,
    in db: Database
  ) throws {
    let deliveryPointID = UUID()

    try DeliveryPoint.insert {
      DeliveryPoint(id: deliveryPointID, stopID: stopID, label: "Box")
    }
    .execute(db)
    try Address.insert {
      Address(id: addressID, civicNumber: 101, street: "Sample Road")
    }
    .execute(db)
    try DeliveryPointAddress.insert {
      DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: addressID)
    }
    .execute(db)
  }
}
