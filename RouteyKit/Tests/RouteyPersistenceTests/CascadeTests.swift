import Testing
import Foundation
import SQLiteData
import RouteyModel
@testable import RouteyPersistence

@Suite struct CascadeTests {
  private func freshDB() throws -> DatabaseQueue {
    let db = try DatabaseQueue()
    try Schema.migrator.migrate(db)
    return db
  }

  private func count(_ db: DatabaseQueue, _ table: String) throws -> Int {
    try db.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM \"\(table)\"") ?? -1 }
  }

  @Test func deletingRouteCascadesOwnedRowsButKeepsAddressesAndTags() throws {
    let db = try freshDB()
    let routeID = UUID(), stopID = UUID(), moduleID = UUID()
    let pointID = UUID(), addressID = UUID(), tagID = UUID()

    try db.write { db in
      try Route.insert { Route(id: routeID, name: "R") }.execute(db)
      try Stop.insert { Stop(id: stopID, routeID: routeID, kind: "cmbSite", displayName: "Cornerstore") }.execute(db)
      try Module.insert { Module(id: moduleID, stopID: stopID, name: "1") }.execute(db)
      try DeliveryPoint.insert {
        DeliveryPoint(id: pointID, stopID: stopID, moduleID: moduleID, kind: "compartment", label: "1A")
      }.execute(db)
      try Address.insert { Address(id: addressID, civicNumber: 31, street: "Elm St", occupantName: "Alex") }.execute(db)
      try Tag.insert { Tag(id: tagID, name: "dog", isWarning: true) }.execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: pointID, addressID: addressID)
      }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addressID, tagID: tagID) }.execute(db)
    }

    // Sanity: everything inserted.
    #expect(try count(db, "stops") == 1)
    #expect(try count(db, "deliveryPointAddresses") == 1)

    // Delete the route.
    // StructuredQueries stores UUIDs as lowercased strings (see QueryBinding.databaseValue),
    // so match that encoding when using raw SQL.
    try db.write { db in
      try db.execute(sql: "DELETE FROM \"routes\" WHERE \"id\" = ?", arguments: [routeID.uuidString.lowercased()])
    }

    // Owned rows cascade away.
    #expect(try count(db, "routes") == 0)
    #expect(try count(db, "stops") == 0)
    #expect(try count(db, "modules") == 0)
    #expect(try count(db, "deliveryPoints") == 0)
    #expect(try count(db, "deliveryPointAddresses") == 0)

    // Shared, route-independent rows survive (addresses can belong to other stops; tags are global).
    #expect(try count(db, "addresses") == 1)
    #expect(try count(db, "tags") == 1)

    // The address↔tag join is owned by the (surviving) address, so it survives too.
    #expect(try count(db, "addressTags") == 1)
  }
}
