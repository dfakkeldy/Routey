import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct CoordinateResolutionTests {
  private struct CoordinateFixture {
    var routeID: Route.ID
    var missingAddressID: Address.ID
    var cachedAddressID: Address.ID
    var missingStopID: Stop.ID
    var cachedStopID: Stop.ID
  }

  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func seedCoordinateFixture(in database: DatabaseQueue) throws -> CoordinateFixture {
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

    return CoordinateFixture(
      routeID: routeID,
      missingAddressID: missingAddressID,
      cachedAddressID: cachedAddressID,
      missingStopID: missingStopID,
      cachedStopID: cachedStopID
    )
  }

  @Test func candidatesIncludeOnlyMissingAddressCoordinates() throws {
    let database = try freshDB()
    let fixture = try seedCoordinateFixture(in: database)

    let candidates = try CoordinateResolution.candidates(routeID: fixture.routeID, in: database)

    #expect(candidates == [
      AddressResolutionCandidate(
        addressID: fixture.missingAddressID,
        stopID: fixture.missingStopID,
        query: "101 Sample Road"
      ),
    ])
  }

  @Test func resolveMissingCoordinatesCachesAddressAndStopCoordinates() async throws {
    let database = try freshDB()
    let fixture = try seedCoordinateFixture(in: database)
    let service = CoordinateResolutionService { query in
      #expect(query == "101 Sample Road")
      return ResolvedCoordinate(latitude: 45.1, longitude: -63.2)
    }

    let resolvedCount = try await service.resolveMissingCoordinates(routeID: fixture.routeID, in: database)

    #expect(resolvedCount == 1)

    let fetchedAddress = try await database.read { db in
      try Address.find(fixture.missingAddressID).fetchOne(db)
    }
    let address = try #require(fetchedAddress)
    #expect(address.doorLatitude == 45.1)
    #expect(address.doorLongitude == -63.2)

    let fetchedStop = try await database.read { db in
      try Stop.find(fixture.missingStopID).fetchOne(db)
    }
    let stop = try #require(fetchedStop)
    #expect(stop.latitude == 45.1)
    #expect(stop.longitude == -63.2)
  }
}
