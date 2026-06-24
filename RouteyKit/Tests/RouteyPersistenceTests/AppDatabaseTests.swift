import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyPersistence

@Suite struct AppDatabaseTests {
  @Test func appDatabaseRunsMigrationsAndAcceptsWrites() throws {
    let database = try appDatabase()
    let routeID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Riverbend") }.execute(db)
    }

    let routeCount = try database.read { db in
      try Route.all.fetchAll(db).count
    }

    #expect(routeCount == 1)
  }
}
