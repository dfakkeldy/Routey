import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RunStopDetailTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  @Test func detailHydratesAddressesParcelsAndWarnings() throws {
    let database = try freshDB()
    let routeID = UUID()
    let stopID = UUID()
    let deliveryPointID = UUID()
    let addressID = UUID()
    let dogTagID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try Stop.insert {
        Stop(id: stopID, routeID: routeID, tieOut: "1", sortIndex: 0, displayName: "Stop A")
      }
      .execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: deliveryPointID, stopID: stopID) }.execute(db)
      try Address.insert {
        Address(id: addressID, civicNumber: 101, street: "Maple Road", occupantName: "Pat Lee")
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: addressID)
      }
      .execute(db)
      try Tag.insert { Tag(id: dogTagID, name: "dog", isWarning: true) }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addressID, tagID: dogTagID) }.execute(db)
    }

    let runID = try RunGeneration.generate(
      routeID: routeID,
      serviceDate: "2026-06-29",
      now: Date(timeIntervalSince1970: 1_782_000_000),
      into: database
    )
    try RunOperations.addParcel(
      runID: runID,
      addressID: addressID,
      source: "ocr",
      requiresSignature: true,
      isCustoms: false,
      toDoor: false,
      labelSnapshot: "101 Maple",
      trackingCode: "ZX1",
      trackingSymbology: "",
      in: database
    )
    let runStop = try #require(try database.read { db in
      try RunStop
        .where { $0.runID.eq(#bind(runID)) }
        .fetchAll(db)
        .first { $0.stopID == stopID }
    })

    let detail = try database.read { db in
      try RunStopDetail.load(runStopID: runStop.id, runID: runID, db)
    }

    #expect(detail.addresses.map(\.street) == ["Maple Road"])
    #expect(detail.addresses.first?.occupant == "Pat Lee")
    #expect(detail.addresses.first?.civic == "101")
    #expect(detail.parcels.map(\.trackingCode) == ["ZX1"])
    #expect(detail.parcels.first?.requiresSignature == true)
    #expect(detail.warningTags == ["dog"])
  }
}
