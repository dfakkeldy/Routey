import Testing
import Foundation
import SQLiteData
import RouteyModel
@testable import RouteyPersistence

@Suite struct CRUDTests {
  private func freshDB() throws -> DatabaseQueue {
    let db = try DatabaseQueue()
    try Schema.migrator.migrate(db)
    return db
  }

  @Test func insertAndFetchRoute() throws {
    let db = try freshDB()
    let id = UUID()

    try db.write { db in
      try Route.insert { Route(id: id, name: "Riverbend", rtaFSA: "A1A") }.execute(db)
    }

    let routes = try db.read { db in try Route.all.fetchAll(db) }
    #expect(routes.count == 1)
    #expect(routes.first?.id == id)
    #expect(routes.first?.name == "Riverbend")
  }
}
