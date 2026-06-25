import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyPersistence
@testable import RouteySearch

@Suite struct SearchServiceTests {
  private func sharedCompartmentDatabase() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)

    try database.write { db in
      try SearchIndex.install(db)

      let routeID = UUID()
      let stopID = UUID()
      let moduleID = UUID()
      let deliveryPointID = UUID()
      let matchedAddressID = UUID()
      let sharedAddressID = UUID()
      let tagID = UUID()

      try Route.insert {
        Route(id: routeID, name: "Sample Route")
      }
      .execute(db)

      try Stop.insert {
        Stop(id: stopID, routeID: routeID, tieOut: "A1", sortIndex: 1, displayName: "Cornerstore")
      }
      .execute(db)

      try Module.insert {
        Module(id: moduleID, stopID: stopID, name: "Module 1", sortIndex: 1)
      }
      .execute(db)

      try DeliveryPoint.insert {
        DeliveryPoint(id: deliveryPointID, stopID: stopID, moduleID: moduleID, kind: "compartment", label: "M1-3")
      }
      .execute(db)

      try Address.insert {
        Address(id: matchedAddressID, civicNumber: 1284, street: "Concession Rd 6")
      }
      .execute(db)

      try Address.insert {
        Address(id: sharedAddressID, civicNumber: 1286, street: "Concession Rd 6")
      }
      .execute(db)

      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: matchedAddressID)
      }
      .execute(db)

      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: sharedAddressID)
      }
      .execute(db)

      try Tag.insert {
        Tag(id: tagID, name: "dog", isWarning: true)
      }
      .execute(db)

      try AddressTag.insert {
        AddressTag(addressID: matchedAddressID, tagID: tagID)
      }
      .execute(db)

      try SearchIndex.rebuild(from: db)
    }

    return database
  }

  @Test func searchReturnsLocatedSharedCompartmentHit() throws {
    let database = try sharedCompartmentDatabase()
    let service = SearchService(database: database)

    let hits = try service.search("1284")
    let hit = try #require(hits.first)

    #expect(hits.count == 1)
    #expect(hit.address.civicNumber == 1284)
    #expect(hit.stopNickname == "Cornerstore")
    #expect(hit.tieOut == "A1")
    #expect(hit.moduleName == "Module 1")
    #expect(hit.compartmentLabel == "M1-3")
    #expect(hit.sharedCivics == [1286])
    #expect(hit.tagNames.contains("dog"))

    let tag = try #require(hit.tags.first)
    #expect(tag.name == "dog")
    #expect(tag.isWarning)
  }
}
