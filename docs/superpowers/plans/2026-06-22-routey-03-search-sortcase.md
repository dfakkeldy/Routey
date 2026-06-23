# Routey Plan 03 — Search & Virtual Sort Case

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Answer the two questions a carrier asks while sorting — *"is this number on my route?"* and *"where does it go?"* — with instant predictive search, and render the **virtual sort case** (an on-screen mirror of the physical case).

**Architecture:** A new `RouteySearch` module owns a **local, non-synced FTS5** index over address text (rebuilt from the graph — CloudKit does not sync derived FTS). A `SearchService` resolves a query to ranked `SearchHit`s, each carrying the full locator (stop nickname → module/compartment, shared civics, tags). The app gains a predictive Search screen and a Virtual Sort Case grid.

**Tech Stack:** Swift 6, SwiftUI, SQLiteData/GRDB (FTS5), Swift Testing.

**Depends on:** Plan 01 (model + persistence), Plan 02 (some data to search). UI tasks require the app shell (Plan 01 Task 5).

## Global Constraints

- Inherited from Plan 01 (UUID PKs, append-only synced schema, FK rules, STRICT, package boundary).
- **The FTS index is LOCAL and excluded from CloudKit sync** — it is never added to the `SyncEngine` tables list; it is rebuilt from the synced `addresses` rows after import and after first sync.
- Offline-first; search runs entirely on-device with no spinners.
- A shared delivery point shows **all** civic numbers it serves; search by any of them locates the slot.

---

## File structure

```
RouteyKit/
  Package.swift                       # add RouteySearch
  Sources/RouteySearch/
    SearchIndex.swift                 # FTS5 table install + rebuild + raw MATCH query
    SearchService.swift               # query -> [SearchHit] with locator resolution
    SearchHit.swift                   # value type returned to the UI
  Tests/RouteySearchTests/
    SearchIndexTests.swift
    SearchServiceTests.swift
app/Routey/Search/
  SearchView.swift                    # predictive search field + result rows
  VirtualSortCaseView.swift           # slot grid mirroring the physical case
```

---

### Task 1: Local FTS5 index (install + rebuild + match)

**Files:** `RouteyKit/Sources/RouteySearch/SearchIndex.swift`, `RouteyKit/Tests/RouteySearchTests/SearchIndexTests.swift`, `Package.swift`.

**Interfaces:**
- `enum SearchIndex`:
  - `static func install(_ db: Database) throws` — creates `CREATE VIRTUAL TABLE IF NOT EXISTS addressSearch USING fts5(addressID UNINDEXED, civic, street, occupant, postal, prefix='2 3 4', tokenize='unicode61')`.
  - `static func rebuild(from db: Database) throws` — clears + repopulates from `addresses`.
  - `static func match(_ query: String, in db: Database) throws -> [UUID]` — returns address IDs ranked by FTS `rank`, prefix-matching each token (`tok*`).

- [ ] **Step 1:** Add `RouteySearch` target (deps `RouteyModel`, SQLiteData) + test target in `Package.swift`; `swift build`.

- [ ] **Step 2: Write failing tests** — `SearchIndexTests.swift`:

```swift
import Testing
import Foundation
import SQLiteData
import RouteyModel
@testable import RouteySearch
@testable import RouteyPersistence

@Suite struct SearchIndexTests {
  private func dbWithAddresses() throws -> DatabaseQueue {
    let db = try DatabaseQueue(); try Schema.migrator.migrate(db)
    try db.write { db in
      try SearchIndex.install(db)
      try Address.insert { Address(id: UUID(), civicNumber: 1284, street: "Concession Rd 6") }.execute(db)
      try Address.insert { Address(id: UUID(), civicNumber: 88, street: "Maple Side Rd", occupantName: "Alex") }.execute(db)
      try SearchIndex.rebuild(from: db)
    }
    return db
  }

  @Test func prefixMatchOnCivicNumber() throws {
    let db = try dbWithAddresses()
    let hits = try db.read { db in try SearchIndex.match("128", in: db) }
    #expect(hits.count == 1)
  }
  @Test func matchOnStreetToken() throws {
    let db = try dbWithAddresses()
    let hits = try db.read { db in try SearchIndex.match("maple", in: db) }
    #expect(hits.count == 1)
  }
  @Test func matchOnOccupantName() throws {
    let db = try dbWithAddresses()
    let hits = try db.read { db in try SearchIndex.match("sar", in: db) }
    #expect(hits.count == 1)
  }
  @Test func noMatchReturnsEmpty() throws {
    let db = try dbWithAddresses()
    #expect(try db.read { db in try SearchIndex.match("99999", in: db) }.isEmpty)
  }
}
```

- [ ] **Step 3:** Run — FAIL (SearchIndex undefined).

- [ ] **Step 4: Implement** — `SearchIndex.swift`:

```swift
import Foundation
import SQLiteData
import RouteyModel

public enum SearchIndex {
  public static func install(_ db: Database) throws {
    try db.execute(sql: """
      CREATE VIRTUAL TABLE IF NOT EXISTS addressSearch USING fts5(
        addressID UNINDEXED, civic, street, occupant, postal,
        prefix='2 3 4', tokenize='unicode61'
      )
      """)
  }

  public static func rebuild(from db: Database) throws {
    try db.execute(sql: "DELETE FROM addressSearch")
    let rows = try Row.fetchAll(db, sql: """
      SELECT id, civicNumber, street, occupantName, postalCode FROM addresses
      """)
    for r in rows {
      try db.execute(sql: """
        INSERT INTO addressSearch (addressID, civic, street, occupant, postal)
        VALUES (?, ?, ?, ?, ?)
        """, arguments: [
          r["id"] as String,
          (r["civicNumber"] as Int?).map(String.init) ?? "",
          r["street"] as String? ?? "",
          r["occupantName"] as String? ?? "",
          r["postalCode"] as String? ?? "",
        ])
    }
  }

  /// Prefix-matches every whitespace token; returns address IDs ordered by FTS rank.
  public static func match(_ query: String, in db: Database) throws -> [UUID] {
    let tokens = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    guard !tokens.isEmpty else { return [] }
    let ftsQuery = tokens.map { "\($0)*" }.joined(separator: " ")
    let ids = try String.fetchAll(db, sql: """
      SELECT addressID FROM addressSearch WHERE addressSearch MATCH ? ORDER BY rank
      """, arguments: [ftsQuery])
    return ids.compactMap(UUID.init(uuidString:))
  }
}
```

- [ ] **Step 5:** Run — PASS (4/4). (`Row`/`String.fetchAll(db,sql:)` are GRDB, re-exported by SQLiteData.)

- [ ] **Step 6:** Commit `"Add local FTS5 address search index"`.

---

### Task 2: SearchService — query to located hits

**Files:** `RouteyKit/Sources/RouteySearch/SearchHit.swift`, `SearchService.swift`, `Tests/RouteySearchTests/SearchServiceTests.swift`.

**Interfaces:**
- `struct SearchHit: Equatable, Sendable { var address: Address; var stopNickname: String; var tieOut: String; var moduleName: String?; var compartmentLabel: String?; var sharedCivics: [Int]; var tagNames: [String] }`
- `struct SearchService { var database: any DatabaseReader; func search(_ query: String) throws -> [SearchHit] }` — runs `SearchIndex.match`, then for each address joins through `deliveryPointAddresses → deliveryPoints → (modules) → stops`, collects the other civics on the same point (`sharedCivics`), and the address's tag names.

- [ ] **Step 1: Write failing test** — build a route with a shared CMB compartment serving two addresses + a tag; assert a search for one civic returns a hit whose `stopNickname`, `compartmentLabel`, `sharedCivics` (the other civic), and `tagNames` are populated. (Full code mirrors Task 1's setup; assert `hit.stopNickname == "Cornerstore"`, `hit.compartmentLabel == "M1-3"`, `hit.sharedCivics == [1286]`, `hit.tagNames.contains("dog")`.)

- [ ] **Step 2:** Run — FAIL.

- [ ] **Step 3: Implement** `SearchHit.swift` + `SearchService.swift`. Resolution algorithm per hit:
  1. `address` = the matched row.
  2. Find its `deliveryPointAddresses` → first `deliveryPoint` → its `stop` (nickname = `stop.displayName`, `tieOut`) and `module` (if any) for `moduleName`/`compartmentLabel` (= `deliveryPoint.label`).
  3. `sharedCivics` = civic numbers of *other* addresses on the same delivery point.
  4. `tagNames` = names via `addressTags → tags`.
  Use SQLiteData typed queries or GRDB raw SQL joins; keep it read-only on a `DatabaseReader`.

- [ ] **Step 4:** Run — PASS.

- [ ] **Step 5:** Commit `"Add SearchService with locator + shared-civic resolution"`.

---

### Task 3: Wire reindex into import & app launch

**Files:** modify `RouteyKit/Sources/RouteyDomain/RouteImporter.swift` (call `SearchIndex.rebuild` after import); add `SearchIndex.install` to app DB setup.

- [ ] **Step 1:** After a successful import (Plan 02 Task 2), call `try SearchIndex.rebuild(from: db)` inside the same write. Add a test asserting a freshly imported route is immediately searchable.
- [ ] **Step 2:** In `appDatabase()` (Plan 01), after migration call `database.write { try SearchIndex.install($0); try SearchIndex.rebuild(from: $0) }` so the local index exists and reflects synced rows on every launch. (RouteyPersistence gains a dependency on RouteySearch.)
- [ ] **Step 3:** `swift test` (all suites) — PASS. Commit `"Rebuild search index after import and on launch"`.

---

### Task 4: Predictive Search screen (UI)

> Requires app shell (Plan 01 Task 5).

**Files:** `app/Routey/Search/SearchView.swift`.

- [ ] **Step 1:** A `@State query` text field; on change, run `SearchService.search(query)` (debounced via `.task(id: query)`); render result rows showing civic + street, the locator (`stopNickname` · `compartmentLabel`), shared civics ("also: 1286"), and tag chips (warning tags in red). Empty query → empty state; no matches → "Not on this route." (the membership answer).
- [ ] **Step 2:** Run in simulator against imported data; verify instant filtering and the "not on this route" message for a fake number.
- [ ] **Step 3:** Commit `"Add predictive search screen"`.

---

### Task 5: Virtual Sort Case grid (UI)

> Requires app shell.

**Files:** `app/Routey/Search/VirtualSortCaseView.swift`.

- [ ] **Step 1:** Render delivery points for a route as an ordered grid of **slots** (by stop `sortIndex`, then module/compartment), each slot labeled with civic number(s) + tie-out, colored by warning flags, showing a note indicator. A shared slot shows all its civics. Tapping a slot shows its addresses + tags + notes.
- [ ] **Step 2:** A search field at top that, on submit, **scrolls to and highlights** the matching slot (`ScrollViewReader`), realizing "where does it go."
- [ ] **Step 3:** Run in simulator; verify the grid mirrors the route order and search jumps to a slot.
- [ ] **Step 4:** Commit `"Add virtual sort case grid with search-to-slot"`.

---

## Plan self-review

- **Spec coverage:** membership + slot lookup ✓ (T1–T2), shared-slot civics ✓ (T2), tags/warnings surfaced ✓ (T2/T4), predictive search ✓ (T4), virtual sort case grid with search-to-slot ✓ (T5), local non-synced FTS rebuilt from graph ✓ (T1/T3). Per-slot notes/color flags rendering ✓ (T5).
- **Placeholders:** none in headless tasks (complete code); UI tasks specify exact behavior + the queries they call.
- **Type consistency:** `SearchIndex.match` (T1) feeds `SearchService.search` (T2) feeds the UI (T4/T5); `SearchHit` fields are fixed in T2 and consumed verbatim in T4.
- **Sync honesty:** the FTS table is never added to the SyncEngine list; it's rebuilt locally (T3) so synced-in rows become searchable.
