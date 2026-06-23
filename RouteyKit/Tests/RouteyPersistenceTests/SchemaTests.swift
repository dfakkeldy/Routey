import Testing
import SQLiteData
@testable import RouteyPersistence

@Suite struct SchemaTests {
  @Test func migrationCreatesAllTables() throws {
    let db = try DatabaseQueue()              // in-memory
    try Schema.migrator.migrate(db)

    let tables = try db.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
      )
    }

    for expected in [
      "routes", "stops", "modules", "deliveryPoints",
      "addresses", "deliveryPointAddresses", "tags", "addressTags",
    ] {
      #expect(tables.contains(expected), "missing table \(expected)")
    }
  }
}
