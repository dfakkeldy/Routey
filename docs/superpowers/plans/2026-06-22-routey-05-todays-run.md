# Routey Plan 05 — Today's Run & Delivery

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The in-the-truck loop — generate a reorderable **Today's Run** from the master route, load parcels (manual + OCR snap), and log deliveries with rich outcomes, follow-up tasks, and proof of delivery.

**Architecture:** New **append-only synced tables** (`todaysRuns`, `runStops`, `parcels`, `deliveryRecords`, `followUpTasks`) added in a v2 migration. `RunStop` is a *snapshot* (denormalized `tieOut`/`displayName`/`kind` copied at generation) so master-route edits don't disturb an in-progress run; its `stopID` is a soft reference. `RouteyDomain` gains run generation, reorder (gap index), parcel add, delivery logging (which spawns follow-up tasks), and bulk check-off. The app gains the Today's Run screen, the deliver flow, and the camera Snap-to-Add (using Plan 04's `SnapPipeline`).

**Tech Stack:** Swift 6, SwiftUI, SQLiteData/GRDB, Vision (via Plan 04), CoreLocation, Swift Testing.

**Depends on:** Plan 01 (model/persistence), Plan 04 (`SnapPipeline`, `LabelFlags`). UI requires the app shell (Plan 01 Task 5).

## Global Constraints

- Inherited from Plan 01: UUID PKs; **append-only synced schema** (these are NEW tables — allowed; add to the `SyncEngine` tables list); no non-PK UNIQUE; FK `ON DELETE` only CASCADE/SET NULL/SET DEFAULT; STRICT; package boundary.
- **Today's Run is single-device-per-day** (per the sync gate) — do not design for two devices editing one run concurrently.
- Reorder uses fractional `sortIndex` (gap insert), never renumbering.
- **Photos are file references**, never inline blobs — `deliveryRecords.photoPath` stores a relative filename under the app's Application Support; the file itself is not in the synced row.
- Delivery outcomes: `delivered | safedrop | mailbox | inPerson | notHomeCarded | leftAtDoor | nextDay`.

---

## File structure

```
RouteyKit/
  Package.swift                        # (no new target; extend RouteyModel/RouteyDomain)
  Sources/RouteyModel/
    Daily.swift                        # TodaysRun, RunStop, Parcel, DeliveryRecord, FollowUpTask
  Sources/RouteyPersistence/
    Schema.swift                       # + "Create v2 daily tables" migration
    AppDatabase.swift                  # + the 5 new types in the synced tables list
  Sources/RouteyDomain/
    RunGeneration.swift                # master route -> Today's Run snapshot
    RunOperations.swift                # reorder, add parcel, log delivery, follow-ups, bulk check-off
  Tests/RouteyDomainTests/
    RunGenerationTests.swift
    RunOperationsTests.swift
app/Routey/Run/
  TodaysRunView.swift                  # next stop + ordered list + filters
  DeliverView.swift                    # log outcome, photo, GPS
  SnapToAddView.swift                  # camera -> Plan 04 pipeline -> add parcel; signatures count
```

---

### Task 1: v2 daily model + migration

**Files:** `RouteyModel/Daily.swift`, `RouteyPersistence/Schema.swift` (+ migration), `RouteyPersistence/AppDatabase.swift`, `RouteyDomainTests/RunGenerationTests.swift` (schema portion).

**Interfaces (`@Table` structs, all `Identifiable, Sendable`, `id: UUID`):**
- `TodaysRun { routeID: Route.ID; serviceDate: String /*yyyy-MM-dd*/; createdAt: Date; archivedAt: Date? }`
- `RunStop { runID: TodaysRun.ID; stopID: Stop.ID?; tieOut; displayName; kind; sortIndex: Double; isDone: Bool }`
- `Parcel { runID: TodaysRun.ID; addressID: Address.ID?; source: String /*ocr|manual*/; sizeClass: String; toDoor: Bool; requiresSignature: Bool; isCustoms: Bool; isDelivered: Bool; labelSnapshot: String; trackingCode: String; trackingSymbology: String /*code128|qr|… empty if none*/ }`
- `DeliveryRecord { runID: TodaysRun.ID; addressID: Address.ID?; parcelID: Parcel.ID?; outcome: String; latitude: Double?; longitude: Double?; loggedAt: Date; photoPath: String? }`
- `FollowUpTask { runID: TodaysRun.ID; targetStopID: Stop.ID?; addressID: Address.ID?; text: String; isDone: Bool }`

**Migration `"Create v2 daily tables"`** (registered AFTER the v1 migration; never edits v1 tables). Each table: UUID PK (`ON CONFLICT REPLACE DEFAULT (uuid())`), STRICT, `runID … REFERENCES "todaysRuns"("id") ON DELETE CASCADE`, soft refs (`stopID`/`addressID`/`parcelID`/`targetStopID`) `ON DELETE SET NULL` (and nullable). `Date` columns stored per SQLiteData's default (REAL/TEXT — match the `@Table` mapping).

- [ ] **Step 1: Write failing schema test** — migrate, assert the 5 new tables exist; insert a `TodaysRun` + `RunStop` + `Parcel` + `DeliveryRecord` + `FollowUpTask`; delete the run; assert all 5 children cascade to 0.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement** `Daily.swift` structs + the v2 migration + add the 5 types to the synced tables list in `AppDatabase.swift` and to `SyncEngine(for:tables:)` (Plan 01 Task 6's call — update it).
- [ ] **Step 4:** Run — PASS.
- [ ] **Step 5:** Commit `"Add v2 daily tables (run, parcels, delivery records, tasks)"`.

---

### Task 2: Run generation (snapshot from master route)

**Files:** `RouteyDomain/RunGeneration.swift`, `RunGenerationTests.swift`.

**Interfaces:**
- `enum RunGeneration { static func generate(routeID: Route.ID, serviceDate: String, now: Date, into db: any DatabaseWriter) throws -> TodaysRun.ID }` — creates a `TodaysRun`; copies every master `Stop` (in `sortIndex` order) into a `RunStop` snapshot (denormalized `tieOut`/`displayName`/`kind`, `sortIndex` preserved, `isDone=false`, `stopID` soft-linked). Idempotent per (route, date): if a run already exists for that route+date, return it unchanged.

- [ ] **Step 1: Write failing test** — import a 3-stop route (Plan 02), generate a run for "2026-06-22", assert 3 RunStops in the same order with snapshot names; calling generate again returns the same run id and still 3 RunStops (idempotent).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement** `generate` (pass `now`/`serviceDate` in — no `Date()`-in-logic so it's testable).
- [ ] **Step 4:** Run — PASS. Commit `"Add Today's Run generation from master route"`.

---

### Task 3: Run operations — reorder, add parcel, signatures count

**Files:** `RouteyDomain/RunOperations.swift`, `RunOperationsTests.swift`.

**Interfaces:**
- `enum RunOperations`:
  - `static func moveRunStop(_ id: RunStop.ID, after: RunStop.ID?, in db:) throws` — fractional gap reindex (mirror `RouteEditing.nextIndex` from Plan 02 Task 3; reuse that helper).
  - `static func addParcel(runID:, addressID: Address.ID?, source: String, requiresSignature: Bool, isCustoms: Bool, toDoor: Bool, labelSnapshot: String, trackingCode: String, trackingSymbology: String, in db:) throws -> Parcel.ID`
  - `static func signatureCount(runID:, in db: any DatabaseReader) throws -> Int` — parcels in the run with `requiresSignature && !isDelivered`.

- [ ] **Step 1: Write failing tests** — reorder 3 run stops and assert order; add two parcels (one signature) and assert `signatureCount == 1`; mark it delivered, assert count drops to 0.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement.** Reuse the gap-index helper (extract `RouteEditing.nextIndex` to a shared `Ordering.between(...)` if cleaner — and update its callers + tests).
- [ ] **Step 4:** Run — PASS. Commit `"Add run reorder, parcel add, and signatures count"`.

---

### Task 4: Delivery logging + follow-up tasks + bulk check-off

**Files:** `RouteyDomain/RunOperations.swift` (extend), `RunOperationsTests.swift` (extend).

**Interfaces:**
- `static func logDelivery(runID:, runStopID: RunStop.ID, parcelID: Parcel.ID?, addressID: Address.ID?, outcome: String, location: (lat: Double, lon: Double)?, photoPath: String?, loggedAt: Date, in db:) throws -> DeliveryRecord.ID` — inserts a `DeliveryRecord`; if `outcome == "notHomeCarded"` and the address is served by a CMB compartment, **spawn a `FollowUpTask`** ("drop notice card in <compartment label>") targeting that CMB stop; if a `parcelID` is given, set the parcel `isDelivered = true` for terminal outcomes.
- `static func bulkCheckOff(throughRunStop id: RunStop.ID, runID:, in db:) throws` — mark every RunStop with `sortIndex <= target.sortIndex` as `isDone = true`.

- [ ] **Step 1: Write failing tests** — (a) logging `notHomeCarded` for a CMB-served address creates exactly one FollowUpTask targeting the right stop with the compartment label in its text; (b) logging `safedrop` with a parcel marks the parcel delivered and creates no task; (c) `bulkCheckOff` through the 3rd of 5 stops marks 3 done, 2 not.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement.** Determine "served by CMB compartment" via the address's delivery point (`kind == "compartment"`); compose the task text from `module.name` + `deliveryPoint.label`.
- [ ] **Step 4:** Run — PASS. `swift test` (all). Commit `"Add delivery logging, follow-up tasks, bulk check-off"`.

---

### Task 5: Today's Run screen + filters (UI)

> Requires app shell.

**Files:** `app/Routey/Run/TodaysRunView.swift`.

- [ ] **Step 1:** Show **Next stop** prominently (first not-`isDone` RunStop) with a **dog/scary-dog warning banner** if that stop's address carries a warning tag; below it the ordered RunStop list with progress ("42 / 117"). A **filter** control: full route / no-flyers + parcels / today's parcels / signatures (the signatures filter shows the running `signatureCount`). Drag-to-reorder calls `RunOperations.moveRunStop`. Tap the last stop → confirm → `bulkCheckOff`.
- [ ] **Step 2:** Run in simulator on a generated run; verify next-stop, warning banner, filters, reorder, bulk check-off.
- [ ] **Step 3:** Commit `"Add Today's Run screen with filters, reorder, bulk check-off"`.

---

### Task 6: Deliver flow (UI) — outcome + GPS + photo

> Requires app shell.

**Files:** `app/Routey/Run/DeliverView.swift`.

- [ ] **Step 1:** From a RunStop, present outcome buttons (the 7 outcomes); on tap, capture `CLLocation` (one-shot, non-blocking — log without GPS if unavailable), optionally a photo (saved to Application Support, store the relative path), then call `RunOperations.logDelivery`. Surface any spawned follow-up task (e.g. a toast "Card to drop at Cornerstore M2-C7"). Follow-up tasks appear on their target stop in the run list.
- [ ] **Step 2:** Run in simulator (simulate a location); verify a record is written, a photo path is saved, and a `notHomeCarded` on a CMB address surfaces the follow-up.
- [ ] **Step 3:** Commit `"Add deliver flow (outcome, GPS, photo, follow-up surfacing)"`.

---

### Task 7: Snap-to-Add (UI) — camera → match → parcel

> Requires app shell + Plan 04 (`SnapPipeline`).

**Files:** `app/Routey/Run/SnapToAddView.swift`.

- [ ] **Step 1:** Camera capture (AVFoundation or `PhotosPicker` fallback) → `SnapPipeline.process` → handle the band: **auto-accept** adds the parcel (with detected `requiresSignature`/`isCustoms` flags) to Today's Run with an undoable toast; **disambiguate** shows the ranked short-list (raw OCR + differing field highlighted) to pick; **manual** drops into predictive search (Plan 03). **Capture the tracking code** when adding the parcel: prefer the scanned barcode (`readout.barcodes.first` + its symbology), else the OCR'd code, else a manual-entry field; store as `trackingCode`/`trackingSymbology`. Show the running **"Today: N signatures"** count, updating as flagged parcels are added.
- [ ] **Step 2:** Run on device (camera) or simulator (photo fixture); snap a few labels, confirm parcels land on the right stops in delivery order and signatures count rises.
- [ ] **Step 3:** Commit `"Add Snap-to-Add camera flow with signatures count"`.

---

### Task 8: Scannable barcode re-display (Day-1 must-have)

**Why:** the carrier captures a parcel's tracking code once in the morning (Task 7), then must
re-enter it into the official scanner — at sorting and again at the door. Routey instead
re-displays the captured code as a crisp barcode the scanner reads directly.

**Files:** `RouteyKit/Sources/RouteyDomain/BarcodeGenerator.swift`, `RouteyDomainTests/BarcodeGeneratorTests.swift`, `app/Routey/Run/BarcodeView.swift`.

**Interfaces:**
- `enum BarcodeGenerator { static func image(for code: String, symbology: String, scale: CGFloat = 10) -> CGImage? }` — CoreImage: `symbology == "qr"` → `CIFilter.qrCodeGenerator()`, otherwise `CIFilter.code128BarcodeGenerator()` (the safe default most scanners read); returns `nil` for an empty code; scales up (nearest-neighbor) for a sharp, large image.

- [ ] **Step 1: Write failing tests** (headless — CoreImage works on macOS):
  - `image(for: "1Z999AA10123456784", symbology: "code128")` returns a non-nil `CGImage` with width > 0.
  - `image(for: "https://x", symbology: "qr")` returns non-nil.
  - `image(for: "", symbology: "code128")` returns nil.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement** `BarcodeGenerator` (CoreImage `CIContext().createCGImage`; apply a `CGAffineTransform` scale; fall back to Code128 for unknown symbologies).
- [ ] **Step 4:** Run — PASS. `swift test` (all). Commit `"Add barcode generator (Code128/QR) for scannable re-display"`.
- [ ] **Step 5 (UI):** `BarcodeView(code:symbology:)` — renders the barcode large, **black on a white background**, with the human-readable code beneath. On appear: save `UIScreen.main.brightness`, set it to `1.0`, and set `UIApplication.shared.isIdleTimerDisabled = true`; restore both on disappear. Reachable from a parcel in Today's Run and from the deliver flow (Task 6). A manual **edit-code** field lets the carrier fix a mis-captured code before showing it.
- [ ] **Step 6:** Run in simulator/device; show a barcode and confirm it scans (validate against the real scanner on device). Commit `"Add bright scannable barcode display with manual code edit"`.

---

## Plan self-review

- **Spec coverage:** Today's Run snapshot + idempotent generation ✓ (T2), reorder ✓ (T3), rich outcomes ✓ (T4), cross-stop follow-up tasks ✓ (T4), bulk check-off ✓ (T4), proof of delivery (GPS+timestamp+photo file ref) ✓ (T1/T6), signatures count ✓ (T3/T7), Snap-to-Add via Plan 04 ✓ (T7), **tracking-code capture + scannable barcode re-display** ✓ (T1 model fields, T7 capture, T8 generator+bright display), dog warnings on next stop ✓ (T5), filters incl. no-flyers+parcels ✓ (T5). Archival to History is Plan 06.
- **Placeholders:** none in headless tasks (1–4); UI tasks (5–7) specify exact behavior + the domain calls they make.
- **Type consistency:** the 5 model types (T1) are used verbatim in generation (T2) and operations (T3/T4); outcome string set is fixed; `signatureCount`/`logDelivery`/`bulkCheckOff`/`moveRunStop` signatures are reused by the UI.
- **Append-only honesty:** these are NEW tables added in a v2 migration; the v1 tables are untouched; the new types are added to the SyncEngine list.
- **Single-device honesty:** the run is single-device-per-day by design; no concurrent-run-edit merge logic is attempted (matches the sync-gate decision).
