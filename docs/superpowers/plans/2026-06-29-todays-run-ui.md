# Today's Run UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Today's Run drive loop — a TabView home whose Run tab shows today's run as an ordered, check-offable stop list with parcel/warning badges, backed by pure `RouteyDomain` read-model loaders.

**Implementation status 2026-06-30:** Implemented on `codex/todays-run-ui`
through Task 6: `RunOperations.setRunStopDone`, `RunBoard`, `RunStopDetail`,
the Run/Routes/Search TabView shell, live Run board, single and bulk check-off,
read-only stop detail, and drag reorder. Task 7 updates the project docs. The
broader delivery-loop follow-ups remain proof-of-delivery/outcome UI, filters,
follow-up task UI, and a full device truck-loop gesture pass.

**Architecture:** Two pure, Mac-testable read-model loaders (`RunBoard`, `RunStopDetail`) and one new write op (`setRunStopDone`) go in `RouteyDomain`. The app gets a `TabView` (Run/Routes/Search), and the Run tab observes `RunBoard` live via SQLiteData's `@Fetch`/`FetchKeyRequest` (whose `fetch(_ db: Database)` calls the same loader the tests call). Existing tested ops (`RunGeneration.generate`, `bulkCheckOff`, `moveRunStop`) are reused.

**Tech Stack:** Swift 6, SwiftUI (TabView `Tab` API, `List` with `.swipeActions`/`.onMove`), SQLiteData/GRDB (`@Fetch`/`FetchKeyRequest`), Swift Testing.

## Global Constraints

- **Swift Testing only** (not XCTest). Package tests: `cd RouteyKit && swift test`.
- **App deployment target iOS 18.0**; `RouteyKit` floor iOS 17 / macOS 14.
- **No synced-schema change.** This slice only *reads* the graph and toggles `RunStop.isDone` (an existing column). Do NOT add/alter synced tables or columns.
- **House query style (enforced):** parameterized StructuredQueries only — `Model.where { $0.col.eq(#bind(value)) }.order { $0.sortIndex }.fetchAll(db)`, `Model.all.fetchAll(db)`, `Model.find(id).fetchOne(db)`, `Model.find(id).update { $0.col = #bind(value) }.execute(db)`. **No `.join`/`.leftJoin`/`Select{}`/`.in([...])` — they appear nowhere; join and set-membership are done in Swift via dictionaries (`ReportBuilder` precedent).** Never string-interpolated SQL.
- **Warning tag = `Tag.isWarning == true`** (a bool field, not a name).
- **Read-model loaders take a GRDB `Database`** (`_ db: Database`), so they work inside both `FetchKeyRequest.fetch(_ db:)` and `database.read { db in … }`.
- **App DI:** views read `@Dependency(\.defaultDatabase)` / `@Dependency(\.defaultSyncEngine)`; after a write, fire `Task { await RouteySyncing.sendChanges(reason:using: syncEngine) }`. Errors → an `.alert` via `errorMessage`/`isShowingError` @State (the `RouteStopsView.show(_:)` idiom).
- **New `.swift` files under `app/Routey/Routey/` auto-compile** (Xcode 16 synchronized groups) — never add `project.pbxproj` entries for source files. `RouteyDomain` is already linked to the app.
- **Single-route assumption:** the Run tab uses `routes.first` (V1 has one route), same as Snap-to-Add.
- **Carrier-agnostic:** invented placeholders only in all seed/test/sample data and copy.
- **End every task with a commit** (Conventional Commits, `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`).

---

### Task 1: `RunOperations.setRunStopDone` (single-stop check-off)

**Files:**
- Modify: `RouteyKit/Sources/RouteyDomain/RunOperations.swift`
- Test: `RouteyKit/Tests/RouteyDomainTests/RunOperationTests.swift`

**Interfaces:**
- Consumes: `RunStop` model; the existing private `freshDB()` / `seedRun(in:stopCount:)` helpers in `RunOperationTests.swift`.
- Produces: `public static func setRunStopDone(_ id: RunStop.ID, done: Bool, in database: any DatabaseWriter) throws` — sets one `RunStop.isDone`. Used by `RunBoardView` (Task 5).

- [ ] **Step 1: Write the failing test** — append to `RunOperationTests.swift`:

```swift
@Test func setRunStopDoneTogglesASingleStop() throws {
  let database = try freshDB()
  let (_, runID) = try seedRun(in: database, stopCount: 3)
  let stops = try database.read { db in
    try RunStop.where { $0.runID.eq(#bind(runID)) }.order { $0.sortIndex }.fetchAll(db)
  }
  let target = stops[1]

  try RunOperations.setRunStopDone(target.id, done: true, in: database)
  let afterOn = try database.read { db in try RunStop.find(target.id).fetchOne(db) }
  #expect(afterOn?.isDone == true)
  // only the one stop changed
  let others = try database.read { db in
    try RunStop.where { $0.runID.eq(#bind(runID)) }.fetchAll(db)
  }.filter { $0.id != target.id }
  #expect(others.allSatisfy { $0.isDone == false })

  try RunOperations.setRunStopDone(target.id, done: false, in: database)
  let afterOff = try database.read { db in try RunStop.find(target.id).fetchOne(db) }
  #expect(afterOff?.isDone == false)
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd RouteyKit && swift test --filter RunOperationTests`
Expected: FAIL — `setRunStopDone` undefined.

- [ ] **Step 3: Implement** — add inside `enum RunOperations`, after `bulkCheckOff`:

```swift
public static func setRunStopDone(_ id: RunStop.ID, done: Bool, in database: any DatabaseWriter) throws {
  try database.write { db in
    try RunStop.find(id).update { $0.isDone = #bind(done) }.execute(db)
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd RouteyKit && swift test --filter RunOperationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Sources/RouteyDomain/RunOperations.swift RouteyKit/Tests/RouteyDomainTests/RunOperationTests.swift
git commit -m "$(cat <<'EOF'
feat(domain): add RunOperations.setRunStopDone single-stop check-off

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `RunBoard` read-model + loader

**Files:**
- Create: `RouteyKit/Sources/RouteyDomain/RunBoard.swift`
- Test: `RouteyKit/Tests/RouteyDomainTests/RunBoardTests.swift`

**Interfaces:**
- Consumes: `RunStop`, `Parcel`, `DeliveryPoint`, `DeliveryPointAddress`, `AddressTag`, `Tag` models; GRDB `Database` (via `import SQLiteData`).
- Produces:
  - `public struct RunStopSummary: Equatable, Identifiable, Sendable` — fields `runStopID: UUID`, `stopID: UUID?`, `tieOut: String`, `displayName: String`, `kind: String`, `isDone: Bool`, `sortIndex: Double`, `hasWarning: Bool`, `parcelCount: Int`; `id` returns `runStopID`.
  - `public struct RunBoard: Equatable, Sendable` — fields `total: Int`, `doneCount: Int`, `signatureCount: Int`, `stops: [RunStopSummary]`; `public static let empty`; `public static func load(runID: TodaysRun.ID, _ db: Database) throws -> RunBoard`.
  - Consumed by `RunBoardRequest`/`RunBoardView` (Task 4).

- [ ] **Step 1: Write the failing test** — create `RunBoardTests.swift`:

```swift
import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RunBoardTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  @Test func boardSummarizesWarningsParcelsAndProgress() throws {
    let database = try freshDB()
    let routeID = UUID()
    let dogTagID = UUID()
    let plainTagID = UUID()
    // Stop A: one address with a dog tag + 1 parcel. Stop B: one address, no tag, no parcel.
    let stopAID = UUID(), stopBID = UUID()
    let dpAID = UUID(), dpBID = UUID()
    let addrAID = UUID(), addrBID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try Stop.insert { Stop(id: stopAID, routeID: routeID, tieOut: "1", sortIndex: 0, displayName: "Stop A") }.execute(db)
      try Stop.insert { Stop(id: stopBID, routeID: routeID, tieOut: "2", sortIndex: 1, displayName: "Stop B") }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: dpAID, stopID: stopAID) }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: dpBID, stopID: stopBID) }.execute(db)
      try Address.insert { Address(id: addrAID, civicNumber: 101, street: "Maple Road") }.execute(db)
      try Address.insert { Address(id: addrBID, civicNumber: 102, street: "Maple Road") }.execute(db)
      try DeliveryPointAddress.insert { DeliveryPointAddress(deliveryPointID: dpAID, addressID: addrAID) }.execute(db)
      try DeliveryPointAddress.insert { DeliveryPointAddress(deliveryPointID: dpBID, addressID: addrBID) }.execute(db)
      try Tag.insert { Tag(id: dogTagID, name: "dog", isWarning: true) }.execute(db)
      try Tag.insert { Tag(id: plainTagID, name: "no-flyers", isWarning: false) }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addrAID, tagID: dogTagID) }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addrBID, tagID: plainTagID) }.execute(db)
    }
    let runID = try RunGeneration.generate(routeID: routeID, serviceDate: "2026-06-29", now: Date(timeIntervalSince1970: 1_782_000_000), into: database)
    // one signature-required parcel for address A
    try RunOperations.addParcel(runID: runID, addressID: addrAID, source: "manual", requiresSignature: true, isCustoms: false, toDoor: false, labelSnapshot: "L", trackingCode: "", trackingSymbology: "", in: database)

    let board = try database.read { db in try RunBoard.load(runID: runID, db) }

    #expect(board.total == 2)
    #expect(board.doneCount == 0)
    #expect(board.signatureCount == 1)
    #expect(board.stops.map(\.displayName) == ["Stop A", "Stop B"])   // ordered by sortIndex
    let a = try #require(board.stops.first { $0.displayName == "Stop A" })
    let b = try #require(board.stops.first { $0.displayName == "Stop B" })
    #expect(a.hasWarning == true)
    #expect(a.parcelCount == 1)
    #expect(b.hasWarning == false)
    #expect(b.parcelCount == 0)
  }

  @Test func emptyRunYieldsZeroes() throws {
    let database = try freshDB()
    let routeID = UUID()
    try database.write { db in try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db) }
    let runID = try RunGeneration.generate(routeID: routeID, serviceDate: "2026-06-29", now: Date(timeIntervalSince1970: 1_782_000_000), into: database)
    let board = try database.read { db in try RunBoard.load(runID: runID, db) }
    #expect(board == RunBoard.empty)
  }
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd RouteyKit && swift test --filter RunBoardTests`
Expected: FAIL — `RunBoard` undefined.

- [ ] **Step 3: Implement** — create `RunBoard.swift`:

```swift
import Foundation
import RouteyModel
import SQLiteData

public struct RunStopSummary: Equatable, Identifiable, Sendable {
  public var runStopID: UUID
  public var stopID: UUID?
  public var tieOut: String
  public var displayName: String
  public var kind: String
  public var isDone: Bool
  public var sortIndex: Double
  public var hasWarning: Bool
  public var parcelCount: Int

  public var id: UUID { runStopID }

  public init(
    runStopID: UUID, stopID: UUID?, tieOut: String, displayName: String, kind: String,
    isDone: Bool, sortIndex: Double, hasWarning: Bool, parcelCount: Int
  ) {
    self.runStopID = runStopID
    self.stopID = stopID
    self.tieOut = tieOut
    self.displayName = displayName
    self.kind = kind
    self.isDone = isDone
    self.sortIndex = sortIndex
    self.hasWarning = hasWarning
    self.parcelCount = parcelCount
  }
}

public struct RunBoard: Equatable, Sendable {
  public var total: Int
  public var doneCount: Int
  public var signatureCount: Int
  public var stops: [RunStopSummary]

  public init(total: Int = 0, doneCount: Int = 0, signatureCount: Int = 0, stops: [RunStopSummary] = []) {
    self.total = total
    self.doneCount = doneCount
    self.signatureCount = signatureCount
    self.stops = stops
  }

  public static let empty = RunBoard()

  public static func load(runID: TodaysRun.ID, _ db: Database) throws -> RunBoard {
    let runStops = try RunStop.where { $0.runID.eq(#bind(runID)) }.order { $0.sortIndex }.fetchAll(db)
    let parcels = try Parcel.where { $0.runID.eq(#bind(runID)) }.fetchAll(db)

    // Fetch the master graph (fetch-all + filter-in-Swift, per house style).
    let stopIDs = Set(runStops.compactMap(\.stopID))
    let deliveryPoints = try DeliveryPoint.all.fetchAll(db).filter { stopIDs.contains($0.stopID) }
    let pointStopByID = Dictionary(uniqueKeysWithValues: deliveryPoints.map { ($0.id, $0.stopID) })
    let pointIDs = Set(deliveryPoints.map(\.id))
    let links = try DeliveryPointAddress.all.fetchAll(db).filter { pointIDs.contains($0.deliveryPointID) }
    let addressIDs = Set(links.map(\.addressID))
    let addressTags = try AddressTag.all.fetchAll(db).filter { addressIDs.contains($0.addressID) }
    let warningTagIDs = Set(try Tag.all.fetchAll(db).filter(\.isWarning).map(\.id))
    let warnedAddressIDs = Set(addressTags.filter { warningTagIDs.contains($0.tagID) }.map(\.addressID))

    // stop -> addressIDs, and address -> its stopIDs (an address may sit under >1 point).
    var addressIDsByStop: [UUID: Set<UUID>] = [:]
    var stopIDsByAddress: [UUID: Set<UUID>] = [:]
    for link in links {
      guard let stopID = pointStopByID[link.deliveryPointID] else { continue }
      addressIDsByStop[stopID, default: []].insert(link.addressID)
      stopIDsByAddress[link.addressID, default: []].insert(stopID)
    }

    // stop -> parcel count (a parcel's address may belong to >1 stop).
    var parcelCountByStop: [UUID: Int] = [:]
    for parcel in parcels {
      guard let addressID = parcel.addressID, let stops = stopIDsByAddress[addressID] else { continue }
      for stopID in stops { parcelCountByStop[stopID, default: 0] += 1 }
    }

    let summaries = runStops.map { runStop -> RunStopSummary in
      let addresses = runStop.stopID.flatMap { addressIDsByStop[$0] } ?? []
      return RunStopSummary(
        runStopID: runStop.id,
        stopID: runStop.stopID,
        tieOut: runStop.tieOut,
        displayName: runStop.displayName,
        kind: runStop.kind,
        isDone: runStop.isDone,
        sortIndex: runStop.sortIndex,
        hasWarning: !addresses.isDisjoint(with: warnedAddressIDs),
        parcelCount: runStop.stopID.flatMap { parcelCountByStop[$0] } ?? 0
      )
    }

    return RunBoard(
      total: runStops.count,
      doneCount: runStops.filter(\.isDone).count,
      signatureCount: parcels.filter { $0.requiresSignature && !$0.isDelivered }.count,
      stops: summaries
    )
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd RouteyKit && swift test --filter RunBoardTests`
Expected: PASS. (If `Database` is not in scope, add `import GRDB` — it's a transitive dependency via SQLiteData.)

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Sources/RouteyDomain/RunBoard.swift RouteyKit/Tests/RouteyDomainTests/RunBoardTests.swift
git commit -m "$(cat <<'EOF'
feat(domain): add RunBoard read-model loader

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `RunStopDetail` read-model + loader

**Files:**
- Create: `RouteyKit/Sources/RouteyDomain/RunStopDetail.swift`
- Test: `RouteyKit/Tests/RouteyDomainTests/RunStopDetailTests.swift`

**Interfaces:**
- Consumes: `RunStop`, `DeliveryPoint`, `DeliveryPointAddress`, `Address`, `AddressTag`, `Tag`, `Parcel`; GRDB `Database`.
- Produces:
  - `public struct RunStopDetail: Equatable, Sendable` with nested `AddressLine` (`id: UUID`, `civic: String`, `street: String`, `occupant: String?`) and `ParcelLine` (`id: UUID`, `labelSnapshot: String`, `trackingCode: String`, `requiresSignature: Bool`, `isCustoms: Bool`, `isDelivered: Bool`); fields `addresses: [AddressLine]`, `parcels: [ParcelLine]`, `warningTags: [String]`; `public static let empty`; `public static func load(runStopID: RunStop.ID, runID: TodaysRun.ID, _ db: Database) throws -> RunStopDetail`.
  - Consumed by `RunStopDetailView` (Task 5).

- [ ] **Step 1: Write the failing test** — create `RunStopDetailTests.swift`:

```swift
import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct RunStopDetailTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  @Test func detailHydratesAddressesParcelsAndWarnings() throws {
    let database = try freshDB()
    let routeID = UUID(), stopID = UUID(), dpID = UUID(), addrID = UUID(), dogTagID = UUID()
    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try Stop.insert { Stop(id: stopID, routeID: routeID, tieOut: "1", sortIndex: 0, displayName: "Stop A") }.execute(db)
      try DeliveryPoint.insert { DeliveryPoint(id: dpID, stopID: stopID) }.execute(db)
      try Address.insert { Address(id: addrID, civicNumber: 101, street: "Maple Road", occupantName: "Pat Lee") }.execute(db)
      try DeliveryPointAddress.insert { DeliveryPointAddress(deliveryPointID: dpID, addressID: addrID) }.execute(db)
      try Tag.insert { Tag(id: dogTagID, name: "dog", isWarning: true) }.execute(db)
      try AddressTag.insert { AddressTag(addressID: addrID, tagID: dogTagID) }.execute(db)
    }
    let runID = try RunGeneration.generate(routeID: routeID, serviceDate: "2026-06-29", now: Date(timeIntervalSince1970: 1_782_000_000), into: database)
    try RunOperations.addParcel(runID: runID, addressID: addrID, source: "ocr", requiresSignature: true, isCustoms: false, toDoor: false, labelSnapshot: "101 Maple", trackingCode: "ZX1", trackingSymbology: "", in: database)
    let runStop = try #require(try database.read { db in
      try RunStop.where { $0.runID.eq(#bind(runID)) }.fetchAll(db).first { $0.stopID == stopID }
    })

    let detail = try database.read { db in try RunStopDetail.load(runStopID: runStop.id, runID: runID, db) }

    #expect(detail.addresses.map(\.street) == ["Maple Road"])
    #expect(detail.addresses.first?.occupant == "Pat Lee")
    #expect(detail.addresses.first?.civic == "101")
    #expect(detail.parcels.map(\.trackingCode) == ["ZX1"])
    #expect(detail.parcels.first?.requiresSignature == true)
    #expect(detail.warningTags == ["dog"])
  }
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd RouteyKit && swift test --filter RunStopDetailTests`
Expected: FAIL — `RunStopDetail` undefined.

- [ ] **Step 3: Implement** — create `RunStopDetail.swift`:

```swift
import Foundation
import RouteyModel
import SQLiteData

public struct RunStopDetail: Equatable, Sendable {
  public struct AddressLine: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var civic: String
    public var street: String
    public var occupant: String?
    public init(id: UUID, civic: String, street: String, occupant: String?) {
      self.id = id; self.civic = civic; self.street = street; self.occupant = occupant
    }
  }

  public struct ParcelLine: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var labelSnapshot: String
    public var trackingCode: String
    public var requiresSignature: Bool
    public var isCustoms: Bool
    public var isDelivered: Bool
    public init(id: UUID, labelSnapshot: String, trackingCode: String, requiresSignature: Bool, isCustoms: Bool, isDelivered: Bool) {
      self.id = id; self.labelSnapshot = labelSnapshot; self.trackingCode = trackingCode
      self.requiresSignature = requiresSignature; self.isCustoms = isCustoms; self.isDelivered = isDelivered
    }
  }

  public var addresses: [AddressLine]
  public var parcels: [ParcelLine]
  public var warningTags: [String]

  public init(addresses: [AddressLine] = [], parcels: [ParcelLine] = [], warningTags: [String] = []) {
    self.addresses = addresses
    self.parcels = parcels
    self.warningTags = warningTags
  }

  public static let empty = RunStopDetail()

  public static func load(runStopID: RunStop.ID, runID: TodaysRun.ID, _ db: Database) throws -> RunStopDetail {
    guard let runStop = try RunStop.find(runStopID).fetchOne(db), let stopID = runStop.stopID else {
      return .empty
    }
    let deliveryPoints = try DeliveryPoint.where { $0.stopID.eq(#bind(stopID)) }.fetchAll(db)
    let pointIDs = Set(deliveryPoints.map(\.id))
    let links = try DeliveryPointAddress.all.fetchAll(db).filter { pointIDs.contains($0.deliveryPointID) }
    let addressIDs = Set(links.map(\.addressID))
    let addresses = try Address.all.fetchAll(db).filter { addressIDs.contains($0.id) }
    let addressTags = try AddressTag.all.fetchAll(db).filter { addressIDs.contains($0.addressID) }
    let warnedTagIDs = Set(addressTags.map(\.tagID))
    let warningTags = try Tag.all.fetchAll(db).filter { $0.isWarning && warnedTagIDs.contains($0.id) }.map(\.name)
    let parcels = try Parcel.where { $0.runID.eq(#bind(runID)) }.fetchAll(db)
      .filter { parcel in parcel.addressID.map { addressIDs.contains($0) } ?? false }

    let addressLines = addresses
      .sorted { ($0.civicNumber ?? 0, $0.street) < ($1.civicNumber ?? 0, $1.street) }
      .map { AddressLine(id: $0.id, civic: Self.civicDisplay($0), street: $0.street, occupant: $0.occupantName) }
    let parcelLines = parcels.map {
      ParcelLine(id: $0.id, labelSnapshot: $0.labelSnapshot, trackingCode: $0.trackingCode,
                 requiresSignature: $0.requiresSignature, isCustoms: $0.isCustoms, isDelivered: $0.isDelivered)
    }
    return RunStopDetail(addresses: addressLines, parcels: parcelLines, warningTags: warningTags.sorted())
  }

  private static func civicDisplay(_ address: Address) -> String {
    if let civic = address.civicNumber { return String(civic) }
    if let from = address.civicRangeFrom, let to = address.civicRangeTo { return "\(from)-\(to)" }
    return ""
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd RouteyKit && swift test --filter RunStopDetailTests`
Expected: PASS.

- [ ] **Step 5: Run the full package suite**

Run: `cd RouteyKit && swift test`
Expected: PASS (all suites green).

- [ ] **Step 6: Commit**

```bash
git add RouteyKit/Sources/RouteyDomain/RunStopDetail.swift RouteyKit/Tests/RouteyDomainTests/RunStopDetailTests.swift
git commit -m "$(cat <<'EOF'
feat(domain): add RunStopDetail read-model loader

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: TabView restructure + read-only Run board

**Files:**
- Modify: `app/Routey/Routey/ContentView.swift` (becomes the TabView; hoists the sync lifecycle)
- Create: `app/Routey/Routey/Routes/RoutesView.swift` (the current route-list body, moved verbatim)
- Create: `app/Routey/Routey/Run/RunBoardRequest.swift`
- Create: `app/Routey/Routey/Run/RunView.swift`
- Create: `app/Routey/Routey/Run/RunBoardView.swift`
- Create: `app/Routey/Routey/Run/RunStopRowView.swift`

**Interfaces:**
- Consumes: `RunBoard`/`RunStopSummary` + `RunGeneration.generate` (RouteyDomain); `@Dependency(\.defaultDatabase)`, `@Dependency(\.defaultSyncEngine)`; SQLiteData `@Fetch`/`FetchKeyRequest`; existing `SearchView`, `ImportRouteView`, `RouteStopsView`, `RouteySyncing`.
- Produces: a `TabView` app shell (Run/Routes/Search) with the Run tab showing today's run **read-only** (no check-off/reorder yet — those are Tasks 5–6).

**Read-only first:** this task delivers the screen and the live board; the ○ is a static icon and the row is non-interactive. Interactions are added in Tasks 5–6 so each is independently reviewable.

- [ ] **Step 1: Move the current route list into `RoutesView`.** Create `RoutesView.swift` containing the **current `ContentView` body verbatim** (the `NavigationStack` with the route `List`, `.navigationDestination`s, the Import toolbar button + sheet, the `routes.isEmpty` overlay) but **without** the Search toolbar `NavigationLink`/`ContentDestination` (Search becomes a tab) and **without** the `.task`/`scenePhase` sync block (hoisted in Step 2). It reads `@FetchAll(Route.order { $0.name }) private var routes` and `@State private var isImportingRoute`. It needs no `@Dependency` (it doesn't sync directly).

```swift
import SQLiteData
import SwiftUI
import RouteyModel

struct RoutesView: View {
  @FetchAll(Route.order { $0.name }) private var routes: [Route]
  @State private var isImportingRoute = false

  var body: some View {
    NavigationStack {
      List(routes) { route in
        NavigationLink(value: route) {
          VStack(alignment: .leading) {
            Text(route.name.isEmpty ? "Untitled route" : route.name)
            if !route.rtaFSA.isEmpty {
              Text(route.rtaFSA).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle("Routes (\(routes.count))")
      .navigationDestination(for: Route.self) { route in
        RouteStopsView(route: route)
      }
      .toolbar {
        Button("Import", systemImage: "square.and.arrow.down") { isImportingRoute = true }
      }
      .sheet(isPresented: $isImportingRoute) { ImportRouteView() }
      .overlay {
        if routes.isEmpty {
          ContentUnavailableView("No Routes", systemImage: "map")
        }
      }
    }
  }
}
```

- [ ] **Step 2: Replace `ContentView` with the TabView (sync lifecycle hoisted here).**

```swift
import SQLiteData
import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Dependency(\.defaultSyncEngine) private var syncEngine

  var body: some View {
    TabView {
      Tab("Run", systemImage: "shippingbox") { RunView() }
      Tab("Routes", systemImage: "map") { RoutesView() }
      Tab("Search", systemImage: "magnifyingglass") {
        NavigationStack { SearchView() }
      }
    }
    .task {
      await RouteySyncing.synchronize(reason: "app appeared", using: syncEngine)
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        Task { await RouteySyncing.synchronize(reason: "app became active", using: syncEngine) }
      case .background:
        Task { await RouteySyncing.sendChanges(reason: "app entered background", using: syncEngine) }
      case .inactive:
        break
      @unknown default:
        break
      }
    }
  }
}

#Preview { ContentView() }
```

(Delete the old `private enum ContentDestination` from `ContentView.swift` — Search is a tab now. `SearchView` gets its own `NavigationStack` in the tab because it uses `.navigationTitle`/`.searchable`.)

- [ ] **Step 3: Create the observed board request.**

```swift
// app/Routey/Routey/Run/RunBoardRequest.swift
import RouteyDomain
import RouteyModel
import SQLiteData

struct RunBoardRequest: FetchKeyRequest {
  let runID: TodaysRun.ID
  func fetch(_ db: Database) throws -> RunBoard {
    try RunBoard.load(runID: runID, db)
  }
}
```

- [ ] **Step 4: Create `RunView` (route selection + idempotent run generation).**

```swift
// app/Routey/Routey/Run/RunView.swift
import Foundation
import RouteyDomain
import RouteyModel
import SQLiteData
import SwiftUI

struct RunView: View {
  @Dependency(\.defaultDatabase) private var database
  @FetchAll(Route.order { $0.name }) private var routes: [Route]
  @State private var runID: TodaysRun.ID?
  @State private var errorMessage = ""
  @State private var isShowingError = false

  var body: some View {
    NavigationStack {
      Group {
        if routes.first == nil {
          ContentUnavailableView("No Route", systemImage: "map", description: Text("Import a route on the Routes tab to start a run."))
        } else if let runID {
          RunBoardView(runID: runID)
        } else {
          ProgressView()
        }
      }
      .navigationTitle("Today's Run")
      .navigationBarTitleDisplayMode(.inline)
    }
    .task(id: routes.first?.id) {
      guard let route = routes.first else { return }
      do {
        runID = try RunGeneration.generate(
          routeID: route.id,
          serviceDate: Self.serviceDate(for: .now),
          now: .now,
          into: database
        )
      } catch {
        errorMessage = error.localizedDescription
        isShowingError = true
      }
    }
    .alert("Couldn't open today's run", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorMessage) }
  }

  static func serviceDate(for date: Date) -> String {
    date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
  }
}
```

- [ ] **Step 5: Create `RunBoardView` (observed board + header + read-only list).**

```swift
// app/Routey/Routey/Run/RunBoardView.swift
import RouteyDomain
import RouteyModel
import SQLiteData
import SwiftUI

struct RunBoardView: View {
  @Fetch private var board: RunBoard

  init(runID: TodaysRun.ID) {
    _board = Fetch(wrappedValue: RunBoard.empty, RunBoardRequest(runID: runID))
  }

  var body: some View {
    List {
      Section {
        HStack {
          Text("\(board.doneCount)/\(board.total) done")
          Spacer()
          if board.signatureCount > 0 {
            Label("\(board.signatureCount)", systemImage: "signature")
          }
        }
        .font(.headline)
      }
      if board.stops.isEmpty {
        ContentUnavailableView("No stops yet", systemImage: "shippingbox")
      } else {
        ForEach(board.stops) { stop in
          RunStopRowView(stop: stop)
        }
      }
    }
  }
}
```

- [ ] **Step 6: Create `RunStopRowView` (read-only row).**

```swift
// app/Routey/Routey/Run/RunStopRowView.swift
import RouteyDomain
import SwiftUI

struct RunStopRowView: View {
  let stop: RunStopSummary

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: stop.isDone ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(stop.isDone ? .green : .secondary)
      VStack(alignment: .leading) {
        Text(stop.tieOut.isEmpty ? stop.displayName : stop.tieOut)
        if !stop.displayName.isEmpty && !stop.tieOut.isEmpty {
          Text(stop.displayName).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
      if stop.hasWarning {
        Image(systemName: "dog").foregroundStyle(.orange)
      }
      if stop.parcelCount > 0 {
        Label("\(stop.parcelCount)", systemImage: "shippingbox.fill")
          .labelStyle(.titleAndIcon).font(.caption)
      }
    }
    .opacity(stop.isDone ? 0.5 : 1)
  }
}
```

- [ ] **Step 7: Build to verify the restructure compiles and the Run tab renders**

Run: `"$HOME/.claude/bin/xcode-build-gate.sh" --wait && xcodebuild -project app/Routey/Routey.xcodeproj -scheme Routey -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`. (If `@Fetch`/`Fetch(wrappedValue:_:)` or the `Tab` initializer differ from the forms above, adjust to the SQLiteData / iOS 18 SDK signatures — mirror the existing `@FetchAll` init-form in `RouteStopsView` for the `Fetch` backing-store pattern.)

- [ ] **Step 8: Commit**

```bash
git add app/Routey/Routey/ContentView.swift app/Routey/Routey/Routes/RoutesView.swift app/Routey/Routey/Run
git commit -m "$(cat <<'EOF'
feat(app): add TabView shell and read-only Today's Run board

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Check-off (single + bulk) + stop detail

**Files:**
- Modify: `app/Routey/Routey/Run/RunBoardView.swift` (wire writes + swipe + navigation)
- Modify: `app/Routey/Routey/Run/RunStopRowView.swift` (make the ○ a Button, the body a Button)
- Create: `app/Routey/Routey/Run/RunStopDetailView.swift`

**Interfaces:**
- Consumes: `RunOperations.setRunStopDone`, `RunOperations.bulkCheckOff`, `RunStopDetail.load` (RouteyDomain); `@Dependency(\.defaultDatabase)`/`@Dependency(\.defaultSyncEngine)`; `RouteySyncing.sendChanges`.
- Produces: an interactive board — tap ○ to toggle a stop done, swipe for "Done through here", tap the row to push `RunStopDetailView`.

- [ ] **Step 1: Add the write/sync helpers + swipe + navigation to `RunBoardView`.** Replace the file with:

```swift
import RouteyDomain
import RouteyModel
import SQLiteData
import SwiftUI

struct RunBoardView: View {
  let runID: TodaysRun.ID
  @Fetch private var board: RunBoard
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @State private var errorMessage = ""
  @State private var isShowingError = false

  init(runID: TodaysRun.ID) {
    self.runID = runID
    _board = Fetch(wrappedValue: RunBoard.empty, RunBoardRequest(runID: runID))
  }

  var body: some View {
    List {
      Section {
        HStack {
          Text("\(board.doneCount)/\(board.total) done")
          Spacer()
          if board.signatureCount > 0 {
            Label("\(board.signatureCount)", systemImage: "signature")
          }
        }
        .font(.headline)
      }
      if board.stops.isEmpty {
        ContentUnavailableView("No stops yet", systemImage: "shippingbox")
      } else {
        ForEach(board.stops) { stop in
          NavigationLink(value: stop.runStopID) {
            RunStopRowView(stop: stop) { toggle(stop) }
          }
          .swipeActions(edge: .trailing) {
            Button("Done through here", systemImage: "checkmark.circle") { bulk(stop) }
              .tint(.green)
          }
        }
      }
    }
    .navigationDestination(for: TodaysRun.ID.self) { runStopID in
      RunStopDetailView(runStopID: runStopID, runID: runID)
    }
    .alert("Couldn't update the run", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorMessage) }
  }

  private func toggle(_ stop: RunStopSummary) {
    do {
      try RunOperations.setRunStopDone(stop.runStopID, done: !stop.isDone, in: database)
      sendChanges(reason: "stop checked off")
    } catch { show(error) }
  }

  private func bulk(_ stop: RunStopSummary) {
    do {
      try RunOperations.bulkCheckOff(throughRunStop: stop.runStopID, runID: runID, in: database)
      sendChanges(reason: "bulk check-off")
    } catch { show(error) }
  }

  private func sendChanges(reason: String) {
    Task { await RouteySyncing.sendChanges(reason: reason, using: syncEngine) }
  }

  private func show(_ error: any Error) {
    errorMessage = error.localizedDescription
    isShowingError = true
  }
}
```

(Note: `RunStopSummary.id` and the `NavigationLink(value:)` both key on `runStopID` — a `UUID`/`TodaysRun.ID`. `TodaysRun.ID` is `UUID`, so `RunStop.ID` is also `UUID`; the `navigationDestination(for: TodaysRun.ID.self)` matches because both are `UUID`. If the compiler needs a distinct type, wrap the id in a small `Hashable` `RunStopRoute` struct — but `UUID` is the simplest match.)

- [ ] **Step 2: Make the row's ○ and body interactive.** Replace `RunStopRowView.swift`:

```swift
import RouteyDomain
import SwiftUI

struct RunStopRowView: View {
  let stop: RunStopSummary
  let onToggle: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onToggle) {
        Image(systemName: stop.isDone ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(stop.isDone ? .green : .secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(stop.isDone ? "Mark not done" : "Mark done")

      VStack(alignment: .leading) {
        Text(stop.tieOut.isEmpty ? stop.displayName : stop.tieOut)
        if !stop.displayName.isEmpty && !stop.tieOut.isEmpty {
          Text(stop.displayName).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
      if stop.hasWarning {
        Image(systemName: "dog").foregroundStyle(.orange)
      }
      if stop.parcelCount > 0 {
        Label("\(stop.parcelCount)", systemImage: "shippingbox.fill")
          .labelStyle(.titleAndIcon).font(.caption)
      }
    }
    .opacity(stop.isDone ? 0.5 : 1)
  }
}
```

(The `.buttonStyle(.plain)` on the ○ keeps the surrounding `NavigationLink` tappable while the ○ handles its own tap.)

- [ ] **Step 3: Create `RunStopDetailView`.**

```swift
// app/Routey/Routey/Run/RunStopDetailView.swift
import RouteyDomain
import RouteyModel
import SQLiteData
import SwiftUI

struct RunStopDetailView: View {
  @Fetch private var detail: RunStopDetail

  init(runStopID: RunStop.ID, runID: TodaysRun.ID) {
    _detail = Fetch(wrappedValue: RunStopDetail.empty, RunStopDetailRequest(runStopID: runStopID, runID: runID))
  }

  var body: some View {
    List {
      if !detail.warningTags.isEmpty {
        Section("Warnings") {
          ForEach(detail.warningTags, id: \.self) { tag in
            Label(tag, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
          }
        }
      }
      Section("Addresses") {
        ForEach(detail.addresses) { address in
          VStack(alignment: .leading) {
            Text("\(address.civic) \(address.street)".trimmingCharacters(in: .whitespaces))
            if let occupant = address.occupant {
              Text(occupant).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      if !detail.parcels.isEmpty {
        Section("Parcels") {
          ForEach(detail.parcels) { parcel in
            HStack {
              VStack(alignment: .leading) {
                Text(parcel.labelSnapshot.isEmpty ? parcel.trackingCode : parcel.labelSnapshot)
                if !parcel.trackingCode.isEmpty {
                  Text(parcel.trackingCode).font(.caption).foregroundStyle(.secondary)
                }
              }
              Spacer()
              if parcel.requiresSignature { Image(systemName: "signature") }
              if parcel.isCustoms { Image(systemName: "doc.text") }
            }
          }
        }
      }
    }
    .navigationTitle("Stop")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct RunStopDetailRequest: FetchKeyRequest {
  let runStopID: RunStop.ID
  let runID: TodaysRun.ID
  func fetch(_ db: Database) throws -> RunStopDetail {
    try RunStopDetail.load(runStopID: runStopID, runID: runID, db)
  }
}
```

- [ ] **Step 4: Build to verify**

Run: `"$HOME/.claude/bin/xcode-build-gate.sh" --wait && xcodebuild -project app/Routey/Routey.xcodeproj -scheme Routey -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: On-device / Simulator manual check** (record in the PR description):
  - Open the app → Run tab shows today's run; tap a ○ → it fills green, progress increments; tap again → reverts.
  - Swipe a row → "Done through here" marks it and every stop above it done.
  - Tap a row body → the stop detail shows its addresses, parcels, and any warning tags.

- [ ] **Step 6: Commit**

```bash
git add app/Routey/Routey/Run
git commit -m "$(cat <<'EOF'
feat(app): add Today's Run check-off, bulk check-off, and stop detail

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Drag reorder

**Files:**
- Modify: `app/Routey/Routey/Run/RunBoardView.swift` (add `.onMove`)

**Interfaces:**
- Consumes: `RunOperations.moveRunStop` (RouteyDomain).
- Produces: drag-to-reorder on the run stop list.

**Gesture-layering note:** this row already carries a tap target (○), a `NavigationLink`, and a `.swipeActions`. `.onMove` adds long-press drag. Validate the interplay early — if the SDK requires an explicit edit affordance for `.onMove`, add an `EditButton()` to the toolbar rather than fighting the gesture system. Consult the project's SwiftUI guidance (axiom-swiftui) on `List` reorder + swipe coexistence before finalizing.

- [ ] **Step 1: Add `.onMove` to the `ForEach` in `RunBoardView` and the move handler.** Change the `ForEach(board.stops) { … }` block to attach `.onMove`, and add the handler. The move translates SwiftUI's `(IndexSet, Int)` offsets into `moveRunStop(_ movedID, after: precedingID)`:

```swift
        ForEach(board.stops) { stop in
          NavigationLink(value: stop.runStopID) {
            RunStopRowView(stop: stop) { toggle(stop) }
          }
          .swipeActions(edge: .trailing) {
            Button("Done through here", systemImage: "checkmark.circle") { bulk(stop) }
              .tint(.green)
          }
        }
        .onMove(perform: move)
```

Add this method to `RunBoardView`:

```swift
  private func move(from offsets: IndexSet, to destination: Int) {
    guard let source = offsets.first else { return }
    let moved = board.stops[source]
    // Compute the stop the moved row should follow at its new position.
    var order = board.stops
    order.move(fromOffsets: offsets, toOffset: destination)
    guard let newIndex = order.firstIndex(where: { $0.runStopID == moved.runStopID }) else { return }
    let precedingID = newIndex > 0 ? order[newIndex - 1].runStopID : nil
    do {
      try RunOperations.moveRunStop(moved.runStopID, after: precedingID, in: database)
      sendChanges(reason: "stop reordered")
    } catch { show(error) }
  }
```

- [ ] **Step 2: Build to verify**

Run: `"$HOME/.claude/bin/xcode-build-gate.sh" --wait && xcodebuild -project app/Routey/Routey.xcodeproj -scheme Routey -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: On-device / Simulator manual check** (record in the PR):
  - Long-press a row and drag it to a new position → the order persists (re-open the Run tab; the new order holds).
  - Confirm tap-○, swipe "Done through here", and tap-to-open all still work after adding reorder (no gesture conflict). If drag requires an Edit affordance, an `EditButton()` was added to the toolbar — note that in the PR.

- [ ] **Step 4: Commit**

```bash
git add app/Routey/Routey/Run/RunBoardView.swift
git commit -m "$(cat <<'EOF'
feat(app): add drag reorder to Today's Run

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Documentation update

**Files:**
- Modify: `docs/superpowers/specs/2026-06-22-routey-design.md` (§6 note)
- Modify: `docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md` (M5 status)

- [ ] **Step 1: Update the master spec.** In `2026-06-22-routey-design.md`, add a dated note in/near §6 ("On route — Deliver") recording: the Today's Run drive-loop UI shipped as the app's TabView home (Run/Routes/Search); the run is an ordered, check-offable stop list (single + bulk check-off, drag reorder) with dog/parcel badges; it's backed by the pure `RunBoard`/`RunStopDetail` read-model loaders surfaced live via `@Fetch`; proof-of-delivery, plan-view filters, and follow-up tasks remain deferred.

- [ ] **Step 2: Update the roadmap.** In `2026-06-25-routey-roadmap-execution.md`, mark the M5 Today's Run *UI drive-loop* as implemented (referencing `docs/superpowers/plans/2026-06-29-todays-run-ui.md`), noting the deferred sub-slices.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-06-22-routey-design.md docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md
git commit -m "$(cat <<'EOF'
docs: record Today's Run drive-loop UI as-built

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**1. Spec coverage** (against `2026-06-29-todays-run-ui-design.md`):
- §2 TabView (Run/Routes/Search) → Task 4. ✓
- §2 ordered stop list + dog/parcel badges → Tasks 2 (data) + 4 (UI). ✓
- §2 single check-off (`setRunStopDone`) → Tasks 1 + 5. ✓
- §2 bulk "Done through here" → Task 5 (reuses `bulkCheckOff`). ✓
- §2 open stop (addresses/parcels/tags, informational) → Tasks 3 + 5. ✓
- §2 drag reorder → Task 6 (reuses `moveRunStop`). ✓
- §2 header progress + signature count → Tasks 2 + 4. ✓
- §3 sync lifecycle hoisted to TabView root → Task 4 Step 2. ✓
- §4 `RunBoard`/`RunStopDetail` pure loaders + `setRunStopDone` → Tasks 1–3. ✓
- §5 live binding via `@Fetch`/`FetchKeyRequest` → Task 4 (`RunBoardRequest`) + Task 5 (`RunStopDetailRequest`). ✓
- §7 idempotent generate on appear → Task 4 (`RunView.task`). ✓
- §8 empty states (no route / no stops) → Task 4. ✓
- §9 Mac-testable loaders + ops → Tasks 1–3; device feel → Tasks 5–6. ✓
- §10 docs → Task 7. ✓

**2. Placeholder scan:** No "TBD"/"handle errors"/"similar to" — every code step is complete. The two acknowledged build-time validations (`@Fetch`/`Tab` exact initializers in Task 4 Step 7; `.onMove`+swipe coexistence in Task 6) are explicit, bounded checks with named fallbacks, not placeholders.

**3. Type consistency:** loaders take `_ db: Database` and are called identically from tests (`database.read { db in … }`) and from `FetchKeyRequest.fetch(_ db:)`; `RunGeneration.generate` uses `into:` while every `RunOperations.*` (incl. the new `setRunStopDone`) uses `in:`; `RunStopSummary.id == runStopID` keys both `ForEach` and the `NavigationLink`; `bulkCheckOff(throughRunStop:runID:in:)` and `moveRunStop(_:after:in:)` are called with their exact labels; warning = `Tag.isWarning`. ✓
