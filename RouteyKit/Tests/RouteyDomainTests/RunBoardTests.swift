import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RunBoardTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  @Test func boardSummarizesWarningsParcelsAndProgress() throws {
    let database = try freshDB()
    let routeID = UUID()
    let dogTagID = UUID()
    let plainTagID = UUID()
    let stopAID = UUID()
    let stopBID = UUID()
    let deliveryPointAID = UUID()
    let deliveryPointBID = UUID()
    let addressAID = UUID()
    let addressBID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try Stop.insert {
        Stop(id: stopAID, routeID: routeID, tieOut: "1", sortIndex: 0, displayName: "Stop A")
      }
      .execute(db)
      try Stop.insert {
        Stop(id: stopBID, routeID: routeID, tieOut: "2", sortIndex: 1, displayName: "Stop B")
      }
      .execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: deliveryPointAID, stopID: stopAID) }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: deliveryPointBID, stopID: stopBID) }.execute(db)
      try Address.insert { Address(id: addressAID, civicNumber: 101, street: "Maple Road") }.execute(db)
      try Address.insert { Address(id: addressBID, civicNumber: 102, street: "Maple Road") }.execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: deliveryPointAID, addressID: addressAID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: deliveryPointBID, addressID: addressBID)
      }
      .execute(db)
      try Tag.insert { Tag(id: dogTagID, name: "dog", isWarning: true) }.execute(db)
      try Tag.insert { Tag(id: plainTagID, name: "no-flyers", isWarning: false) }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addressAID, tagID: dogTagID) }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addressBID, tagID: plainTagID) }.execute(db)
    }

    let runID = try RunGeneration.generate(
      routeID: routeID,
      serviceDate: "2026-06-29",
      now: Date(timeIntervalSince1970: 1_782_000_000),
      into: database
    )
    try RunOperations.addParcel(
      runID: runID,
      addressID: addressAID,
      source: "manual",
      requiresSignature: true,
      isCustoms: false,
      toDoor: false,
      labelSnapshot: "Invented label",
      trackingCode: "",
      trackingSymbology: "",
      in: database
    )

    let board = try database.read { db in try RunBoard.load(runID: runID, db) }

    #expect(board.total == 2)
    #expect(board.doneCount == 0)
    #expect(board.signatureCount == 1)
    #expect(board.stops.map(\.displayName) == ["Stop A", "Stop B"])
    let stopA = try #require(board.stops.first { $0.displayName == "Stop A" })
    let stopB = try #require(board.stops.first { $0.displayName == "Stop B" })
    #expect(stopA.hasWarning)
    #expect(stopA.parcelCount == 1)
    #expect(stopB.hasWarning == false)
    #expect(stopB.parcelCount == 0)
  }

  @Test func emptyRunYieldsZeroes() throws {
    let database = try freshDB()
    let routeID = UUID()
    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
    }

    let runID = try RunGeneration.generate(
      routeID: routeID,
      serviceDate: "2026-06-29",
      now: Date(timeIntervalSince1970: 1_782_000_000),
      into: database
    )
    let board = try database.read { db in try RunBoard.load(runID: runID, db) }

    #expect(board == RunBoard.empty)
  }
}
