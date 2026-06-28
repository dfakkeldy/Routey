import Testing
import Foundation
import SQLiteData
@testable import RouteyPersistence

@Suite struct SchemaTests {
  private let syncedTables = [
    "routes", "stops", "modules", "deliveryPoints", "addresses",
    "deliveryPointAddresses", "tags", "addressTags",
    "todaysRuns", "runStops", "parcels", "deliveryRecords", "followUpTasks",
  ]

  private let dailyTables = [
    "todaysRuns", "runStops", "parcels", "deliveryRecords", "followUpTasks",
  ]

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

  private func count(_ table: String, on db: DatabaseQueue) throws -> Int {
    try db.read { db in
      try Int.fetchOne(db, sql: "SELECT count(*) FROM \"\(table)\"") ?? -1
    }
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
      "todaysRuns", "runStops", "parcels", "deliveryRecords", "followUpTasks",
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

    #expect(appliedMigrations == ["Create v1 tables", "Create v2 daily tables"])
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
      "todaysRuns": ["id", "routeID", "serviceDate", "createdAt", "archivedAt"],
      "runStops": [
        "id", "runID", "stopID", "tieOut", "displayName", "kind", "sortIndex", "isDone",
      ],
      "parcels": [
        "id", "runID", "addressID", "source", "sizeClass", "toDoor", "requiresSignature",
        "isCustoms", "isDelivered", "labelSnapshot", "trackingCode", "trackingSymbology",
      ],
      "deliveryRecords": [
        "id", "runID", "addressID", "parcelID", "outcome", "latitude", "longitude",
        "loggedAt", "photoPath",
      ],
      "followUpTasks": ["id", "runID", "targetStopID", "addressID", "text", "isDone"],
    ]

    for (table, expected) in expectedColumns {
      #expect(try columns(in: table, on: db) == expected, "\(table) columns drifted")
    }
  }

  @Test func syncedTablesUseGeneratedTextUUIDPrimaryKeys() throws {
    let db = try freshDB()

    let signatures = try idColumnSignatures(in: syncedTables, on: db)
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

    for table in syncedTables {
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

    for table in syncedTables {
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

  @Test func v2DailyTablesAreStrict() throws {
    let db = try freshDB()

    for table in dailyTables {
      let createSQL = try #require(try db.read { db in
        try String.fetchOne(
          db,
          sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
          arguments: [table]
        )
      })

      #expect(createSQL.contains("STRICT"), "\(table) is not STRICT")
    }
  }

  @Test func deletingTodaysRunCascadesDailyChildren() throws {
    let db = try freshDB()
    let routeID = UUID().uuidString.lowercased()
    let runID = UUID().uuidString.lowercased()
    let stopID = UUID().uuidString.lowercased()
    let addressID = UUID().uuidString.lowercased()
    let parcelID = UUID().uuidString.lowercased()

    try db.write { db in
      try db.execute(
        sql: #"INSERT INTO "routes" ("id", "name") VALUES (?, ?)"#,
        arguments: [routeID, "Sample Route"]
      )
      try db.execute(
        sql: """
          INSERT INTO "stops" ("id", "routeID", "displayName")
          VALUES (?, ?, ?)
          """,
        arguments: [stopID, routeID, "Sample Stop"]
      )
      try db.execute(
        sql: #"INSERT INTO "addresses" ("id", "street") VALUES (?, ?)"#,
        arguments: [addressID, "Placeholder Road"]
      )
      try db.execute(
        sql: """
          INSERT INTO "todaysRuns" ("id", "routeID", "serviceDate", "createdAt")
          VALUES (?, ?, ?, ?)
          """,
        arguments: [runID, routeID, "2026-06-22", "2026-06-22T09:00:00.000Z"]
      )
      try db.execute(
        sql: """
          INSERT INTO "runStops" ("runID", "stopID", "tieOut", "displayName", "kind", "sortIndex")
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [runID, stopID, "A", "Sample Stop", "pointOfCall", 0.0]
      )
      try db.execute(
        sql: """
          INSERT INTO "parcels" (
            "id", "runID", "addressID", "source", "sizeClass", "labelSnapshot"
          )
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [parcelID, runID, addressID, "manual", "small", "Sample label"]
      )
      try db.execute(
        sql: """
          INSERT INTO "deliveryRecords" ("runID", "addressID", "parcelID", "outcome", "loggedAt")
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [runID, addressID, parcelID, "safedrop", "2026-06-22T10:00:00.000Z"]
      )
      try db.execute(
        sql: """
          INSERT INTO "followUpTasks" ("runID", "targetStopID", "addressID", "text")
          VALUES (?, ?, ?, ?)
          """,
        arguments: [runID, stopID, addressID, "Check sample compartment"]
      )
    }

    try db.write { db in
      try db.execute(sql: #"DELETE FROM "todaysRuns" WHERE "id" = ?"#, arguments: [runID])
    }

    for table in dailyTables {
      #expect(try count(table, on: db) == 0, "\(table) did not cascade away")
    }
  }
}
