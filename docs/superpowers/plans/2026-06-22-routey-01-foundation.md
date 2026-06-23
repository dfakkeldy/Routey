# Routey Plan 01 — Foundation & Sync Gate

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `RouteyKit` Swift package + iOS app shell with the master-route data model on SQLiteData, and **prove SQLiteData+CloudKit syncs the deep graph across two devices** before any feature work is built on it.

**Architecture:** A local Swift package (`RouteyKit`) holds the model (`RouteyModel`) and persistence/migrations (`RouteyPersistence`); a thin iOS app target (`Routey`) wires the default database and a CloudKit `SyncEngine` at launch. SQLite is the offline-first source of truth; CloudKit private-database sync is a background layer. The deepest, riskiest part of the graph (Route→Stop→Module→DeliveryPoint→Address + two many-to-many joins) is built and sync-verified here so later plans build on proven ground.

**Tech Stack:** Swift 6, SwiftUI, SQLiteData (Point-Free, on GRDB) `from: 1.0.0`, CloudKit, Swift Testing.

## Global Constraints

These apply to **every task** in this and later plans (copied from the design spec):

- **Persistence engine:** SQLiteData (GRDB-based), accessed **only through the `RouteyKit` package boundary**. Pin the dependency to an exact version once it resolves.
- **Globally-unique UUID primary keys** on every synced table — never autoincrement. SQL: `"id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())` (the `ON CONFLICT REPLACE` must come directly after `NOT NULL`).
- **Every table has a single, non-compound primary key** — including join tables.
- **No non-primary-key `UNIQUE` constraints** on synced tables (they throw at `SyncEngine` construction). Enforce uniqueness in app logic.
- **Foreign keys:** `ON DELETE` may only be `CASCADE`, `SET NULL`, or `SET DEFAULT` (`RESTRICT`/`NO ACTION` throw at sync init).
- **Append-only synced schema:** once sync is live, no renaming/dropping/retyping columns or tables on synced tables. New tables and new optional/defaulted columns only.
- **Offline-first:** all reads/writes hit local SQLite; nothing blocks on the network.
- **No CloudKit *sharing*** for the graph — relief handoff is the encrypted `.routey` file (later plan). Do not enable `CKSharingSupported`.
- **iOS deployment target: 18.0** for the app; package floor iOS 17 / macOS 14 so `swift test` runs on the Mac.
- **Naming:** SQLiteData derives table names by lower-casing + pluralizing the type (`Route`→`routes`, `DeliveryPoint`→`deliveryPoints`). Migration `CREATE TABLE` names must match exactly.

---

## File structure

```
RouteyKit/
  Package.swift
  Sources/
    RouteyModel/
      Route.swift              # @Table structs for the master-route graph
      Stop.swift
      Module.swift
      DeliveryPoint.swift
      Address.swift
      Tag.swift
      Joins.swift              # DeliveryPointAddress, AddressTag join tables
    RouteyPersistence/
      Schema.swift             # DatabaseMigrator + CREATE TABLE SQL
      AppDatabase.swift        # appDatabase() + syncTables list
  Tests/
    RouteyPersistenceTests/
      SchemaTests.swift        # migration creates tables
      CRUDTests.swift          # insert/fetch round-trip
      CascadeTests.swift       # FK cascade-delete behavior
app/
  Routey.xcodeproj            # iOS app target (created in Xcode)
  Routey/
    RouteyApp.swift            # prepareDependencies: defaultDatabase + SyncEngine
    ContentView.swift          # minimal reactive view over the DB
    Routey.entitlements        # iCloud (CloudKit) + container
```

The repo root keeps the existing `index.html` (GitHub Pages landing page) untouched; all app code lives under `RouteyKit/` and `app/`.

---

### Task 1: Scaffold the `RouteyKit` package

**Files:**
- Create: `RouteyKit/Package.swift`
- Create: `RouteyKit/Sources/RouteyModel/Route.swift` (placeholder)
- Create: `RouteyKit/Sources/RouteyPersistence/Schema.swift` (placeholder)
- Create: `RouteyKit/Tests/RouteyPersistenceTests/SchemaTests.swift` (placeholder)
- Modify: `.gitignore`

**Interfaces:**
- Produces: a buildable package with products `RouteyModel`, `RouteyPersistence`; importing `SQLiteData` works.

- [ ] **Step 1: Create the package manifest**

Create `RouteyKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RouteyKit",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "RouteyModel", targets: ["RouteyModel"]),
    .library(name: "RouteyPersistence", targets: ["RouteyPersistence"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "RouteyModel",
      dependencies: [.product(name: "SQLiteData", package: "sqlite-data")]
    ),
    .target(
      name: "RouteyPersistence",
      dependencies: [
        "RouteyModel",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
    .testTarget(
      name: "RouteyPersistenceTests",
      dependencies: [
        "RouteyModel",
        "RouteyPersistence",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
  ]
)
```

- [ ] **Step 2: Add placeholder sources so the targets compile**

Create `RouteyKit/Sources/RouteyModel/Route.swift`:

```swift
import Foundation
import SQLiteData
```

Create `RouteyKit/Sources/RouteyPersistence/Schema.swift`:

```swift
import Foundation
import SQLiteData
```

Create `RouteyKit/Tests/RouteyPersistenceTests/SchemaTests.swift`:

```swift
import Testing

@Test func packageBuilds() {
  #expect(true)
}
```

- [ ] **Step 3: Ignore build artifacts**

Append to `.gitignore`:

```
.build/
DerivedData/
*.xcuserstate
xcuserdata/
.swiftpm/
```

- [ ] **Step 4: Resolve and build**

Run: `cd RouteyKit && swift build`
Expected: dependencies resolve (SQLiteData + GRDB + dependencies) and the build succeeds.

- [ ] **Step 5: Run the placeholder test**

Run: `cd RouteyKit && swift test`
Expected: PASS (`packageBuilds`).

- [ ] **Step 6: Pin the resolved version & commit**

Open `RouteyKit/Package.resolved`, read the resolved `sqlite-data` version, and change `from: "1.0.0"` in `Package.swift` to that exact version (e.g. `exact: "1.0.3"`). Re-run `swift build` to confirm.

```bash
git add RouteyKit/.gitignore .gitignore RouteyKit/Package.swift RouteyKit/Package.resolved RouteyKit/Sources RouteyKit/Tests
git commit -m "Scaffold RouteyKit package with SQLiteData dependency"
```

---

### Task 2: Define the model + schema migration

**Files:**
- Create: `RouteyKit/Sources/RouteyModel/{Route,Stop,Module,DeliveryPoint,Address,Tag,Joins}.swift`
- Modify: `RouteyKit/Sources/RouteyPersistence/Schema.swift`
- Create: `RouteyKit/Tests/RouteyPersistenceTests/SchemaTests.swift` (replace placeholder)

**Interfaces:**
- Produces:
  - `@Table` structs: `Route`, `Stop`, `Module`, `DeliveryPoint`, `Address`, `Tag`, `DeliveryPointAddress`, `AddressTag` (all `Identifiable`, `id: UUID`).
  - `enum Schema { static var migrator: DatabaseMigrator }` in `RouteyPersistence` — a migrator whose `"Create v1 tables"` migration creates all eight tables.

- [ ] **Step 1: Write the failing schema test**

Replace `RouteyKit/Tests/RouteyPersistenceTests/SchemaTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd RouteyKit && swift test --filter SchemaTests`
Expected: FAIL — `Schema` is undefined.

- [ ] **Step 3: Define the model structs**

Create `RouteyKit/Sources/RouteyModel/Route.swift`:

```swift
import Foundation
import SQLiteData

@Table
public struct Route: Identifiable, Sendable {
  public let id: UUID
  public var name = ""
  public var rtaFSA = ""
  public init(id: UUID = UUID(), name: String = "", rtaFSA: String = "") {
    self.id = id; self.name = name; self.rtaFSA = rtaFSA
  }
}
```

Create `RouteyKit/Sources/RouteyModel/Stop.swift`:

```swift
import Foundation
import SQLiteData

@Table
public struct Stop: Identifiable, Sendable {
  public let id: UUID
  public var routeID: Route.ID
  public var tieOut = ""
  public var sortIndex = 0.0          // fractional/gap index for cheap reordering
  public var kind = "pointOfCall"     // pointOfCall | rmbCluster | cmbSite | doorVisit
  public var displayName = ""         // nickname: "Cornerstore", "The Manor"
  public var officialSiteID: String? = nil
  public var locationText: String? = nil
  public var sharesLocationWith: String? = nil
  public var latitude: Double? = nil
  public var longitude: Double? = nil
  public var notes = ""
  public init(
    id: UUID = UUID(), routeID: Route.ID, tieOut: String = "", sortIndex: Double = 0,
    kind: String = "pointOfCall", displayName: String = "", officialSiteID: String? = nil,
    locationText: String? = nil, sharesLocationWith: String? = nil,
    latitude: Double? = nil, longitude: Double? = nil, notes: String = ""
  ) {
    self.id = id; self.routeID = routeID; self.tieOut = tieOut; self.sortIndex = sortIndex
    self.kind = kind; self.displayName = displayName; self.officialSiteID = officialSiteID
    self.locationText = locationText; self.sharesLocationWith = sharesLocationWith
    self.latitude = latitude; self.longitude = longitude; self.notes = notes
  }
}
```

Create `RouteyKit/Sources/RouteyModel/Module.swift`:

```swift
import Foundation
import SQLiteData

@Table
public struct Module: Identifiable, Sendable {
  public let id: UUID
  public var stopID: Stop.ID
  public var name = ""
  public var sortIndex = 0.0
  public init(id: UUID = UUID(), stopID: Stop.ID, name: String = "", sortIndex: Double = 0) {
    self.id = id; self.stopID = stopID; self.name = name; self.sortIndex = sortIndex
  }
}
```

Create `RouteyKit/Sources/RouteyModel/DeliveryPoint.swift`:

```swift
import Foundation
import SQLiteData

@Table
public struct DeliveryPoint: Identifiable, Sendable {
  public let id: UUID
  public var stopID: Stop.ID
  public var moduleID: Module.ID? = nil
  public var kind = "roadsideBox"     // roadsideBox | compartment
  public var label = ""
  public var isParcelLocker = false
  public var status = "active"        // active | vacant | closed
  public var notes = ""
  public init(
    id: UUID = UUID(), stopID: Stop.ID, moduleID: Module.ID? = nil,
    kind: String = "roadsideBox", label: String = "", isParcelLocker: Bool = false,
    status: String = "active", notes: String = ""
  ) {
    self.id = id; self.stopID = stopID; self.moduleID = moduleID; self.kind = kind
    self.label = label; self.isParcelLocker = isParcelLocker; self.status = status; self.notes = notes
  }
}
```

Create `RouteyKit/Sources/RouteyModel/Address.swift`:

```swift
import Foundation
import SQLiteData

@Table
public struct Address: Identifiable, Sendable {
  public let id: UUID
  public var civicNumber: Int? = nil
  public var civicRangeFrom: Int? = nil
  public var civicRangeTo: Int? = nil
  public var suite: String? = nil
  public var street = ""
  public var occupantName: String? = nil   // disambiguates multi-unit / complexes
  public var doorLatitude: Double? = nil
  public var doorLongitude: Double? = nil
  public var postalCode: String? = nil
  public var notes = ""
  public init(
    id: UUID = UUID(), civicNumber: Int? = nil, civicRangeFrom: Int? = nil,
    civicRangeTo: Int? = nil, suite: String? = nil, street: String = "",
    occupantName: String? = nil, doorLatitude: Double? = nil, doorLongitude: Double? = nil,
    postalCode: String? = nil, notes: String = ""
  ) {
    self.id = id; self.civicNumber = civicNumber; self.civicRangeFrom = civicRangeFrom
    self.civicRangeTo = civicRangeTo; self.suite = suite; self.street = street
    self.occupantName = occupantName; self.doorLatitude = doorLatitude
    self.doorLongitude = doorLongitude; self.postalCode = postalCode; self.notes = notes
  }
}
```

Create `RouteyKit/Sources/RouteyModel/Tag.swift`:

```swift
import Foundation
import SQLiteData

@Table
public struct Tag: Identifiable, Sendable {
  public let id: UUID
  public var name = ""           // uniqueness enforced in app logic, NOT a DB constraint
  public var isWarning = false   // dog / scary-dog surface alerts
  public init(id: UUID = UUID(), name: String = "", isWarning: Bool = false) {
    self.id = id; self.name = name; self.isWarning = isWarning
  }
}
```

Create `RouteyKit/Sources/RouteyModel/Joins.swift`:

```swift
import Foundation
import SQLiteData

// Shared boxes/compartments: one DeliveryPoint serves many Addresses (many-to-many).
@Table
public struct DeliveryPointAddress: Identifiable, Sendable {
  public let id: UUID
  public var deliveryPointID: DeliveryPoint.ID
  public var addressID: Address.ID
  public init(id: UUID = UUID(), deliveryPointID: DeliveryPoint.ID, addressID: Address.ID) {
    self.id = id; self.deliveryPointID = deliveryPointID; self.addressID = addressID
  }
}

// Address <-> Tag (many-to-many).
@Table
public struct AddressTag: Identifiable, Sendable {
  public let id: UUID
  public var addressID: Address.ID
  public var tagID: Tag.ID
  public init(id: UUID = UUID(), addressID: Address.ID, tagID: Tag.ID) {
    self.id = id; self.addressID = addressID; self.tagID = tagID
  }
}
```

- [ ] **Step 4: Write the migration**

Replace `RouteyKit/Sources/RouteyPersistence/Schema.swift`:

```swift
import Foundation
import SQLiteData

public enum Schema {
  public static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("Create v1 tables") { db in
      try #sql("""
        CREATE TABLE "routes" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL DEFAULT '',
          "rtaFSA" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "stops" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "routeID" TEXT NOT NULL REFERENCES "routes"("id") ON DELETE CASCADE,
          "tieOut" TEXT NOT NULL DEFAULT '',
          "sortIndex" REAL NOT NULL DEFAULT 0,
          "kind" TEXT NOT NULL DEFAULT 'pointOfCall',
          "displayName" TEXT NOT NULL DEFAULT '',
          "officialSiteID" TEXT,
          "locationText" TEXT,
          "sharesLocationWith" TEXT,
          "latitude" REAL,
          "longitude" REAL,
          "notes" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "modules" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "stopID" TEXT NOT NULL REFERENCES "stops"("id") ON DELETE CASCADE,
          "name" TEXT NOT NULL DEFAULT '',
          "sortIndex" REAL NOT NULL DEFAULT 0
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "deliveryPoints" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "stopID" TEXT NOT NULL REFERENCES "stops"("id") ON DELETE CASCADE,
          "moduleID" TEXT REFERENCES "modules"("id") ON DELETE SET NULL,
          "kind" TEXT NOT NULL DEFAULT 'roadsideBox',
          "label" TEXT NOT NULL DEFAULT '',
          "isParcelLocker" INTEGER NOT NULL DEFAULT 0,
          "status" TEXT NOT NULL DEFAULT 'active',
          "notes" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "addresses" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "civicNumber" INTEGER,
          "civicRangeFrom" INTEGER,
          "civicRangeTo" INTEGER,
          "suite" TEXT,
          "street" TEXT NOT NULL DEFAULT '',
          "occupantName" TEXT,
          "doorLatitude" REAL,
          "doorLongitude" REAL,
          "postalCode" TEXT,
          "notes" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "deliveryPointAddresses" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "deliveryPointID" TEXT NOT NULL REFERENCES "deliveryPoints"("id") ON DELETE CASCADE,
          "addressID" TEXT NOT NULL REFERENCES "addresses"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "tags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL DEFAULT '',
          "isWarning" INTEGER NOT NULL DEFAULT 0
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "addressTags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "addressID" TEXT NOT NULL REFERENCES "addresses"("id") ON DELETE CASCADE,
          "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)
    }
    return migrator
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd RouteyKit && swift test --filter SchemaTests`
Expected: PASS — all eight tables exist.

- [ ] **Step 6: Commit**

```bash
git add RouteyKit/Sources RouteyKit/Tests
git commit -m "Add master-route model + v1 schema migration"
```

---

### Task 3: Insert/fetch round-trip

**Files:**
- Create: `RouteyKit/Tests/RouteyPersistenceTests/CRUDTests.swift`

**Interfaces:**
- Consumes: `Route`, `Schema.migrator`.
- Produces: confidence that typed insert + typed fetch work against the migrated schema.

- [ ] **Step 1: Write the failing test**

Create `RouteyKit/Tests/RouteyPersistenceTests/CRUDTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails (or errors)**

Run: `cd RouteyKit && swift test --filter CRUDTests`
Expected: FAIL until the code compiles/passes (if the API names differ, fix per the SQLiteData `Fetching` docs — `Route.all.fetchAll(db)` for collections, `try X.insert { … }.execute(db)` for writes).

- [ ] **Step 3: Make it pass**

No new product code is required — the model and schema from Task 2 satisfy this. If the build fails on API spelling, adjust the fetch/insert calls to match the resolved SQLiteData version's `Fetching` documentation, then re-run.

- [ ] **Step 4: Run to verify it passes**

Run: `cd RouteyKit && swift test --filter CRUDTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Tests/RouteyPersistenceTests/CRUDTests.swift
git commit -m "Verify insert/fetch round-trip"
```

---

### Task 4: Cascade-delete integrity across the deep graph

**Files:**
- Create: `RouteyKit/Tests/RouteyPersistenceTests/CascadeTests.swift`

**Interfaces:**
- Consumes: all model types, `Schema.migrator`.
- Produces: proof that deleting a `Route` cascades to its owned rows (stops, modules, deliveryPoints, the point↔address join) while shared `Address`/`Tag` rows survive — the FK design later plans depend on.

- [ ] **Step 1: Write the failing test**

Create `RouteyKit/Tests/RouteyPersistenceTests/CascadeTests.swift`:

```swift
import Testing
import Foundation
import SQLiteData
import RouteyModel
@testable import RouteyPersistence

@Suite struct CascadeTests {
  private func freshDB() throws -> DatabaseQueue {
    let db = try DatabaseQueue()
    try Schema.migrator.migrate(db)
    return db
  }

  private func count(_ db: DatabaseQueue, _ table: String) throws -> Int {
    try db.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM \"\(table)\"") ?? -1 }
  }

  @Test func deletingRouteCascadesOwnedRowsButKeepsAddressesAndTags() throws {
    let db = try freshDB()
    let routeID = UUID(), stopID = UUID(), moduleID = UUID()
    let pointID = UUID(), addressID = UUID(), tagID = UUID()

    try db.write { db in
      try Route.insert { Route(id: routeID, name: "R") }.execute(db)
      try Stop.insert { Stop(id: stopID, routeID: routeID, kind: "cmbSite", displayName: "Cornerstore") }.execute(db)
      try Module.insert { Module(id: moduleID, stopID: stopID, name: "1") }.execute(db)
      try DeliveryPoint.insert {
        DeliveryPoint(id: pointID, stopID: stopID, moduleID: moduleID, kind: "compartment", label: "1A")
      }.execute(db)
      try Address.insert { Address(id: addressID, civicNumber: 31, street: "Elm St", occupantName: "Alex") }.execute(db)
      try Tag.insert { Tag(id: tagID, name: "dog", isWarning: true) }.execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: pointID, addressID: addressID)
      }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addressID, tagID: tagID) }.execute(db)
    }

    // Sanity: everything inserted.
    #expect(try count(db, "stops") == 1)
    #expect(try count(db, "deliveryPointAddresses") == 1)

    // Delete the route.
    try db.write { db in
      try db.execute(sql: "DELETE FROM \"routes\" WHERE \"id\" = ?", arguments: [routeID.uuidString])
    }

    // Owned rows cascade away.
    #expect(try count(db, "routes") == 0)
    #expect(try count(db, "stops") == 0)
    #expect(try count(db, "modules") == 0)
    #expect(try count(db, "deliveryPoints") == 0)
    #expect(try count(db, "deliveryPointAddresses") == 0)

    // Shared, route-independent rows survive (addresses can belong to other stops; tags are global).
    #expect(try count(db, "addresses") == 1)
    #expect(try count(db, "tags") == 1)

    // The address↔tag join is owned by the (surviving) address, so it survives too.
    #expect(try count(db, "addressTags") == 1)
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd RouteyKit && swift test --filter CascadeTests`
Expected: FAIL if foreign-key enforcement is off (cascades wouldn't fire). GRDB enables `PRAGMA foreign_keys=ON` by default, so this should pass once compiling — but the test exists to *prove* it, catching any later config that disables FKs.

- [ ] **Step 3: Ensure foreign keys are enforced**

If the cascade assertions fail, the DB has foreign keys disabled. Confirm GRDB's default is intact; do **not** override it off. No code change expected.

- [ ] **Step 4: Run to verify it passes**

Run: `cd RouteyKit && swift test`
Expected: PASS (all suites).

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Tests/RouteyPersistenceTests/CascadeTests.swift
git commit -m "Verify FK cascade-delete integrity across the deep graph"
```

---

### Task 5: iOS app shell wired to the local database

**Files:**
- Create (in Xcode): `app/Routey.xcodeproj`, `app/Routey/RouteyApp.swift`, `app/Routey/ContentView.swift`
- Create: `RouteyKit/Sources/RouteyPersistence/AppDatabase.swift`

**Interfaces:**
- Consumes: `Schema.migrator`, `Route`.
- Produces: `func appDatabase(configuration:) throws -> any DatabaseWriter` in `RouteyPersistence`; an app that reactively shows the route count and can insert a route.

- [ ] **Step 1: Add the app database factory**

Create `RouteyKit/Sources/RouteyPersistence/AppDatabase.swift`:

```swift
import Foundation
import OSLog
import SQLiteData

private let logger = Logger(subsystem: "com.routey.app", category: "Database")

/// Opens (or creates) the on-disk app database, runs migrations, and returns it.
public func appDatabase(configuration: Configuration = Configuration()) throws -> any DatabaseWriter {
  let database = try defaultDatabase(configuration: configuration)
  logger.info("open '\(database.path)'")
  try Schema.migrator.migrate(database)
  return database
}

/// The list of tables synchronized to CloudKit (used in Task 6).
/// NOTE: keep local-only / derived tables (search indices, caches) OUT of this list.
public let syncedTableTypes: [any PrimaryKeyedTableDefinition.Type] = [
  // populated in Task 6
]
```

> If `PrimaryKeyedTableDefinition` is not the exact protocol name in the resolved SQLiteData version, delete the `syncedTableTypes` constant here; Task 6 passes the table types directly to `SyncEngine(for:tables:)` instead.

- [ ] **Step 2: Create the Xcode app target**

In Xcode: File → New → Project → iOS App. Name `Routey`, interface SwiftUI, language Swift, save into `app/`. Set the **iOS Deployment Target to 18.0**. Delete the auto-generated `ContentView.swift` body content (you'll replace it). Then File → Add Package Dependencies → Add Local… → select `../RouteyKit`, and add both `RouteyModel` and `RouteyPersistence` to the `Routey` target.

- [ ] **Step 3: Wire the database at launch**

Replace `app/Routey/RouteyApp.swift`:

```swift
import SwiftUI
import SQLiteData
import RouteyPersistence

@main
struct RouteyApp: App {
  init() {
    try! prepareDependencies {
      $0.defaultDatabase = try appDatabase()
    }
  }
  var body: some Scene {
    WindowGroup { ContentView() }
  }
}
```

- [ ] **Step 4: Minimal reactive view**

Replace `app/Routey/ContentView.swift`:

```swift
import SwiftUI
import SQLiteData
import RouteyModel

struct ContentView: View {
  @FetchAll(Route.order { $0.name }) var routes: [Route]
  @Dependency(\.defaultDatabase) var database

  var body: some View {
    NavigationStack {
      List(routes) { route in
        Text(route.name.isEmpty ? "Untitled route" : route.name)
      }
      .navigationTitle("Routes (\(routes.count))")
      .toolbar {
        Button("Add") {
          try? database.write { db in
            try Route.insert { Route(name: "Route \(routes.count + 1)") }.execute(db)
          }
        }
      }
    }
  }
}
```

- [ ] **Step 5: Run on the simulator and verify**

Run the `Routey` scheme on an iPhone simulator (iOS 18+).
Expected: title shows "Routes (0)". Tapping **Add** inserts a row; the list and the count update immediately (proving `@FetchAll` observation + writes are wired). Force-quit and relaunch: the rows persist (proving on-disk storage).

- [ ] **Step 6: Commit**

```bash
git add RouteyKit/Sources/RouteyPersistence/AppDatabase.swift app/
git commit -m "Add iOS app shell wired to the local SQLiteData database"
```

---

### Task 6: Enable CloudKit sync

**Files:**
- Create: `app/Routey/Routey.entitlements`
- Modify: `app/Routey/RouteyApp.swift`

**Interfaces:**
- Consumes: `appDatabase()`, all eight model types.
- Produces: an app that builds and runs with a private-database `SyncEngine` over the full graph.

- [ ] **Step 1: Add iCloud + background capabilities**

In Xcode → `Routey` target → Signing & Capabilities:
- Add **iCloud**, check **CloudKit**, and create/select a container `iCloud.com.routey.app` (match your bundle id).
- Add **Background Modes**, check **Remote notifications**.
- Confirm `app/Routey/Routey.entitlements` now contains `com.apple.developer.icloud-services` (CloudKit) and the container identifier. Do **not** add `CKSharingSupported` (sharing is out of scope).

- [ ] **Step 2: Construct the SyncEngine at launch**

Replace `app/Routey/RouteyApp.swift`:

```swift
import SwiftUI
import SQLiteData
import RouteyModel
import RouteyPersistence

@main
struct RouteyApp: App {
  init() {
    try! prepareDependencies {
      $0.defaultDatabase = try appDatabase()
      $0.defaultSyncEngine = try SyncEngine(
        for: $0.defaultDatabase,
        tables: Route.self, Stop.self, Module.self, DeliveryPoint.self,
                Address.self, Tag.self, DeliveryPointAddress.self, AddressTag.self
      )
    }
  }
  var body: some Scene {
    WindowGroup { ContentView() }
  }
}
```

- [ ] **Step 3: Build and run on a real device**

Run the `Routey` scheme on a **physical device** signed into iCloud (the simulator can sync but two physical devices are the real test in Task 7).
Expected: the app launches without crashing, the route list still works locally, and Xcode logs show the sync engine starting (no `SyncEngine` construction error — which would mean a schema rule was violated, e.g. an unsupported `ON DELETE` action or a non-PK unique constraint).

- [ ] **Step 4: Commit**

```bash
git add app/Routey/Routey.entitlements app/Routey/RouteyApp.swift
git commit -m "Enable private CloudKit sync over the full graph"
```

---

### Task 7: Two-device sync gate (architecture decision)

> **This task is a manual verification gate, not code.** It decides whether the SQLiteData bet holds. Do not start any later plan until it passes.

**Files:** none.

**Interfaces:**
- Consumes: the app from Task 6.
- Produces: a recorded PASS/FAIL decision. On FAIL, the project switches the persistence engine (see Step 5) — the model and package structure are reused, only `RouteyPersistence` changes.

- [ ] **Step 1: Prepare two devices**

Install the Task 6 build on **two physical devices** (Device A, Device B) signed into the **same iCloud account**. Ensure both have network. In the CloudKit Console, confirm the Development schema has the eight record types (SQLiteData creates them on first sync); if releasing later, remember to **Deploy Schema Changes** to Production.

- [ ] **Step 2: Verify create → propagate**

On Device A, tap **Add** to create a route. Within a short delay, confirm the route appears on Device B (foreground the app / pull to refresh by relaunch if needed).
Expected: route count increments on B. ✅/❌

- [ ] **Step 3: Verify deep-graph + cascade sync**

Temporarily extend `ContentView` (or use a debug button) to insert a full chain on A — a Stop, Module, DeliveryPoint, Address, and the joins — then delete the Route on A. Confirm on B that the chain arrived first and then the cascade delete propagated (B ends with zero stops/points for that route, addresses/tags per the Task 4 rules).
Expected: parent-before-child arrival, then cascade. ✅/❌

- [ ] **Step 4: Verify concurrent reorder behavior**

Put both devices offline. On each, change a `Stop.sortIndex` (simulate a reorder) to different values. Bring both online. Observe the converged value.
Expected: last-write-wins converges to a single value with **no crash and no orphaned/duplicated rows** (we accept LWW for ordering; Today's Run is single-device-per-day by design, so this is the worst realistic case). ✅/❌

- [ ] **Step 5: Record the decision**

- If Steps 2–4 all pass → **PASS.** Append a note to the design spec (`docs/superpowers/specs/2026-06-22-routey-design.md`, §10) recording the SQLiteData decision is confirmed, commit it, and proceed to Plan 02.
- If any step fails irrecoverably → **FAIL.** Stop. Open a new brainstorming/plan note to switch `RouteyPersistence` to **Core Data + NSPersistentCloudKitContainer**, keeping `RouteyModel`'s field set, the same constraints (UUID keys, optional relationships, sortIndex ordering), and the app structure. The other plans (02–07) are written against the model, not the engine, so they remain valid.

- [ ] **Step 6: Commit the recorded decision**

```bash
git add docs/superpowers/specs/2026-06-22-routey-design.md
git commit -m "Record two-device sync gate result"
```

---

## Plan self-review

- **Spec coverage (foundation slice):** package boundary ✓ (Task 1), full master-route data model incl. Delivery Point / shared-box & clustered-RMB joins, CMB hierarchy, tie-out, nicknames, occupant name, vacant/closed status ✓ (Task 2), UUID PKs + append-only + FK rules ✓ (Global Constraints, Task 2), offline-first local store ✓ (Task 5), private CloudKit sync ✓ (Task 6), the spec-mandated **two-device sync PoC gate** ✓ (Task 7). Deferred by design to later plans: Parcel, DeliveryRecord, Today's Run, VirtualSortCase/FTS, import, OCR, history, print, encrypted export.
- **Placeholder scan:** none — every code step has complete code; Xcode-GUI steps have exact menu paths and a run-verification.
- **Type consistency:** model type/field names (`Route`, `Stop.routeID`, `DeliveryPoint.stopID/moduleID`, `Address.occupantName`, `DeliveryPointAddress`, `AddressTag`) are used identically in the schema SQL, tests, and app. Table names match the lower-cased plural convention used in the migration.
- **Known API risk:** SQLiteData fetch/insert verbs (`Route.all.fetchAll(db)`, `X.insert { … }.execute(db)`, `@FetchAll(Route.order { … })`) are taken from the resolved docs; Step 2/3 of Tasks 3 explicitly say to reconcile against the pinned version's `Fetching` docs if a name differs. This is the medium-confidence area the gate (Task 7) exists to close.
