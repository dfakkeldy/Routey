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
    let (routeID, runID) = try seedRun(in: database)
    let addressID = UUID()
    let deliveryPointID = UUID()
    let stop = try #require(database.read { db in
      try Stop.where { $0.routeID.eq(#bind(routeID)) }.fetchAll(db).first
    })

    try database.write { db in
      try Address.insert { Address(id: addressID, street: "Placeholder Road") }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: deliveryPointID, stopID: stop.id) }.execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: addressID)
      }
      .execute(db)
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

  @Test func setRunStopDoneTogglesASingleStop() throws {
    let database = try freshDB()
    let (_, runID) = try seedRun(in: database, stopCount: 3)
    let stops = try database.read { db in
      try RunStop.where { $0.runID.eq(#bind(runID)) }.order { $0.sortIndex }.fetchAll(db)
    }
    let target = stops[1]

    try RunOperations.setRunStopDone(target.id, done: true, in: database)
    let afterOn = try database.read { db in try RunStop.find(target.id).fetchOne(db) }
    #expect(afterOn?.isDone == true)

    let others = try database.read { db in
      try RunStop.where { $0.runID.eq(#bind(runID)) }.fetchAll(db)
    }
    .filter { $0.id != target.id }
    #expect(others.allSatisfy { $0.isDone == false })

    try RunOperations.setRunStopDone(target.id, done: false, in: database)
    let afterOff = try database.read { db in try RunStop.find(target.id).fetchOne(db) }
    #expect(afterOff?.isDone == false)
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

  @Test func addParcelRejectsAnAddressOutsideTheRunRoute() throws {
    let database = try freshDB()
    let (selectedRouteID, runID) = try seedRun(in: database)
    let otherRouteID = UUID()
    let otherStopID = UUID()
    let otherPointID = UUID()
    let otherAddressID = UUID()

    try database.write { db in
      try Route.insert { Route(id: otherRouteID, name: "Backup Route") }.execute(db)
      try Stop.insert { Stop(id: otherStopID, routeID: otherRouteID) }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: otherPointID, stopID: otherStopID) }.execute(db)
      try Address.insert { Address(id: otherAddressID, street: "Backup Road") }.execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: otherPointID, addressID: otherAddressID)
      }
      .execute(db)
    }

    #expect(
      throws: RunOperations.ValidationError.addressDoesNotBelongToRun(
        addressID: otherAddressID,
        runID: runID
      )
    ) {
      try RunOperations.addParcel(
        runID: runID,
        addressID: otherAddressID,
        source: "ocr",
        requiresSignature: false,
        isCustoms: false,
        toDoor: false,
        labelSnapshot: "Invented backup-route label",
        trackingCode: "",
        trackingSymbology: "",
        in: database
      )
    }

    let route = try database.read { db in try TodaysRun.find(runID).fetchOne(db) }
    let parcels = try database.read { db in
      try Parcel.where { $0.runID.eq(#bind(runID)) }.fetchAll(db)
    }
    #expect(route?.routeID == selectedRouteID)
    #expect(parcels.isEmpty)
  }

  @Test func addParcelRejectsAnAddressOutsideTheRunSnapshot() throws {
    let database = try freshDB()
    let (routeID, runID) = try seedRun(in: database)
    let newStopID = UUID()
    let newPointID = UUID()
    let newAddressID = UUID()

    try database.write { db in
      try Stop.insert { Stop(id: newStopID, routeID: routeID) }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: newPointID, stopID: newStopID) }.execute(db)
      try Address.insert { Address(id: newAddressID, street: "Later Addition Road") }.execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: newPointID, addressID: newAddressID)
      }
      .execute(db)
    }

    #expect(
      throws: RunOperations.ValidationError.addressDoesNotBelongToRun(
        addressID: newAddressID,
        runID: runID
      )
    ) {
      try RunOperations.addParcel(
        runID: runID,
        addressID: newAddressID,
        source: "ocr",
        requiresSignature: false,
        isCustoms: false,
        toDoor: false,
        labelSnapshot: "Invented later-added label",
        trackingCode: "",
        trackingSymbology: "",
        in: database
      )
    }

    let parcels = try database.read { db in
      try Parcel.where { $0.runID.eq(#bind(runID)) }.fetchAll(db)
    }
    #expect(parcels.isEmpty)
  }

  @Test func addParcelAcceptsAnAddressSharedByBothRunSnapshots() throws {
    let database = try freshDB()
    let (firstRouteID, firstRunID) = try seedRun(in: database)
    let (secondRouteID, secondRunID) = try seedRun(in: database)
    let firstStop = try #require(database.read { db in
      try Stop.where { $0.routeID.eq(#bind(firstRouteID)) }.fetchAll(db).first
    })
    let secondStop = try #require(database.read { db in
      try Stop.where { $0.routeID.eq(#bind(secondRouteID)) }.fetchAll(db).first
    })
    let addressID = UUID()
    let firstPointID = UUID()
    let secondPointID = UUID()

    try database.write { db in
      try Address.insert { Address(id: addressID, street: "Shared Way") }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: firstPointID, stopID: firstStop.id) }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: secondPointID, stopID: secondStop.id) }.execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: firstPointID, addressID: addressID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: secondPointID, addressID: addressID)
      }
      .execute(db)
    }

    for runID in [firstRunID, secondRunID] {
      _ = try RunOperations.addParcel(
        runID: runID,
        addressID: addressID,
        source: "ocr",
        requiresSignature: false,
        isCustoms: false,
        toDoor: false,
        labelSnapshot: "Invented shared-address label",
        trackingCode: "",
        trackingSymbology: "",
        in: database
      )
    }

    let parcels = try database.read { db in try Parcel.all.fetchAll(db) }
    #expect(Set(parcels.map(\.runID)) == [firstRunID, secondRunID])
  }
}
