import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyExport
@testable import RouteyPersistence

@Suite struct ExportImportRoundTripTests {
  private struct RouteGraphFixture {
    var routeID: Route.ID
    var stopIDs: [Stop.ID]
    var moduleIDs: [Module.ID]
    var deliveryPointIDs: [DeliveryPoint.ID]
    var addressIDs: [Address.ID]
    var tagIDs: [RouteyModel.Tag.ID]
  }

  private let passphrase = "sample handoff phrase"
  private let iterations: UInt32 = 100_000

  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func seedInventedRouteGraph(in database: DatabaseQueue) throws -> RouteGraphFixture {
    let routeID = UUID()
    let stopID = UUID()
    let moduleAID = UUID()
    let moduleBID = UUID()
    let compartmentOneID = UUID()
    let compartmentTwoID = UUID()
    let addressOneID = UUID()
    let addressTwoID = UUID()
    let addressThreeID = UUID()
    let tagAlertID = UUID()
    let tagNoteID = UUID()

    try database.write { db in
      try Route.insert {
        Route(id: routeID, name: "Sample Handoff Route", rtaFSA: "X0X")
      }
      .execute(db)
      try Stop.insert {
        Stop(
          id: stopID,
          routeID: routeID,
          tieOut: "A",
          sortIndex: 0,
          kind: "cmbSite",
          displayName: "North Kiosk",
          officialSiteID: "SITE-001",
          locationText: "Beside the sample green",
          notes: "Invented shared stop"
        )
      }
      .execute(db)
      try Module.insert { Module(id: moduleAID, stopID: stopID, name: "Module A", sortIndex: 0) }
        .execute(db)
      try Module.insert { Module(id: moduleBID, stopID: stopID, name: "Module B", sortIndex: 1) }
        .execute(db)
      try DeliveryPoint.insert {
        DeliveryPoint(
          id: compartmentOneID,
          stopID: stopID,
          moduleID: moduleAID,
          kind: "compartment",
          label: "A1",
          notes: "Shared compartment"
        )
      }
      .execute(db)
      try DeliveryPoint.insert {
        DeliveryPoint(
          id: compartmentTwoID,
          stopID: stopID,
          moduleID: moduleBID,
          kind: "compartment",
          label: "B4",
          isParcelLocker: true,
          notes: "Parcel compartment"
        )
      }
      .execute(db)
      try Address.insert {
        Address(
          id: addressOneID,
          civicNumber: 1001,
          suite: "1A",
          street: "Example Lane",
          occupantName: "Sample Resident",
          postalCode: "X0X 0X0",
          notes: "Invented address"
        )
      }
      .execute(db)
      try Address.insert {
        Address(
          id: addressTwoID,
          civicNumber: 1003,
          street: "Example Lane",
          occupantName: "Placeholder Household"
        )
      }
      .execute(db)
      try Address.insert {
        Address(
          id: addressThreeID,
          civicRangeFrom: 1010,
          civicRangeTo: 1014,
          street: "Sample Crescent",
          notes: "Range placeholder"
        )
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: compartmentOneID, addressID: addressOneID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: compartmentOneID, addressID: addressTwoID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: compartmentTwoID, addressID: addressThreeID)
      }
      .execute(db)
      try Tag.insert { Tag(id: tagAlertID, name: "gate note", isWarning: true) }.execute(db)
      try Tag.insert { Tag(id: tagNoteID, name: "side shelf") }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addressOneID, tagID: tagAlertID) }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addressThreeID, tagID: tagNoteID) }.execute(db)
    }

    return RouteGraphFixture(
      routeID: routeID,
      stopIDs: [stopID],
      moduleIDs: [moduleAID, moduleBID],
      deliveryPointIDs: [compartmentOneID, compartmentTwoID],
      addressIDs: [addressOneID, addressTwoID, addressThreeID],
      tagIDs: [tagAlertID, tagNoteID]
    )
  }

  @Test func buildDTOCapturesReachableRouteGraph() throws {
    let database = try freshDB()
    let fixture = try seedInventedRouteGraph(in: database)

    let dto = try DTOMapping.buildDTO(routeID: fixture.routeID, from: database)

    #expect(dto.route.id == fixture.routeID)
    #expect(dto.stops.count == 1)
    #expect(dto.modules.count == 2)
    #expect(dto.deliveryPoints.count == 2)
    #expect(dto.addresses.count == 3)
    #expect(dto.tags.count == 2)
    #expect(dto.deliveryPointAddresses.count == 3)
    #expect(dto.addressTags.count == 2)
  }

  @Test func encryptedExportImportsAsBorrowedRouteWithFreshIDs() throws {
    let sourceDB = try freshDB()
    let fixture = try seedInventedRouteGraph(in: sourceDB)

    let blob = try RouteExporter.export(
      routeID: fixture.routeID,
      passphrase: passphrase,
      iterations: iterations,
      from: sourceDB
    )
    let destinationDB = try freshDB()
    let importedRouteID = try EncryptedRouteImporter.import(blob, passphrase: passphrase, into: destinationDB)

    let importedRoute = try #require(try destinationDB.read { db in
      try Route.all.fetchAll(db).first { $0.id == importedRouteID }
    })
    #expect(importedRoute.id != fixture.routeID)
    #expect(importedRoute.name == "Sample Handoff Route")
    #expect(importedRoute.rtaFSA == "X0X")
    #expect(importedRoute.isBorrowed)

    let stops = try destinationDB.read { db in try Stop.all.fetchAll(db) }
    let modules = try destinationDB.read { db in try Module.all.fetchAll(db) }
    let deliveryPoints = try destinationDB.read { db in try DeliveryPoint.all.fetchAll(db) }
    let addresses = try destinationDB.read { db in try Address.all.fetchAll(db) }
    let tags = try destinationDB.read { db in try Tag.all.fetchAll(db) }
    let deliveryPointAddresses = try destinationDB.read { db in try DeliveryPointAddress.all.fetchAll(db) }
    let addressTags = try destinationDB.read { db in try AddressTag.all.fetchAll(db) }

    #expect(stops.count == 1)
    #expect(modules.count == 2)
    #expect(deliveryPoints.count == 2)
    #expect(addresses.count == 3)
    #expect(tags.count == 2)
    #expect(deliveryPointAddresses.count == 3)
    #expect(addressTags.count == 2)
    #expect(Set(stops.map(\.id)).isDisjoint(with: fixture.stopIDs))
    #expect(Set(modules.map(\.id)).isDisjoint(with: fixture.moduleIDs))
    #expect(Set(deliveryPoints.map(\.id)).isDisjoint(with: fixture.deliveryPointIDs))
    #expect(Set(addresses.map(\.id)).isDisjoint(with: fixture.addressIDs))
    #expect(Set(tags.map(\.id)).isDisjoint(with: fixture.tagIDs))
    #expect(stops.map(\.routeID) == [importedRouteID])

    let importedStopIDs = Set(stops.map(\.id))
    let importedModuleIDs = Set(modules.map(\.id))
    let importedDeliveryPointIDs = Set(deliveryPoints.map(\.id))
    let importedAddressIDs = Set(addresses.map(\.id))
    let importedTagIDs = Set(tags.map(\.id))

    #expect(modules.allSatisfy { importedStopIDs.contains($0.stopID) })
    #expect(deliveryPoints.allSatisfy { point in
      importedStopIDs.contains(point.stopID)
        && point.moduleID.map { importedModuleIDs.contains($0) } != false
    })
    #expect(deliveryPointAddresses.allSatisfy { link in
      importedDeliveryPointIDs.contains(link.deliveryPointID)
        && importedAddressIDs.contains(link.addressID)
    })
    #expect(addressTags.allSatisfy { link in
      importedAddressIDs.contains(link.addressID)
        && importedTagIDs.contains(link.tagID)
    })
    #expect(Set(tags.map(\.name)) == Set(["gate note", "side shelf"]))
  }

  @Test func encryptedImportRejectsWrongPassphrase() throws {
    let sourceDB = try freshDB()
    let fixture = try seedInventedRouteGraph(in: sourceDB)
    let blob = try RouteExporter.export(
      routeID: fixture.routeID,
      passphrase: passphrase,
      iterations: iterations,
      from: sourceDB
    )
    let destinationDB = try freshDB()

    #expect(throws: RouteyCryptoError.wrongPassphraseOrCorrupt) {
      _ = try EncryptedRouteImporter.import(blob, passphrase: "not the phrase", into: destinationDB)
    }
    #expect(try destinationDB.read { db in try Route.all.fetchAll(db).isEmpty })
  }
}
