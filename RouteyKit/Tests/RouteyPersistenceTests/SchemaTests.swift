import Testing
import Foundation
import SQLiteData
@testable import RouteyPersistence

@Suite struct SchemaTests {
  private func freshDB() throws -> DatabaseQueue {
    let db = try DatabaseQueue()
    try Schema.migrator.migrate(db)
    return db
  }

  private func columns(in table: String, on db: DatabaseQueue) throws -> [String] {
    try db.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT name FROM pragma_table_info(?) ORDER BY cid",
        arguments: [table]
      )
    }
  }

  private func idColumnSignatures(in tables: [String], on db: DatabaseQueue) throws -> Set<String> {
    var signatures = Set<String>()
    for table in tables {
      let tableSignatures = try db.read { db in
        try String.fetchAll(
          db,
          sql: """
            SELECT type || ':' || "notnull" || ':' || pk || ':' || coalesce(dflt_value, '')
            FROM pragma_table_info(?)
            WHERE name = 'id'
            """,
          arguments: [table]
        )
      }
      for signature in tableSignatures {
        signatures.insert(signature)
      }
    }
    return signatures
  }

  @Test func migrationCreatesAllTables() throws {
    let db = try freshDB()

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

  @Test func migrationIsIdempotentForFreshInstall() throws {
    let db = try freshDB()
    try Schema.migrator.migrate(db)

    let appliedMigrations = try db.read { db in
      try Schema.migrator.appliedMigrations(db)
    }

    #expect(appliedMigrations == ["Create v1 tables"])
  }

  @Test func v1TablesHaveExpectedColumns() throws {
    let db = try freshDB()

    let expectedColumns = [
      "routes": ["id", "name", "rtaFSA"],
      "stops": [
        "id", "routeID", "tieOut", "sortIndex", "kind", "displayName",
        "officialSiteID", "locationText", "sharesLocationWith", "latitude",
        "longitude", "notes",
      ],
      "modules": ["id", "stopID", "name", "sortIndex"],
      "deliveryPoints": [
        "id", "stopID", "moduleID", "kind", "label", "isParcelLocker", "status", "notes",
      ],
      "addresses": [
        "id", "civicNumber", "civicRangeFrom", "civicRangeTo", "suite", "street",
        "occupantName", "doorLatitude", "doorLongitude", "postalCode", "notes",
      ],
      "deliveryPointAddresses": ["id", "deliveryPointID", "addressID"],
      "tags": ["id", "name", "isWarning"],
      "addressTags": ["id", "addressID", "tagID"],
    ]

    for (table, expected) in expectedColumns {
      #expect(try columns(in: table, on: db) == expected, "\(table) columns drifted")
    }
  }

  @Test func syncedTablesUseGeneratedTextUUIDPrimaryKeys() throws {
    let db = try freshDB()
    let tables = [
      "routes", "stops", "modules", "deliveryPoints", "addresses",
      "deliveryPointAddresses", "tags", "addressTags",
    ]

    let signatures = try idColumnSignatures(in: tables, on: db)
    #expect(signatures == ["TEXT:1:1:uuid()"])
  }

  @Test func databaseGeneratesUUIDPrimaryKeysWhenIDsAreOmitted() throws {
    let db = try freshDB()

    try db.write { db in
      try db.execute(sql: #"INSERT INTO "routes" ("name") VALUES (?)"#, arguments: ["Generated"])
    }

    let generatedID = try #require(
      try db.read { db in
        try String.fetchOne(
          db,
          sql: #"SELECT "id" FROM "routes" WHERE "name" = ?"#,
          arguments: ["Generated"]
        )
      }
    )

    #expect(UUID(uuidString: generatedID) != nil)
    #expect(generatedID == generatedID.lowercased())
  }

  @Test func syncedTablesHaveNoNonPrimaryKeyUniqueIndexes() throws {
    let db = try freshDB()
    let tables = [
      "routes", "stops", "modules", "deliveryPoints", "addresses",
      "deliveryPointAddresses", "tags", "addressTags",
    ]

    for table in tables {
      let uniqueIndexes = try db.read { db in
        try String.fetchAll(
          db,
          sql: """
            SELECT name
            FROM pragma_index_list(?)
            WHERE "unique" = 1 AND origin != 'pk'
            ORDER BY name
            """,
          arguments: [table]
        )
      }

      #expect(uniqueIndexes.isEmpty, "\(table) has non-PK unique indexes: \(uniqueIndexes)")
    }
  }

  @Test func foreignKeyDeleteActionsAreSyncCompatible() throws {
    let db = try freshDB()
    let allowedActions = Set(["CASCADE", "SET NULL", "SET DEFAULT"])
    let tables = [
      "routes", "stops", "modules", "deliveryPoints", "addresses",
      "deliveryPointAddresses", "tags", "addressTags",
    ]

    for table in tables {
      let deleteActions = try db.read { db in
        try String.fetchAll(
          db,
          sql: """
            SELECT on_delete
            FROM pragma_foreign_key_list(?)
            ORDER BY id, seq
            """,
          arguments: [table]
        )
      }

      #expect(
        deleteActions.allSatisfy { allowedActions.contains($0) },
        "\(table) has sync-incompatible FK delete actions: \(deleteActions)"
      )
    }
  }
}
