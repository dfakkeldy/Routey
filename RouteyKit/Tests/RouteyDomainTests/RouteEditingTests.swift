import Foundation
import SQLiteData
import Testing
import RouteyModel
import RouteySearch
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RouteEditingTests {
  private struct SearchableAddressFixture {
    var addressID: Address.ID
  }

  private struct BorrowedRouteFixture {
    var routeID: Route.ID
    var stopID: Stop.ID
    var pointID: DeliveryPoint.ID
    var addressID: Address.ID
    var tagID: RouteyModel.Tag.ID
  }

  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func count(_ tableName: String, in database: DatabaseQueue) throws -> Int {
    try database.read { db in
      try Int.fetchOne(db, sql: "SELECT count(*) FROM \"\(tableName)\"") ?? -1
    }
  }

  private func seedBorrowedRoute(in database: DatabaseQueue) throws -> BorrowedRouteFixture {
    let routeID = UUID()
    let stopID = UUID()
    let pointID = UUID()
    let addressID = UUID()
    let tagID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Borrowed Route", isBorrowed: true) }.execute(db)
      try Stop.insert {
        Stop(id: stopID, routeID: routeID, tieOut: "A", displayName: "Borrowed stop")
      }
      .execute(db)
      try DeliveryPoint.insert {
        DeliveryPoint(id: pointID, stopID: stopID, label: "Borrowed point")
      }
      .execute(db)
      try Address.insert {
        Address(id: addressID, civicNumber: 2001, street: "Borrowed Example Lane")
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: pointID, addressID: addressID)
      }
      .execute(db)
      try Tag.insert { Tag(id: tagID, name: "borrowed marker") }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addressID, tagID: tagID) }.execute(db)
    }

    return BorrowedRouteFixture(
      routeID: routeID,
      stopID: stopID,
      pointID: pointID,
      addressID: addressID,
      tagID: tagID
    )
  }

  private func seedSearchableAddress(
    in database: DatabaseQueue,
    civicNumber: Int,
    street: String,
    occupantName: String? = nil,
    installSearchIndex: Bool = true
  ) throws -> SearchableAddressFixture {
    let routeID = UUID()
    let stopID = UUID()
    let pointID = UUID()
    let addressID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try Stop.insert {
        Stop(
          id: stopID,
          routeID: routeID,
          tieOut: "A",
          sortIndex: 0,
          kind: "pointOfCall",
          displayName: "Sample Stop"
        )
      }
      .execute(db)
      try DeliveryPoint.insert {
        DeliveryPoint(id: pointID, stopID: stopID, label: "Sample Point")
      }
      .execute(db)
      try Address.insert {
        Address(
          id: addressID,
          civicNumber: civicNumber,
          street: street,
          occupantName: occupantName
        )
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: pointID, addressID: addressID)
      }
      .execute(db)

      if installSearchIndex {
        try SearchIndex.install(db)
        try SearchIndex.rebuild(from: db)
      }
    }

    return SearchableAddressFixture(addressID: addressID)
  }

  @Test func addStopInsertsBetweenSiblingsUsingFractionalSortIndex() throws {
    let database = try freshDB()
    let routeID = UUID()
    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
    }

    let firstID = try RouteEditing.addStop(
      routeID: routeID,
      tieOut: "1",
      displayName: "First stop",
      after: nil,
      into: database
    )
    let thirdID = try RouteEditing.addStop(
      routeID: routeID,
      tieOut: "3",
      displayName: "Third stop",
      after: firstID,
      into: database
    )
    let secondID = try RouteEditing.addStop(
      routeID: routeID,
      tieOut: "2",
      displayName: "Second stop",
      after: firstID,
      into: database
    )

    let stops = try database.read { db in
      try Stop.all.order { $0.sortIndex }.fetchAll(db)
    }

    #expect(stops.map(\.id) == [firstID, secondID, thirdID])
    #expect(stops.map(\.displayName) == ["First stop", "Second stop", "Third stop"])
    #expect(stops.map(\.sortIndex) == [0.0, 0.5, 1.0])
  }

  @Test func updateStopChangesDisplayNameAndTieOut() throws {
    let database = try freshDB()
    let routeID = UUID()
    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
    }
    let stopID = try RouteEditing.addStop(
      routeID: routeID,
      tieOut: "A",
      displayName: "Original stop",
      after: nil,
      into: database
    )

    try RouteEditing.updateStopDisplayName(stopID, to: "Edited stop", in: database)
    try RouteEditing.updateStopTieOut(stopID, to: "B", in: database)

    let stop = try #require(try database.read { db in
      try Stop.all.fetchAll(db).first { $0.id == stopID }
    })
    #expect(stop.displayName == "Edited stop")
    #expect(stop.tieOut == "B")
  }

  @Test func deleteStopCascadesOwnedDeliveryPointsAndLinks() throws {
    let database = try freshDB()
    let routeID = UUID()
    let addressID = UUID()
    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try Address.insert {
        Address(id: addressID, civicNumber: 10, street: "Placeholder Road")
      }
      .execute(db)
    }
    let stopID = try RouteEditing.addStop(
      routeID: routeID,
      tieOut: "1",
      displayName: "Stop to delete",
      after: nil,
      into: database
    )
    let pointID = UUID()
    try database.write { db in
      try DeliveryPoint.insert {
        DeliveryPoint(id: pointID, stopID: stopID, label: "Box")
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: pointID, addressID: addressID)
      }
      .execute(db)
    }

    try RouteEditing.deleteStop(stopID, in: database)

    #expect(try count("stops", in: database) == 0)
    #expect(try count("deliveryPoints", in: database) == 0)
    #expect(try count("deliveryPointAddresses", in: database) == 0)
    #expect(try count("addresses", in: database) == 1)
  }

  @Test func addAddressCreatesAddressAndDeliveryPointLink() throws {
    let database = try freshDB()
    let routeID = UUID()
    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
    }
    let stopID = try RouteEditing.addStop(
      routeID: routeID,
      tieOut: "1",
      displayName: "Shared point",
      after: nil,
      into: database
    )
    let pointID = UUID()
    let address = Address(
      civicNumber: 24,
      street: "Example Lane",
      occupantName: "Sample Occupant",
      notes: "Leave at side shelf"
    )
    try database.write { db in
      try DeliveryPoint.insert {
        DeliveryPoint(id: pointID, stopID: stopID, label: "Shared point")
      }
      .execute(db)
    }

    try RouteEditing.addAddress(address, toDeliveryPoint: pointID, in: database)

    let addresses = try database.read { db in try Address.all.fetchAll(db) }
    let links = try database.read { db in try DeliveryPointAddress.all.fetchAll(db) }
    #expect(addresses.map(\.id) == [address.id])
    #expect(links.map(\.addressID) == [address.id])
    #expect(links.map(\.deliveryPointID) == [pointID])
  }

  @Test func updateAddressChangesEditableFields() throws {
    let database = try freshDB()
    let addressID = UUID()
    try database.write { db in
      try Address.insert {
        Address(id: addressID, civicNumber: 12, street: "Old Placeholder Road", occupantName: "Original")
      }
      .execute(db)
    }

    try RouteEditing.updateAddress(
      addressID,
      civicNumber: 88,
      street: "New Placeholder Road",
      occupantName: nil,
      notes: "Updated note",
      in: database
    )

    let address = try #require(try database.read { db in
      try Address.all.fetchAll(db).first { $0.id == addressID }
    })
    #expect(address.civicNumber == 88)
    #expect(address.street == "New Placeholder Road")
    #expect(address.occupantName == nil)
    #expect(address.notes == "Updated note")
  }

  @Test func updateAddressKeepsSearchServiceFresh() throws {
    let database = try freshDB()
    let fixture = try seedSearchableAddress(
      in: database,
      civicNumber: 4200,
      street: "Old Placeholder Road",
      occupantName: "Original Placeholder"
    )
    let service = SearchService(database: database)

    try RouteEditing.updateAddress(
      fixture.addressID,
      civicNumber: 4200,
      street: "New Placeholder Road",
      occupantName: "Updated Placeholder",
      notes: "Updated note",
      in: database
    )

    let oldHits = try service.search("Old Placeholder")
    let newHits = try service.search("New Placeholder")
    let occupantHits = try service.search("Updated Placeholder")

    #expect(oldHits.isEmpty)
    #expect(newHits.map(\.address.id) == [fixture.addressID])
    #expect(occupantHits.map(\.address.id) == [fixture.addressID])
  }

  @Test func attachAndDetachTagAreIdempotent() throws {
    let database = try freshDB()
    let addressID = UUID()
    try database.write { db in
      try Address.insert {
        Address(id: addressID, street: "Example Lane")
      }
      .execute(db)
    }

    let firstTagID = try RouteEditing.attachTag(
      named: "porch alert",
      toAddress: addressID,
      isWarning: true,
      in: database
    )
    let secondTagID = try RouteEditing.attachTag(
      named: "porch alert",
      toAddress: addressID,
      isWarning: true,
      in: database
    )

    #expect(firstTagID == secondTagID)
    #expect(try count("tags", in: database) == 1)
    #expect(try count("addressTags", in: database) == 1)

    try RouteEditing.detachTag(firstTagID, fromAddress: addressID, in: database)
    try RouteEditing.detachTag(firstTagID, fromAddress: addressID, in: database)

    #expect(try count("addressTags", in: database) == 0)
    #expect(try count("tags", in: database) == 1)
  }

  @Test func attachAndDetachTagKeepSearchServiceFresh() throws {
    let database = try freshDB()
    let fixture = try seedSearchableAddress(
      in: database,
      civicNumber: 4210,
      street: "Taggable Placeholder Road",
      installSearchIndex: false
    )
    let service = SearchService(database: database)

    let tagID = try RouteEditing.attachTag(
      named: "porch marker",
      toAddress: fixture.addressID,
      isWarning: true,
      in: database
    )

    var hit = try #require(try service.search("Taggable Placeholder").first)
    #expect(hit.tagNames == ["porch marker"])
    #expect(hit.tags.first?.isWarning == true)

    try RouteEditing.detachTag(tagID, fromAddress: fixture.addressID, in: database)

    hit = try #require(try service.search("Taggable Placeholder").first)
    #expect(hit.tagNames.isEmpty)
  }

  @Test func borrowedRouteRejectsAddStopWithoutMutating() throws {
    let database = try freshDB()
    let fixture = try seedBorrowedRoute(in: database)
    let initialStopCount = try count("stops", in: database)

    #expect(throws: RouteEditingError.routeIsBorrowed) {
      _ = try RouteEditing.addStop(
        routeID: fixture.routeID,
        tieOut: "B",
        displayName: "New stop",
        after: fixture.stopID,
        into: database
      )
    }

    #expect(try count("stops", in: database) == initialStopCount)
  }

  @Test func borrowedRouteRejectsAddressAndTagMutationsWithoutMutating() throws {
    let database = try freshDB()
    let fixture = try seedBorrowedRoute(in: database)
    let initialAddressCount = try count("addresses", in: database)
    let initialTagLinkCount = try count("addressTags", in: database)

    #expect(throws: RouteEditingError.routeIsBorrowed) {
      try RouteEditing.addAddress(
        Address(civicNumber: 2003, street: "Borrowed Example Lane"),
        toDeliveryPoint: fixture.pointID,
        in: database
      )
    }
    #expect(throws: RouteEditingError.routeIsBorrowed) {
      try RouteEditing.updateAddress(
        fixture.addressID,
        civicNumber: 2005,
        street: "Changed Example Lane",
        occupantName: nil,
        notes: "Should not save",
        in: database
      )
    }
    #expect(throws: RouteEditingError.routeIsBorrowed) {
      _ = try RouteEditing.attachTag(
        named: "new borrowed marker",
        toAddress: fixture.addressID,
        isWarning: false,
        in: database
      )
    }
    #expect(throws: RouteEditingError.routeIsBorrowed) {
      try RouteEditing.detachTag(fixture.tagID, fromAddress: fixture.addressID, in: database)
    }

    let address = try #require(try database.read { db in
      try Address.all.fetchAll(db).first { $0.id == fixture.addressID }
    })
    #expect(address.civicNumber == 2001)
    #expect(address.street == "Borrowed Example Lane")
    #expect(try count("addresses", in: database) == initialAddressCount)
    #expect(try count("addressTags", in: database) == initialTagLinkCount)
  }
}
