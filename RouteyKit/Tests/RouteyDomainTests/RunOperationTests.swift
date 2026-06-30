import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RunOperationTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func seedRun(in database: DatabaseQueue, stopCount: Int = 3) throws -> (Route.ID, TodaysRun.ID) {
    let routeID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      for index in 0..<stopCount {
        try Stop.insert {
          Stop(
            routeID: routeID,
            tieOut: "\(index + 1)",
            sortIndex: Double(index),
            kind: "pointOfCall",
            displayName: "Sample Stop \(index + 1)"
          )
        }
        .execute(db)
      }
    }

    let runID = try RunGeneration.generate(
      routeID: routeID,
      serviceDate: "2026-06-22",
      now: Date(timeIntervalSince1970: 1_782_000_000),
      into: database
    )
    return (routeID, runID)
  }

  @Test func moveRunStopUsesFractionalSortIndexWithoutRenumberingSiblings() throws {
    let database = try freshDB()
    let (_, runID) = try seedRun(in: database)
    let original = try database.read { db in
      try RunStop.where { $0.runID.eq(#bind(runID)) }.order { $0.sortIndex }.fetchAll(db)
    }
    let first = try #require(original.first)
    let second = try #require(original.dropFirst().first)
    let third = try #require(original.dropFirst(2).first)

    try RunOperations.moveRunStop(third.id, after: first.id, in: database)

    let moved = try database.read { db in
      try RunStop.where { $0.runID.eq(#bind(runID)) }.order { $0.sortIndex }.fetchAll(db)
    }

    #expect(moved.map(\.id) == [first.id, third.id, second.id])
    #expect(moved.map(\.sortIndex) == [0.0, 0.5, 1.0])
  }

  @Test func moveRunStopWithNilPredecessorMovesStopToFront() throws {
    let database = try freshDB()
    let (_, runID) = try seedRun(in: database)
    let original = try database.read { db in
      try RunStop.where { $0.runID.eq(#bind(runID)) }.order { $0.sortIndex }.fetchAll(db)
    }
    let first = try #require(original.first)
    let second = try #require(original.dropFirst().first)
    let third = try #require(original.dropFirst(2).first)

    try RunOperations.moveRunStop(third.id, after: nil, in: database)

    let moved = try database.read { db in
      try RunStop.where { $0.runID.eq(#bind(runID)) }.order { $0.sortIndex }.fetchAll(db)
    }

    #expect(moved.map(\.id) == [third.id, first.id, second.id])
    #expect((moved.first?.sortIndex ?? 0) < first.sortIndex)
  }

  @Test func addParcelAndSignatureCountTrackUndeliveredSignatureParcels() throws {
    let database = try freshDB()
    let (_, runID) = try seedRun(in: database)
    let addressID = UUID()

    try database.write { db in
      try Address.insert { Address(id: addressID, street: "Placeholder Road") }.execute(db)
    }

    let signatureParcelID = try RunOperations.addParcel(
      runID: runID,
      addressID: addressID,
      source: "manual",
      sizeClass: "small",
      requiresSignature: true,
      isCustoms: false,
      toDoor: true,
      labelSnapshot: "Sample label requiring signature",
      trackingCode: "TRACK-001",
      trackingSymbology: "code128",
      in: database
    )
    _ = try RunOperations.addParcel(
      runID: runID,
      addressID: addressID,
      source: "manual",
      sizeClass: "large",
      requiresSignature: false,
      isCustoms: false,
      toDoor: false,
      labelSnapshot: "Sample label without signature",
      trackingCode: "TRACK-002",
      trackingSymbology: "code128",
      in: database
    )

    #expect(try RunOperations.signatureCount(runID: runID, in: database) == 1)

    try database.write { db in
      try Parcel.find(signatureParcelID)
        .update { $0.isDelivered = #bind(true) }
        .execute(db)
    }

    #expect(try RunOperations.signatureCount(runID: runID, in: database) == 0)
  }

  @Test func bulkCheckOffMarksStopsThroughTargetOnly() throws {
    let database = try freshDB()
    let (_, runID) = try seedRun(in: database, stopCount: 5)
    let runStops = try database.read { db in
      try RunStop.where { $0.runID.eq(#bind(runID)) }.order { $0.sortIndex }.fetchAll(db)
    }
    let third = try #require(runStops.dropFirst(2).first)

    try RunOperations.bulkCheckOff(throughRunStop: third.id, runID: runID, in: database)

    let checkedStops = try database.read { db in
      try RunStop.where { $0.runID.eq(#bind(runID)) }.order { $0.sortIndex }.fetchAll(db)
    }

    #expect(checkedStops.prefix(3).allSatisfy { $0.isDone })
    #expect(checkedStops.suffix(2).allSatisfy { !$0.isDone })
  }

  @Test func removeParcelDeletesTheRow() throws {
    let database = try freshDB()
    let (_, runID) = try seedRun(in: database)

    let parcelID = try RunOperations.addParcel(
      runID: runID, addressID: nil, source: "ocr",
      requiresSignature: true, isCustoms: false, toDoor: false,
      labelSnapshot: "31 Elm St", trackingCode: "ZX-001", trackingSymbology: "",
      in: database
    )
    #expect(try RunOperations.signatureCount(runID: runID, in: database) == 1)

    try RunOperations.removeParcel(parcelID, in: database)

    let remaining = try database.read { db in try Parcel.where { $0.id.eq(#bind(parcelID)) }.fetchAll(db) }
    #expect(remaining.isEmpty)
    #expect(try RunOperations.signatureCount(runID: runID, in: database) == 0)
  }
}
