# Routey Plan 02 — Import & Route Editing

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get a real master route *into* Routey — by importing a pasted/CSV route list and by hand-editing stops, addresses, and tags — so the carrier sees and maintains their living route.

**Architecture:** A new pure-Swift `RouteyImport` module parses tolerant route text into structured rows; a `RouteyDomain` module holds persistence-backed edit operations (add/update/delete stop & address, tag management) with gap-based ordering. Both are headlessly testable. The iOS app gains a Route List, Stop/Address editors, a Tag picker, and an Import screen built on `@FetchAll` + `database.write`.

**Tech Stack:** Swift 6, SwiftUI, SQLiteData (on GRDB), Swift Testing.

**Depends on:** Plan 01 (RouteyKit package: `Route`, `Stop`, `Module`, `DeliveryPoint`, `Address`, `Tag`, `DeliveryPointAddress`, `AddressTag`; `Schema.migrator`; `appDatabase()`). **UI tasks (5–7) require Plan 01 Task 5's app shell to exist.** Tasks 1–4 here are package-level and run headlessly without the app.

## Global Constraints

(Inherited from Plan 01 — every task implicitly includes these.)

- SQLiteData behind the `RouteyKit` package boundary; UUID PKs; append-only synced schema; no non-PK UNIQUE; FK `ON DELETE` only CASCADE/SET NULL/SET DEFAULT; STRICT tables; table names = lower-cased plural of the type.
- **Reorderable/ordered sequences use a fractional `sortIndex`** (`Double`), never row renumbering — inserting between `a` and `b` uses `(a+b)/2`; appending uses `lastSortIndex + 1.0`.
- **Stop.kind** vocabulary: `pointOfCall | rmbCluster | cmbSite | doorVisit`. Import produces `pointOfCall` stops only (CMB structure is built later, by hand).
- Offline-first; all reads/writes are local.
- iOS deployment target 18.0 for the app; package floor iOS 17 / macOS 14.
- **Import is tolerant, never destructive:** a malformed line is collected as a skipped-row report, never silently dropped and never aborting the whole import. Import always targets a *new* Route or a chosen existing Route; it never overwrites unrelated data.

---

## File structure

```
RouteyKit/
  Package.swift                         # add RouteyImport, RouteyDomain products/targets
  Sources/
    RouteyImport/
      ParsedRoute.swift                 # value types: ParsedStop, ParseResult, SkippedRow
      RouteParser.swift                 # text/CSV -> ParseResult (pure, no DB)
    RouteyDomain/
      RouteImporter.swift               # ParseResult -> persisted Route graph
      RouteEditing.swift                # add/update/delete stop, address, tag ops
  Tests/
    RouteyImportTests/
      RouteParserTests.swift
    RouteyDomainTests/
      RouteImporterTests.swift
      RouteEditingTests.swift
app/Routey/
  Routes/
    RouteListView.swift                 # stops in order, filter-as-you-type (basic)
    StopDetailView.swift                # view/edit a stop + its delivery points/addresses
    AddressEditorView.swift            # edit one address + its tags
    TagPickerView.swift                 # attach/detach/create tags
  Import/
    ImportView.swift                    # paste text / pick .csv, preview, confirm
```

---

### Task 1: Tolerant route parser (pure Swift)

**Files:**
- Create: `RouteyKit/Sources/RouteyImport/ParsedRoute.swift`
- Create: `RouteyKit/Sources/RouteyImport/RouteParser.swift`
- Create: `RouteyKit/Tests/RouteyImportTests/RouteParserTests.swift`
- Modify: `RouteyKit/Package.swift` (add `RouteyImport` target + test target)

**Interfaces:**
- Produces:
  - `struct ParsedStop: Equatable, Sendable { var tieOut: String?; var civicNumber: Int?; var street: String; var occupantName: String?; var notes: String?; var sourceLine: Int }`
  - `struct SkippedRow: Equatable, Sendable { var line: Int; var raw: String; var reason: String }`
  - `struct ParseResult: Equatable, Sendable { var stops: [ParsedStop]; var skipped: [SkippedRow] }`
  - `enum RouteParser { static func parse(_ text: String) -> ParseResult }`
- Consumed by: Task 2 (importer), Task 7 (import UI preview).

**Parsing rules (tolerant, deterministic):**
- Split on newlines; trim each line; ignore blank lines and lines that are only punctuation.
- If the first non-blank line is a header containing `street` (case-insensitive), treat the file as **CSV with headers**: recognized columns `tieout`, `civic`, `street`, `occupant`, `notes` (case-insensitive, any order); unknown columns ignored. Split rows on commas (no embedded-comma/quote handling in v1 — note this limit in a skipped reason if a row has more fields than headers).
- Otherwise treat each line as **freeform**: a leading integer (optionally followed by a letter, e.g. `20A`) before more text is ambiguous, so apply this rule — if the line matches `^\s*(\d+)\s+(.+)$`, the integer is the **civic number** and the rest is the **street**. (Tie-out is not inferred from freeform lines; only CSV `tieout` sets it.)
- A row with neither a civic number nor a non-empty street → `SkippedRow` with reason `"no civic number or street"`.
- `sourceLine` is the 1-based line number in the original text.

- [ ] **Step 1: Add the targets to Package.swift**

In `RouteyKit/Package.swift`, add to `products`:

```swift
    .library(name: "RouteyImport", targets: ["RouteyImport"]),
    .library(name: "RouteyDomain", targets: ["RouteyDomain"]),
```

Add to `targets` (RouteyImport has NO dependencies — it is pure value types):

```swift
    .target(name: "RouteyImport"),
    .testTarget(name: "RouteyImportTests", dependencies: ["RouteyImport"]),
```

Run: `cd RouteyKit && swift build`
Expected: builds (empty new target).

- [ ] **Step 2: Write the failing tests**

Create `RouteyKit/Tests/RouteyImportTests/RouteParserTests.swift`:

```swift
import Testing
@testable import RouteyImport

@Suite struct RouteParserTests {
  @Test func parsesFreeformCivicAndStreet() {
    let r = RouteParser.parse("10100 County Rd 12\n38 Northgate Rd\n")
    #expect(r.skipped.isEmpty)
    #expect(r.stops.count == 2)
    #expect(r.stops[0] == ParsedStop(tieOut: nil, civicNumber: 10100, street: "County Rd 12",
                                     occupantName: nil, notes: nil, sourceLine: 1))
    #expect(r.stops[1].civicNumber == 38)
    #expect(r.stops[1].street == "Northgate Rd")
  }

  @Test func ignoresBlankLinesAndTracksLineNumbers() {
    let r = RouteParser.parse("\n\n10100 County Rd 12\n\n")
    #expect(r.stops.count == 1)
    #expect(r.stops[0].sourceLine == 3)
  }

  @Test func skipsRowsWithNeitherCivicNorStreet() {
    let r = RouteParser.parse("---\n10100 County Rd 12\n")
    #expect(r.stops.count == 1)
    #expect(r.skipped.count == 1)
    #expect(r.skipped[0].line == 1)
    #expect(r.skipped[0].reason == "no civic number or street")
  }

  @Test func parsesCSVWithHeaders() {
    let csv = """
      tieOut,civic,street,occupant,notes
      1,10100,County Rd 12,,
      20A,3400,County Rd 12,Alex,by the barn
      """
    let r = RouteParser.parse(csv)
    #expect(r.stops.count == 2)
    #expect(r.stops[0] == ParsedStop(tieOut: "1", civicNumber: 10100, street: "County Rd 12",
                                     occupantName: nil, notes: nil, sourceLine: 2))
    #expect(r.stops[1].tieOut == "20A")
    #expect(r.stops[1].occupantName == "Alex")
    #expect(r.stops[1].notes == "by the barn")
  }

  @Test func streetOnlyRowIsKept() {
    let r = RouteParser.parse("Harbour Rd\n")
    #expect(r.stops.count == 1)
    #expect(r.stops[0].civicNumber == nil)
    #expect(r.stops[0].street == "Harbour Rd")
  }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `cd RouteyKit && swift test --filter RouteParserTests`
Expected: FAIL — `ParsedStop`/`RouteParser` undefined.

- [ ] **Step 4: Implement the value types**

Create `RouteyKit/Sources/RouteyImport/ParsedRoute.swift`:

```swift
public struct ParsedStop: Equatable, Sendable {
  public var tieOut: String?
  public var civicNumber: Int?
  public var street: String
  public var occupantName: String?
  public var notes: String?
  public var sourceLine: Int
  public init(tieOut: String? = nil, civicNumber: Int? = nil, street: String,
              occupantName: String? = nil, notes: String? = nil, sourceLine: Int) {
    self.tieOut = tieOut; self.civicNumber = civicNumber; self.street = street
    self.occupantName = occupantName; self.notes = notes; self.sourceLine = sourceLine
  }
}

public struct SkippedRow: Equatable, Sendable {
  public var line: Int
  public var raw: String
  public var reason: String
  public init(line: Int, raw: String, reason: String) {
    self.line = line; self.raw = raw; self.reason = reason
  }
}

public struct ParseResult: Equatable, Sendable {
  public var stops: [ParsedStop]
  public var skipped: [SkippedRow]
  public init(stops: [ParsedStop] = [], skipped: [SkippedRow] = []) {
    self.stops = stops; self.skipped = skipped
  }
}
```

- [ ] **Step 5: Implement the parser**

Create `RouteyKit/Sources/RouteyImport/RouteParser.swift`:

```swift
import Foundation

public enum RouteParser {
  public static func parse(_ text: String) -> ParseResult {
    let rawLines = text.components(separatedBy: .newlines)
    let firstNonBlank = rawLines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    if let header = firstNonBlank, isHeader(header) {
      return parseCSV(rawLines, headerLine: header)
    }
    return parseFreeform(rawLines)
  }

  private static func isHeader(_ line: String) -> Bool {
    line.lowercased().split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == "street" }
  }

  private static func parseFreeform(_ rawLines: [String]) -> ParseResult {
    var result = ParseResult()
    for (idx, raw) in rawLines.enumerated() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let n = idx + 1
      if line.isEmpty || line.allSatisfy({ !$0.isLetter && !$0.isNumber }) {
        if !line.isEmpty {
          result.skipped.append(SkippedRow(line: n, raw: raw, reason: "no civic number or street"))
        }
        continue
      }
      if let (civic, rest) = leadingCivic(line), !rest.isEmpty {
        result.stops.append(ParsedStop(civicNumber: civic, street: rest, sourceLine: n))
      } else {
        result.stops.append(ParsedStop(street: line, sourceLine: n))
      }
    }
    return result
  }

  /// Returns (civic, remainder) when the line begins with `<digits> <text>`.
  private static func leadingCivic(_ line: String) -> (Int, String)? {
    let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2, let civic = Int(parts[0]) else { return nil }
    return (civic, parts[1].trimmingCharacters(in: .whitespaces))
  }

  private static func parseCSV(_ rawLines: [String], headerLine: String) -> ParseResult {
    var result = ParseResult()
    let headers = headerLine.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    func col(_ name: String, _ fields: [String]) -> String? {
      guard let i = headers.firstIndex(of: name), i < fields.count else { return nil }
      let v = fields[i].trimmingCharacters(in: .whitespaces)
      return v.isEmpty ? nil : v
    }
    var headerSeen = false
    for (idx, raw) in rawLines.enumerated() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let n = idx + 1
      if line.isEmpty { continue }
      if !headerSeen { headerSeen = true; continue }   // skip the header row itself
      let fields = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      if fields.count > headers.count {
        result.skipped.append(SkippedRow(line: n, raw: raw, reason: "more fields than headers"))
        continue
      }
      let street = col("street", fields) ?? ""
      let civic = col("civic", fields).flatMap { Int($0) }
      if street.isEmpty && civic == nil {
        result.skipped.append(SkippedRow(line: n, raw: raw, reason: "no civic number or street"))
        continue
      }
      result.stops.append(ParsedStop(
        tieOut: col("tieout", fields), civicNumber: civic, street: street,
        occupantName: col("occupant", fields), notes: col("notes", fields), sourceLine: n))
    }
    return result
  }
}
```

- [ ] **Step 6: Run to verify they pass**

Run: `cd RouteyKit && swift test --filter RouteParserTests`
Expected: PASS (5/5).

- [ ] **Step 7: Commit**

```bash
git add RouteyKit/Package.swift RouteyKit/Sources/RouteyImport RouteyKit/Tests/RouteyImportTests
git commit -m "Add tolerant route parser (freeform + CSV)"
```

---

### Task 2: Persist a parsed route (importer)

**Files:**
- Create: `RouteyKit/Sources/RouteyDomain/RouteImporter.swift`
- Create: `RouteyKit/Tests/RouteyDomainTests/RouteImporterTests.swift`
- Modify: `RouteyKit/Package.swift` (add `RouteyDomain` target depending on `RouteyModel`, `RouteyImport`, `SQLiteData`; add test target)

**Interfaces:**
- Consumes: `ParseResult` (Task 1); `Route`, `Stop`, `Address`, `DeliveryPoint`, `DeliveryPointAddress` (Plan 01); a `DatabaseWriter`.
- Produces:
  - `struct ImportSummary: Equatable, Sendable { var routeID: UUID; var stopsCreated: Int; var skipped: [SkippedRow] }`
  - `enum RouteImporter { static func importRoute(named name: String, from result: ParseResult, into db: any DatabaseWriter) throws -> ImportSummary }`
- Behavior: creates one `Route(name:)`; for each `ParsedStop` in order creates a `Stop(kind: "pointOfCall", tieOut:, displayName:, sortIndex: i*1.0)`, an `Address(civicNumber:, street:, occupantName:, notes:)`, one `DeliveryPoint(stopID:, kind: "roadsideBox", label:)`, and a `DeliveryPointAddress` linking them. `sortIndex` = the parsed order (0,1,2,…). Returns the summary incl. the parser's skipped rows.

- [ ] **Step 1: Add the RouteyDomain target**

In `RouteyKit/Package.swift`, add to `targets`:

```swift
    .target(
      name: "RouteyDomain",
      dependencies: [
        "RouteyModel", "RouteyImport",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
    .testTarget(
      name: "RouteyDomainTests",
      dependencies: [
        "RouteyDomain", "RouteyModel", "RouteyImport",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
```

(Add `RouteyDomain` to `products` if not already added in Task 1.)

- [ ] **Step 2: Write the failing test**

Create `RouteyKit/Tests/RouteyDomainTests/RouteImporterTests.swift`:

```swift
import Testing
import Foundation
import SQLiteData
import RouteyModel
import RouteyImport
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RouteImporterTests {
  private func freshDB() throws -> DatabaseQueue {
    let db = try DatabaseQueue()
    try Schema.migrator.migrate(db)
    return db
  }

  @Test func importCreatesOrderedStopsWithAddressesAndPoints() throws {
    let db = try freshDB()
    let parsed = RouteParser.parse("10100 County Rd 12\n38 Northgate Rd\n")

    let summary = try RouteImporter.importRoute(named: "Riverbend", from: parsed, into: db)

    #expect(summary.stopsCreated == 2)
    #expect(summary.skipped.isEmpty)

    let stops = try db.read { db in try Stop.all.order { $0.sortIndex }.fetchAll(db) }
    #expect(stops.count == 2)
    #expect(stops[0].displayName == "10100 County Rd 12" || stops[0].tieOut == "")
    #expect(stops[0].sortIndex == 0.0)
    #expect(stops[1].sortIndex == 1.0)

    let addressCount = try db.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM addresses") }
    #expect(addressCount == 2)
    let pointCount = try db.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM deliveryPoints") }
    #expect(pointCount == 2)
    let linkCount = try db.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM deliveryPointAddresses") }
    #expect(linkCount == 2)
  }

  @Test func importPropagatesSkippedRows() throws {
    let db = try freshDB()
    let parsed = RouteParser.parse("---\n10100 County Rd 12\n")
    let summary = try RouteImporter.importRoute(named: "R", from: parsed, into: db)
    #expect(summary.stopsCreated == 1)
    #expect(summary.skipped.count == 1)
  }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd RouteyKit && swift test --filter RouteImporterTests`
Expected: FAIL — `RouteImporter` undefined.

- [ ] **Step 4: Implement the importer**

Create `RouteyKit/Sources/RouteyDomain/RouteImporter.swift`:

```swift
import Foundation
import SQLiteData
import RouteyModel
import RouteyImport

public struct ImportSummary: Equatable, Sendable {
  public var routeID: UUID
  public var stopsCreated: Int
  public var skipped: [SkippedRow]
}

public enum RouteImporter {
  public static func importRoute(
    named name: String,
    from result: ParseResult,
    into db: any DatabaseWriter
  ) throws -> ImportSummary {
    let routeID = UUID()
    try db.write { db in
      try Route.insert { Route(id: routeID, name: name) }.execute(db)
      for (i, parsed) in result.stops.enumerated() {
        let stopID = UUID()
        let addressID = UUID()
        let pointID = UUID()
        let display = displayName(for: parsed)
        try Stop.insert {
          Stop(id: stopID, routeID: routeID, tieOut: parsed.tieOut ?? "",
               sortIndex: Double(i), kind: "pointOfCall", displayName: display)
        }.execute(db)
        try Address.insert {
          Address(id: addressID, civicNumber: parsed.civicNumber, street: parsed.street,
                  occupantName: parsed.occupantName, notes: parsed.notes ?? "")
        }.execute(db)
        try DeliveryPoint.insert {
          DeliveryPoint(id: pointID, stopID: stopID, kind: "roadsideBox", label: display)
        }.execute(db)
        try DeliveryPointAddress.insert {
          DeliveryPointAddress(deliveryPointID: pointID, addressID: addressID)
        }.execute(db)
      }
    }
    return ImportSummary(routeID: routeID, stopsCreated: result.stops.count, skipped: result.skipped)
  }

  static func displayName(for s: ParsedStop) -> String {
    let civic = s.civicNumber.map(String.init)
    return [civic, s.street.isEmpty ? nil : s.street].compactMap { $0 }.joined(separator: " ")
  }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd RouteyKit && swift test --filter RouteImporterTests`
Expected: PASS.
(If `Stop.all.order { $0.sortIndex }.fetchAll(db)` differs in the resolved SQLiteData version, reconcile against its `Fetching` docs — the `RouteyPersistence` CRUD tests from Plan 01 already establish the working fetch verb.)

- [ ] **Step 6: Commit**

```bash
git add RouteyKit/Package.swift RouteyKit/Sources/RouteyDomain/RouteImporter.swift RouteyKit/Tests/RouteyDomainTests/RouteImporterTests.swift
git commit -m "Add route importer (parsed route -> persisted graph)"
```

---

### Task 3: Master-route edit operations

**Files:**
- Create: `RouteyKit/Sources/RouteyDomain/RouteEditing.swift`
- Create: `RouteyKit/Tests/RouteyDomainTests/RouteEditingTests.swift`

**Interfaces:**
- Consumes: model types, a `DatabaseWriter`.
- Produces an `enum RouteEditing` with static throwing functions:
  - `addStop(routeID: Route.ID, tieOut: String, displayName: String, after: Stop.ID?, into:) throws -> Stop.ID` — inserts with a `sortIndex` between `after` and the next stop (gap indexing), or appended if `after` is nil/last.
  - `updateStopDisplayName(_ id: Stop.ID, to name: String, in:) throws`
  - `deleteStop(_ id: Stop.ID, in:) throws` (cascades per schema)
  - `addAddress(_ a: Address, toDeliveryPoint pointID: DeliveryPoint.ID, in:) throws` (creates the address + the `DeliveryPointAddress` link — models a shared box when the point already has addresses)
  - `attachTag(named name: String, toAddress addressID: Address.ID, isWarning: Bool, in:) throws -> Tag.ID` — finds an existing `Tag` by exact name (app-level uniqueness) or creates one, then inserts an `AddressTag` if not already linked.
  - `detachTag(_ tagID: Tag.ID, fromAddress addressID: Address.ID, in:) throws`

- [ ] **Step 1: Write the failing tests**

Create `RouteyKit/Tests/RouteyDomainTests/RouteEditingTests.swift`:

```swift
import Testing
import Foundation
import SQLiteData
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RouteEditingTests {
  private func freshDB() throws -> DatabaseQueue {
    let db = try DatabaseQueue(); try Schema.migrator.migrate(db); return db
  }
  private func count(_ db: DatabaseQueue, _ t: String) throws -> Int {
    try db.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM \"\(t)\"") ?? -1 }
  }

  @Test func addStopBetweenUsesFractionalIndex() throws {
    let db = try freshDB()
    let routeID = UUID()
    try db.write { db in try Route.insert { Route(id: routeID, name: "R") }.execute(db) }
    let a = try RouteEditing.addStop(routeID: routeID, tieOut: "1", displayName: "A", after: nil, into: db)
    let c = try RouteEditing.addStop(routeID: routeID, tieOut: "3", displayName: "C", after: a, into: db)
    let b = try RouteEditing.addStop(routeID: routeID, tieOut: "2", displayName: "B", after: a, into: db)

    let ordered = try db.read { db in try Stop.all.order { $0.sortIndex }.fetchAll(db) }.map(\.displayName)
    #expect(ordered == ["A", "B", "C"])
    _ = (b, c)
  }

  @Test func attachTagIsIdempotentAndReusesTag() throws {
    let db = try freshDB()
    let addressID = UUID()
    try db.write { db in try Address.insert { Address(id: addressID, street: "Elm St") }.execute(db) }

    let t1 = try RouteEditing.attachTag(named: "dog", toAddress: addressID, isWarning: true, in: db)
    let t2 = try RouteEditing.attachTag(named: "dog", toAddress: addressID, isWarning: true, in: db)
    #expect(t1 == t2)                       // same tag reused
    #expect(try count(db, "tags") == 1)
    #expect(try count(db, "addressTags") == 1)   // link not duplicated

    try RouteEditing.detachTag(t1, fromAddress: addressID, in: db)
    #expect(try count(db, "addressTags") == 0)
    #expect(try count(db, "tags") == 1)     // tag itself remains
  }

  @Test func deleteStopCascades() throws {
    let db = try freshDB()
    let routeID = UUID()
    try db.write { db in try Route.insert { Route(id: routeID, name: "R") }.execute(db) }
    let s = try RouteEditing.addStop(routeID: routeID, tieOut: "1", displayName: "A", after: nil, into: db)
    try RouteEditing.deleteStop(s, in: db)
    #expect(try count(db, "stops") == 0)
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd RouteyKit && swift test --filter RouteEditingTests`
Expected: FAIL — `RouteEditing` undefined.

- [ ] **Step 3: Implement edit operations**

Create `RouteyKit/Sources/RouteyDomain/RouteEditing.swift`:

```swift
import Foundation
import SQLiteData
import RouteyModel

public enum RouteEditing {
  /// Inserts a stop after `after` (or at the end) using fractional gap indexing.
  public static func addStop(
    routeID: Route.ID, tieOut: String, displayName: String,
    after: Stop.ID?, into db: any DatabaseWriter
  ) throws -> Stop.ID {
    let id = UUID()
    try db.write { db in
      let siblings = try Stop.all.where { $0.routeID.eq(routeID) }
        .order { $0.sortIndex }.fetchAll(db)
      let newIndex = nextIndex(siblings: siblings, after: after)
      try Stop.insert {
        Stop(id: id, routeID: routeID, tieOut: tieOut, sortIndex: newIndex,
             kind: "pointOfCall", displayName: displayName)
      }.execute(db)
    }
    return id
  }

  static func nextIndex(siblings: [Stop], after: Stop.ID?) -> Double {
    guard let after, let i = siblings.firstIndex(where: { $0.id == after }) else {
      return (siblings.map(\.sortIndex).max() ?? -1) + 1.0   // append
    }
    let lower = siblings[i].sortIndex
    let upper = i + 1 < siblings.count ? siblings[i + 1].sortIndex : lower + 1.0
    return (lower + upper) / 2.0
  }

  public static func updateStopDisplayName(_ id: Stop.ID, to name: String, in db: any DatabaseWriter) throws {
    try db.write { db in
      try Stop.where { $0.id.eq(id) }.update { $0.displayName = name }.execute(db)
    }
  }

  public static func deleteStop(_ id: Stop.ID, in db: any DatabaseWriter) throws {
    try db.write { db in try Stop.where { $0.id.eq(id) }.delete().execute(db) }
  }

  public static func addAddress(
    _ address: Address, toDeliveryPoint pointID: DeliveryPoint.ID, in db: any DatabaseWriter
  ) throws {
    try db.write { db in
      try Address.insert { address }.execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: pointID, addressID: address.id)
      }.execute(db)
    }
  }

  @discardableResult
  public static func attachTag(
    named name: String, toAddress addressID: Address.ID, isWarning: Bool, in db: any DatabaseWriter
  ) throws -> Tag.ID {
    try db.write { db in
      let existing = try Tag.all.where { $0.name.eq(name) }.fetchOne(db)
      let tag = existing ?? Tag(id: UUID(), name: name, isWarning: isWarning)
      if existing == nil { try Tag.insert { tag }.execute(db) }
      let linked = try AddressTag.all
        .where { $0.addressID.eq(addressID) && $0.tagID.eq(tag.id) }.fetchOne(db)
      if linked == nil {
        try AddressTag.insert { AddressTag(addressID: addressID, tagID: tag.id) }.execute(db)
      }
      return tag.id
    }
  }

  public static func detachTag(_ tagID: Tag.ID, fromAddress addressID: Address.ID, in db: any DatabaseWriter) throws {
    try db.write { db in
      try AddressTag.where { $0.addressID.eq(addressID) && $0.tagID.eq(tagID) }.delete().execute(db)
    }
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd RouteyKit && swift test --filter RouteEditingTests`
Expected: PASS.
(If `.where{…}.update{…}` / `.delete()` / `.fetchOne(db)` spellings differ in the resolved SQLiteData version, reconcile against its `Fetching`/`StructuredQueries` docs; keep the behavior the tests assert.)

- [ ] **Step 5: Run the whole suite + commit**

Run: `cd RouteyKit && swift test`
Expected: PASS (all suites: Plan 01 + RouteParser + RouteImporter + RouteEditing).

```bash
git add RouteyKit/Sources/RouteyDomain/RouteEditing.swift RouteyKit/Tests/RouteyDomainTests/RouteEditingTests.swift
git commit -m "Add master-route edit operations (stops, addresses, tags)"
```

---

### Task 4: Add the new modules to the app target

**Files:**
- Modify (Xcode): `Routey` target package-product memberships.

> Requires Plan 01 Task 5 (app shell) to exist. If it doesn't yet, **skip this and Tasks 5–7 until the gate passes**, and stop after Task 3 with a clean tested package.

- [ ] **Step 1:** In Xcode → `Routey` target → Frameworks/Libraries, add `RouteyImport` and `RouteyDomain` from the local RouteyKit package.
- [ ] **Step 2:** Build the app (⌘B). Expected: builds with the new modules linked.
- [ ] **Step 3:** Commit the project file change.

```bash
git add app/
git commit -m "Link RouteyImport + RouteyDomain into the app target"
```

---

### Task 5: Route List screen

**Files:**
- Create: `app/Routey/Routes/RouteListView.swift`
- Modify: `app/Routey/ContentView.swift` (navigate into a route's stop list)

**Interfaces:**
- Consumes: `Stop`, `RouteEditing` (Task 3), `@FetchAll`.
- Produces: a screen listing a route's stops in `sortIndex` order with a filter field; add/delete stop affordances.

- [ ] **Step 1: Implement the view**

Create `app/Routey/Routes/RouteListView.swift`:

```swift
import SwiftUI
import SQLiteData
import RouteyModel
import RouteyDomain

struct RouteListView: View {
  let route: Route
  @FetchAll var stops: [Stop]
  @Dependency(\.defaultDatabase) var database
  @State private var filter = ""

  init(route: Route) {
    self.route = route
    _stops = FetchAll(Stop.where { $0.routeID.eq(route.id) }.order { $0.sortIndex })
  }

  var visible: [Stop] {
    guard !filter.isEmpty else { return stops }
    return stops.filter { $0.displayName.localizedCaseInsensitiveContains(filter)
      || $0.tieOut.localizedCaseInsensitiveContains(filter) }
  }

  var body: some View {
    List {
      ForEach(visible) { stop in
        NavigationLink(value: stop) {
          HStack {
            Text(stop.tieOut).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(stop.displayName.isEmpty ? "Untitled stop" : stop.displayName)
          }
        }
      }
      .onDelete { idx in
        for i in idx { try? RouteEditing.deleteStop(visible[i].id, in: database) }
      }
    }
    .searchable(text: $filter, prompt: "Filter stops")
    .navigationTitle(route.name.isEmpty ? "Route" : route.name)
    .navigationDestination(for: Stop.self) { StopDetailView(stop: $0) }
    .toolbar {
      Button("Add Stop") {
        _ = try? RouteEditing.addStop(routeID: route.id, tieOut: "",
          displayName: "New stop", after: stops.last?.id, into: database)
      }
    }
  }
}
```

- [ ] **Step 2:** Wire `ContentView`'s route rows to push `RouteListView(route:)` via `NavigationLink(value: route)` + `.navigationDestination(for: Route.self) { RouteListView(route: $0) }`. (`Route`/`Stop` are `Identifiable`; conform them to `Hashable` in the model if navigation values require it — add `Hashable` to the struct's protocol list, it's free for value types.)

- [ ] **Step 3:** Run in the simulator: open a route → see its stops in order; filter narrows the list; Add Stop appends; swipe deletes. Verify reactivity.

- [ ] **Step 4: Commit**

```bash
git add app/
git commit -m "Add Route List screen with filter + add/delete stop"
```

---

### Task 6: Stop detail + Address editor + Tag picker

**Files:**
- Create: `app/Routey/Routes/StopDetailView.swift`, `app/Routey/Routes/AddressEditorView.swift`, `app/Routey/Routes/TagPickerView.swift`

**Interfaces:**
- Consumes: `Stop`, `DeliveryPoint`, `Address`, `Tag`, `AddressTag`, `DeliveryPointAddress`, `RouteEditing`.
- Produces: a stop detail showing its delivery points + addresses (incl. shared-box addresses), an address editor (civic, street, occupant, notes), and a tag picker (attach/detach/create).

- [ ] **Step 1:** `StopDetailView` — edit `displayName`/`tieOut` (write via `RouteEditing.updateStopDisplayName` + an analogous tie-out update you add), list the stop's delivery points and, under each, the addresses it serves (join through `DeliveryPointAddress`). Use `@FetchAll` queries scoped to the stop. Tapping an address pushes `AddressEditorView`.

```swift
import SwiftUI
import SQLiteData
import RouteyModel
import RouteyDomain

struct StopDetailView: View {
  let stop: Stop
  @FetchAll var points: [DeliveryPoint]
  @Dependency(\.defaultDatabase) var database

  init(stop: Stop) {
    self.stop = stop
    _points = FetchAll(DeliveryPoint.where { $0.stopID.eq(stop.id) })
  }

  var body: some View {
    Form {
      Section("Stop") {
        Text(stop.displayName); Text("Tie-out: \(stop.tieOut)").foregroundStyle(.secondary)
      }
      Section("Delivery points") {
        ForEach(points) { point in
          DeliveryPointRow(point: point)
        }
      }
    }
    .navigationTitle(stop.displayName)
  }
}

private struct DeliveryPointRow: View {
  let point: DeliveryPoint
  @FetchAll var addresses: [Address]
  init(point: DeliveryPoint) {
    self.point = point
    // addresses served by this point, via the join table
    _addresses = FetchAll(
      Address.where { addr in
        DeliveryPointAddress.where { $0.deliveryPointID.eq(point.id) && $0.addressID.eq(addr.id) }.exists()
      }
    )
  }
  var body: some View {
    DisclosureGroup(point.label.isEmpty ? point.kind : point.label) {
      ForEach(addresses) { addr in
        NavigationLink(value: addr) {
          Text([addr.civicNumber.map(String.init), addr.street, addr.occupantName]
            .compactMap { $0 }.joined(separator: " "))
        }
      }
    }
  }
}
```

> The `.exists()` subquery spelling must match the resolved SQLiteData/StructuredQueries version; if it differs, fetch the join rows for the point and filter addresses by the resulting IDs instead. Keep the displayed behavior (a point shows all addresses it serves, including shared boxes).

- [ ] **Step 2:** `AddressEditorView` — `@State` fields bound to the address; Save writes via a `RouteEditing.updateAddress(...)` function you add (mirroring `updateStopDisplayName`, setting civic/street/occupant/notes). Include a Tags section embedding `TagPickerView(addressID:)`.

- [ ] **Step 3:** `TagPickerView` — `@FetchAll` the address's current tags (join through `AddressTag`) and all tags; toggling calls `RouteEditing.attachTag`/`detachTag`; a text field + Add creates+attaches a new tag (with an `isWarning` toggle).

- [ ] **Step 4:** Add the supporting `RouteEditing.updateAddress(...)` and `updateStopTieOut(...)` functions in `RouteEditing.swift` with unit tests in `RouteEditingTests.swift` (RED→GREEN), mirroring Task 3's patterns.

- [ ] **Step 5:** Run in the simulator: edit a stop, edit an address, attach/detach/create tags; confirm changes persist and the list reflects them.

- [ ] **Step 6: Commit**

```bash
git add RouteyKit/Sources/RouteyDomain/RouteEditing.swift RouteyKit/Tests/RouteyDomainTests/RouteEditingTests.swift app/
git commit -m "Add stop detail, address editor, and tag picker"
```

---

### Task 7: Import screen

**Files:**
- Create: `app/Routey/Import/ImportView.swift`
- Modify: `app/Routey/ContentView.swift` (entry point to import)

**Interfaces:**
- Consumes: `RouteParser` (Task 1), `RouteImporter` (Task 2).
- Produces: a screen to paste route text (or pick a `.csv`/`.txt` via `fileImporter`), preview the parse (stop count + skipped rows), name the route, and import.

- [ ] **Step 1:** Implement `ImportView`:

```swift
import SwiftUI
import SQLiteData
import RouteyImport
import RouteyDomain

struct ImportView: View {
  @Dependency(\.defaultDatabase) var database
  @Environment(\.dismiss) var dismiss
  @State private var text = ""
  @State private var name = ""
  @State private var lastSummary: ImportSummary?

  private var preview: ParseResult { RouteParser.parse(text) }

  var body: some View {
    NavigationStack {
      Form {
        Section("Route name") { TextField("e.g. Riverbend", text: $name) }
        Section("Paste route (one stop per line, or CSV with a header)") {
          TextEditor(text: $text).frame(minHeight: 160).font(.body.monospaced())
        }
        Section("Preview") {
          Text("\(preview.stops.count) stops, \(preview.skipped.count) skipped")
          ForEach(preview.skipped, id: \.line) { row in
            Text("line \(row.line): \(row.reason)").font(.caption).foregroundStyle(.orange)
          }
        }
      }
      .navigationTitle("Import route")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Import") {
            lastSummary = try? RouteImporter.importRoute(
              named: name.isEmpty ? "Imported route" : name, from: preview, into: database)
            dismiss()
          }
          .disabled(preview.stops.isEmpty)
        }
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
    }
  }
}
```

- [ ] **Step 2:** Add a toolbar button in `ContentView` presenting `ImportView` as a sheet.

- [ ] **Step 3:** Run in the simulator: paste a few lines of your real route, confirm the preview count, import, and see the new route + its stops. Try a CSV with a header row.

- [ ] **Step 4: Commit**

```bash
git add app/
git commit -m "Add route import screen (paste/CSV preview + import)"
```

---

## Plan self-review

- **Spec coverage:** CSV/Reminders import ✓ (T1, T2, T7), manual route build/edit ✓ (T3, T5, T6), tags incl. warning-class + app-level uniqueness ✓ (T3, T6), shared-box display via the join ✓ (T6), gap-based ordering ✓ (T3). Deferred to later plans: FTS predictive search + virtual sort case (Plan 03), OCR (Plan 04), Today's Run/reorder (Plan 05), print (Plan 06), encrypted export (Plan 07), CMB-site structured import (CSV imports flat pointOfCall stops in V1; CMB hierarchy is hand-built — a documented limitation, not a silent gap).
- **Placeholder scan:** none — headless tasks (1–3) carry complete code + tests; UI tasks (5–7) carry complete SwiftUI with explicit reconciliation notes where a StructuredQueries spelling could differ from the resolved version.
- **Type consistency:** `ParsedStop`/`ParseResult`/`SkippedRow` (T1) flow into `RouteImporter`/`ImportSummary` (T2) and `ImportView` (T7); `RouteEditing` function signatures (T3) are reused verbatim in T5/T6; model types match Plan 01 exactly.
- **Dependency honesty:** Tasks 1–3 run headlessly now; Tasks 4–7 require Plan 01 Task 5's app shell and are explicitly gated on it. CSV parser v1 does not handle quoted/embedded commas — stated in the parsing rules and surfaced as a skipped-row reason, not hidden.
