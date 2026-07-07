import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct CoordinateResolutionTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  @Test func candidatesIncludeOnlyMissingAddressCoordinates() throws {
    let database = try freshDB()
    let routeID = UUID()
    let missingAddressID = UUID()
    let cachedAddressID = UUID()
    let missingStopID = UUID()
    let cachedStopID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try Stop.insert {
        Stop(id: missingStopID, routeID: routeID, tieOut: "A", sortIndex: 0, displayName: "First stop")
      }
      .execute(db)
      try Stop.insert {
        Stop(
          id: cachedStopID,
          routeID: routeID,
          tieOut: "B",
          sortIndex: 1,
          displayName: "Second stop",
          latitude: 45.2,
          longitude: -63.3
        )
      }
      .execute(db)

      let missingPointID = UUID()
      let cachedPointID = UUID()
      try DeliveryPoint.insert { DeliveryPoint(id: missingPointID, stopID: missingStopID, label: "Box A") }
        .execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: cachedPointID, stopID: cachedStopID, label: "Box B") }
        .execute(db)

      try Address.insert {
        Address(id: missingAddressID, civicNumber: 101, street: "Sample Road")
      }
      .execute(db)
      try Address.insert {
        Address(
          id: cachedAddressID,
          civicNumber: 202,
          street: "Example Lane",
          doorLatitude: 45.2,
          doorLongitude: -63.3
        )
      }
      .execute(db)

      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: missingPointID, addressID: missingAddressID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: cachedPointID, addressID: cachedAddressID)
      }
      .execute(db)
    }

    let candidates = try CoordinateResolution.candidates(routeID: routeID, in: database)

    #expect(candidates == [
      AddressResolutionCandidate(
        addressID: missingAddressID,
        stopID: missingStopID,
        query: "101 Sample Road"
      ),
    ])
  }
}
