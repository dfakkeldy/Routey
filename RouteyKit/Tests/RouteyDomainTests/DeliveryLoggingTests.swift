import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct DeliveryLoggingTests {
  private struct CompartmentFixture {
    var runID: TodaysRun.ID
    var runStopID: RunStop.ID
    var stopID: Stop.ID
    var addressID: Address.ID
  }

  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func deliveryRecordCount(in database: DatabaseQueue) throws -> Int {
    try database.read { db in
      try DeliveryRecord.all.fetchAll(db).count
    }
  }

  private func seedCompartmentRun(in database: DatabaseQueue) throws -> CompartmentFixture {
    let routeID = UUID()
    let stopID = UUID()
    let moduleID = UUID()
    let deliveryPointID = UUID()
    let addressID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try Stop.insert {
        Stop(
          id: stopID,
          routeID: routeID,
          tieOut: "A",
          sortIndex: 0,
          kind: "cmbSite",
          displayName: "Shared Compartment Site"
        )
      }
      .execute(db)
      try Module.insert { Module(id: moduleID, stopID: stopID, name: "Module North") }
        .execute(db)
      try DeliveryPoint.insert {
        DeliveryPoint(
          id: deliveryPointID,
          stopID: stopID,
          moduleID: moduleID,
          kind: "compartment",
          label: "Slot 7"
        )
      }
      .execute(db)
      try Address.insert {
        Address(id: addressID, civicNumber: 101, street: "Placeholder Road")
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: addressID)
      }
      .execute(db)
    }

    let runID = try RunGeneration.generate(
      routeID: routeID,
      serviceDate: "2026-06-22",
      now: Date(timeIntervalSince1970: 1_782_000_000),
      into: database
    )
    let runStop = try #require(try database.read { db in
      try RunStop.where { $0.runID.eq(#bind(runID)) }.fetchAll(db).first
    })

    return CompartmentFixture(
      runID: runID,
      runStopID: runStop.id,
      stopID: stopID,
      addressID: addressID
    )
  }

  @Test func notHomeCardedForCompartmentAddressCreatesTargetedFollowUpTask() throws {
    let database = try freshDB()
    let fixture = try seedCompartmentRun(in: database)

    _ = try RunOperations.logDelivery(
      runID: fixture.runID,
      runStopID: fixture.runStopID,
      parcelID: nil,
      addressID: fixture.addressID,
      outcome: "notHomeCarded",
      location: nil,
      photoPath: nil,
      loggedAt: Date(timeIntervalSince1970: 1_782_003_600),
      in: database
    )

    let tasks = try database.read { db in
      try FollowUpTask.where { $0.runID.eq(#bind(fixture.runID)) }.fetchAll(db)
    }
    let task = try #require(tasks.first)

    #expect(tasks.count == 1)
    #expect(task.targetStopID == fixture.stopID)
    #expect(task.addressID == fixture.addressID)
    #expect(task.text.localizedStandardContains("Module North"))
    #expect(task.text.localizedStandardContains("Slot 7"))
    #expect(!task.isDone)
  }

  @Test func safedropWithParcelLogsRecordMarksParcelDeliveredAndCreatesNoTask() throws {
    let database = try freshDB()
    let fixture = try seedCompartmentRun(in: database)
    let parcelID = try RunOperations.addParcel(
      runID: fixture.runID,
      addressID: fixture.addressID,
      source: "manual",
      sizeClass: "medium",
      requiresSignature: true,
      isCustoms: false,
      toDoor: true,
      labelSnapshot: "Sample parcel label",
      trackingCode: "TRACK-003",
      trackingSymbology: "code128",
      in: database
    )
    let loggedAt = Date(timeIntervalSince1970: 1_782_003_900)

    let recordID = try RunOperations.logDelivery(
      runID: fixture.runID,
      runStopID: fixture.runStopID,
      parcelID: parcelID,
      addressID: fixture.addressID,
      outcome: "safedrop",
      location: (lat: 45.1, lon: -63.2),
      photoPath: "proofs/sample-photo.jpg",
      loggedAt: loggedAt,
      in: database
    )

    let record = try #require(try database.read { db in
      try DeliveryRecord.find(recordID).fetchOne(db)
    })
    let parcel = try #require(try database.read { db in
      try Parcel.find(parcelID).fetchOne(db)
    })
    let taskCount = try database.read { db in
      try FollowUpTask.where { $0.runID.eq(#bind(fixture.runID)) }.fetchAll(db).count
    }

    #expect(record.runID == fixture.runID)
    #expect(record.addressID == fixture.addressID)
    #expect(record.parcelID == parcelID)
    #expect(record.outcome == "safedrop")
    #expect(record.latitude == 45.1)
    #expect(record.longitude == -63.2)
    #expect(record.loggedAt == loggedAt)
    #expect(record.photoPath == "proofs/sample-photo.jpg")
    #expect(parcel.isDelivered)
    #expect(taskCount == 0)
  }

  @Test func logDeliveryThrowsForMissingRunStopWithoutInsertingRecord() throws {
    let database = try freshDB()
    let fixture = try seedCompartmentRun(in: database)

    #expect(throws: (any Error).self) {
      try RunOperations.logDelivery(
        runID: fixture.runID,
        runStopID: UUID(),
        parcelID: nil,
        addressID: fixture.addressID,
        outcome: "safedrop",
        location: nil,
        photoPath: nil,
        loggedAt: Date(timeIntervalSince1970: 1_782_004_000),
        in: database
      )
    }

    #expect(try deliveryRecordCount(in: database) == 0)
  }

  @Test func logDeliveryThrowsForCrossRunRunStopWithoutInsertingRecord() throws {
    let database = try freshDB()
    let firstFixture = try seedCompartmentRun(in: database)
    let secondFixture = try seedCompartmentRun(in: database)

    #expect(throws: (any Error).self) {
      try RunOperations.logDelivery(
        runID: firstFixture.runID,
        runStopID: secondFixture.runStopID,
        parcelID: nil,
        addressID: firstFixture.addressID,
        outcome: "safedrop",
        location: nil,
        photoPath: nil,
        loggedAt: Date(timeIntervalSince1970: 1_782_004_100),
        in: database
      )
    }

    #expect(try deliveryRecordCount(in: database) == 0)
  }

  @Test func logDeliveryThrowsForCrossRunParcelWithoutInsertingOrMarkingDelivered() throws {
    let database = try freshDB()
    let firstFixture = try seedCompartmentRun(in: database)
    let secondFixture = try seedCompartmentRun(in: database)
    let crossRunParcelID = try RunOperations.addParcel(
      runID: secondFixture.runID,
      addressID: secondFixture.addressID,
      source: "manual",
      sizeClass: "medium",
      requiresSignature: true,
      isCustoms: false,
      toDoor: true,
      labelSnapshot: "Other run sample parcel",
      trackingCode: "TRACK-004",
      trackingSymbology: "code128",
      in: database
    )

    #expect(throws: (any Error).self) {
      try RunOperations.logDelivery(
        runID: firstFixture.runID,
        runStopID: firstFixture.runStopID,
        parcelID: crossRunParcelID,
        addressID: firstFixture.addressID,
        outcome: "safedrop",
        location: nil,
        photoPath: nil,
        loggedAt: Date(timeIntervalSince1970: 1_782_004_200),
        in: database
      )
    }

    let parcel = try #require(try database.read { db in
      try Parcel.find(crossRunParcelID).fetchOne(db)
    })
    #expect(try deliveryRecordCount(in: database) == 0)
    #expect(!parcel.isDelivered)
  }
}
