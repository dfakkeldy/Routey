import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RouteAddressLookupTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  @Test func addressesAreScopedToTheSelectedRoute() throws {
    let database = try freshDB()
    let selectedRouteID = UUID()
    let otherRouteID = UUID()
    let selectedStopID = UUID()
    let otherStopID = UUID()
    let selectedPointID = UUID()
    let otherPointID = UUID()
    let selectedAddressID = UUID()
    let otherAddressID = UUID()
    let sharedAddressID = UUID()

    try database.write { db in
      try Route.insert { Route(id: selectedRouteID, name: "Sample Route") }.execute(db)
      try Route.insert { Route(id: otherRouteID, name: "Backup Route") }.execute(db)
      try Stop.insert { Stop(id: selectedStopID, routeID: selectedRouteID) }.execute(db)
      try Stop.insert { Stop(id: otherStopID, routeID: otherRouteID) }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: selectedPointID, stopID: selectedStopID) }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: otherPointID, stopID: otherStopID) }.execute(db)
      try Address.insert {
        Address(id: selectedAddressID, civicNumber: 101, street: "Sample Road")
      }
      .execute(db)
      try Address.insert {
        Address(id: otherAddressID, civicNumber: 202, street: "Backup Road")
      }
      .execute(db)
      try Address.insert {
        Address(id: sharedAddressID, civicNumber: 303, street: "Shared Way")
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: selectedPointID, addressID: selectedAddressID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: otherPointID, addressID: otherAddressID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: selectedPointID, addressID: sharedAddressID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: otherPointID, addressID: sharedAddressID)
      }
      .execute(db)
    }

    let selectedAddresses = try database.read { db in
      try RouteAddressLookup.addresses(routeID: selectedRouteID, in: db)
    }
    let otherAddresses = try database.read { db in
      try RouteAddressLookup.addresses(routeID: otherRouteID, in: db)
    }

    #expect(selectedAddresses.map(\.id) == [selectedAddressID, sharedAddressID])
    #expect(otherAddresses.map(\.id) == [otherAddressID, sharedAddressID])
  }
}
