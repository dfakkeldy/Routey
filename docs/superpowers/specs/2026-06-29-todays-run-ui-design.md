# Today's Run UI — Design Spec

- **Date:** 2026-06-29
- **Status:** Initial drive-loop UI implemented 2026-06-30; follow-up delivery features remain deferred
- **Relates to:** Master design spec `docs/superpowers/specs/2026-06-22-routey-design.md` §4, §5 (daily entities), §6 ("On route — Deliver"); roadmap milestone M5 (Today's Run — domain done, UI deferred).
- **Branch:** Implemented on `codex/todays-run-ui` off `nightly`; originally designed on the stale `claude/todays-run-ui` branch and reconciled after Snap-to-Add landed.

## 1. Goal

Build the **visible** Today's Run drive loop: open today's run for the route, see the
stops in delivery order with what's waiting at each (parcels, dog/warning flags), check
them off as you deliver, and track progress — the core *sort → deliver* experience in the
truck. The run domain (`RunGeneration`, `RunOperations`, the run/parcel/record models) is
already built and tested in `RouteyDomain`/`RouteyModel`; this slice builds the read-model
projection, the navigation home, and the Run screen, and wires them to the existing domain.

Guiding rule (master spec): *if it doesn't save time in the truck, it doesn't ship.*

## 2. Scope

**In scope**
- A **TabView** app shell — **Run** (default), **Routes**, **Search** — making Today's Run
  the app's home.
- A Run screen that opens/generates today's run for the route and shows an **ordered stop
  list**: each row shows the tie-out + nickname, a **dog/warning flag**, and a **parcel-count
  badge**.
- **Single check-off** (tap the leading ○ → ✓) via a new `RunOperations.setRunStopDone`.
- **Bulk check-off** ("Done through here") via a row swipe action, using the existing
  `RunOperations.bulkCheckOff`.
- **Open a stop** (tap the row body) to a detail screen showing the stop's addresses,
  parcels (with signature/customs flags), and warning tag names — *informational only*.
- **Drag reorder** of stops via the existing `RunOperations.moveRunStop`.
- A header with **progress (done/total)** and the **signatures-to-collect count**.
- Two pure, Mac-testable read-model loaders in `RouteyDomain` (`RunBoard`, `RunStopDetail`).

**Out of scope (YAGNI / later slices)**
- Proof-of-delivery / outcome logging (the `DeliveryRecord` + `RunOperations.logDelivery`
  UI) — opening a stop is informational here; you check off whole stops, not parcels.
- Plan-view filters (full route / no-flyers+parcels / today's parcels / signatures).
- Follow-up-task UI.
- Multi-route selection (V1 has effectively one route — the Run tab uses the first route,
  same assumption as Snap-to-Add).
- Nightly history archiving (a separate concern).

## 3. Navigation restructure (TabView)

`ContentView` becomes a `TabView` using the modern `Tab` API (per AGENTS.md, not
`tabItem()`), with three tabs:

| Tab | Content | Notes |
| --- | --- | --- |
| **Run** (default) | `RunView` — today's run for the first route | Snap is a camera button in this tab's toolbar |
| **Routes** | `RoutesView` — the current route-list `NavigationStack`, moved verbatim out of `ContentView` | Import lives here |
| **Search** | `SearchView` — unchanged | |

The app's **sync lifecycle** (`.task` synchronize on appear + the `scenePhase` push/pull
handlers) moves to the **TabView root** so it runs regardless of the active tab.

> **Merge coordination:** this reworks `ContentView`, which the open Snap-to-Add PR (#23)
> also modified (it added the Snap toolbar button + the `.fullScreenCover`). Both branch
> from the same `nightly`. Whichever merges first, the other rebases and reconciles: the
> Snap entry point becomes the camera button on the Run tab. This is a deliberate, expected
> reconciliation, not an unforeseen conflict.

## 4. Read-model in `RouteyDomain` (the testable core)

A `RunStop` only snapshots its own label (`tieOut`/`displayName`/`kind`), so "what's at this
stop" is a **derived join** across the master graph
(`RunStop.stopID → Stop → DeliveryPoint → Address → {AddressTag → Tag, Parcel}`). Rather
than fan `@FetchAll`s out in the view, the assembly lives in two **pure loaders** in
`RouteyDomain`, each a function over an injected `DatabaseReader`:

- `RunBoard.load(runID:, from: DatabaseReader) throws -> RunBoard`
  - `RunBoard = { total: Int, doneCount: Int, signatureCount: Int, stops: [RunStopSummary] }`
  - `RunStopSummary = { runStopID, stopID, tieOut, displayName, kind, isDone, sortIndex, hasWarning: Bool, parcelCount: Int }`, ordered by `sortIndex`.
  - `hasWarning` = the stop's addresses have any warning-class tag (e.g. dog / scary-dog).
  - `parcelCount` = today's-run parcels whose `addressID` is among the stop's addresses.
  - `signatureCount` reuses the existing `RunOperations.signatureCount` semantics.
- `RunStopDetail.load(runStopID:, runID:, from: DatabaseReader) throws -> RunStopDetail`
  - `RunStopDetail = { addresses: [AddressLine], parcels: [ParcelLine], warningTags: [String] }`
  - `AddressLine` = civic/range + street + occupant; `ParcelLine` = label snapshot + tracking + signature/customs flags.

One new write op: **`RunOperations.setRunStopDone(_ id: RunStop.ID, done: Bool, in: DatabaseWriter)`**
(single-stop toggle — the domain has `bulkCheckOff` but no single setter). Everything else
reuses tested ops: `RunGeneration.generate`, `RunOperations.bulkCheckOff`,
`RunOperations.moveRunStop`, `RunOperations.signatureCount`.

The loaders are value-type `Sendable` results, no UI, no I/O beyond the reader — the
highest-value `swift test` targets of this slice.

## 5. Live binding

The Run screen surfaces `RunBoard` as a **live, observed query** so check-off, reorder, and
newly-snapped parcels update immediately — backed by the pure `RunBoard.load` loader (which
stays directly unit-testable). The exact SQLiteData observed-query mechanism
(`@Fetch`/`FetchKeyRequest` vs a `.task`-driven re-run on the run's tables) is confirmed
against the SQLiteData docs at plan time; this spec stays at "observed read-model backed by
`RunBoard.load`."

## 6. The Run screen

```
RunView (Run tab)
  ├─ header: "Today's Run — <doneCount>/<total> · <signatureCount> signatures"  [📷 Snap]
  └─ List of RunStopRowView, ordered by sortIndex:
       ┌─────────────────────────────────────────────┐
       │ ○  101-115  Maple cluster              📦 2  │  ← tap ○ = setRunStopDone
       │ ✓  120      Birch Rd                         │  ← tap body = push RunStopDetailView
       │ ○  124      Birch Rd        🐶          📦 1  │
       └─────────────────────────────────────────────┘
       swipe a row → "Done through here" (bulkCheckOff)
       drag (ForEach.onMove) → moveRunStop
  RunStopDetailView (pushed): addresses · parcels (sig/customs) · warning tags — read-only
```

- `RunStopRowView`: a leading `○`/`✓` `Button` (`setRunStopDone`), a row-body `Button`
  (push detail), trailing `🐶` + `📦 N` badges. Declarative; logic delegates to
  `RouteyDomain` ops.
- `.swipeActions` → "Done through here" (`bulkCheckOff(throughRunStop:)`).
- `ForEach(stops).onMove` → `moveRunStop(_:after:)`.
- Done rows are visually de-emphasized (e.g. dimmed) but remain visible and re-openable.

> **Gesture-layering risk (validate early at plan time, axiom-swiftui):** tap targets +
> `.swipeActions` + `.onMove` on the same `List` row is supported but needs care. Prove the
> gesture interplay on a small harness before building the full row.

## 7. Interactions → domain ops

| Interaction | Op |
| --- | --- |
| Open Run tab | `RunGeneration.generate(routeID:serviceDate:now:into:)` (idempotent; today's `serviceDate`) |
| Tap ○ / ✓ | `RunOperations.setRunStopDone(_:done:in:)` |
| Swipe → "Done through here" | `RunOperations.bulkCheckOff(throughRunStop:runID:in:)` |
| Drag reorder | `RunOperations.moveRunStop(_:after:in:)` |
| Open a stop | `RunStopDetail.load(runStopID:runID:from:)` |

Each write is followed by the app's `RouteySyncing.sendChanges` idiom (fire-and-forget;
never blocks the UI).

## 8. Error & empty states (offline-first)

- **No route** → "Import a route" empty state on the Run tab (route import lives on the
  Routes tab).
- **Route present, run not yet generated** → generate on appear (idempotent), then show the
  board.
- **Run with zero stops** → "No stops yet" empty state.
- Local SQLite is the source of truth; sync is a quiet background layer. The screen never
  blocks or spins on a data op.

## 9. Testing

- **Mac-testable (`swift test`, no simulator):**
  - `RunBoard.load` against an in-memory DB seeded with a representative stop graph (a
    shared box serving multiple addresses, a CMB site with modules, a dog-tagged address,
    parcels on some addresses) — assert `total`/`doneCount`/`signatureCount`, per-stop
    `hasWarning`/`parcelCount`, and `sortIndex` ordering.
  - `RunStopDetail.load` — assert addresses, parcels (with flags), and warning tag names.
  - `RunOperations.setRunStopDone` — toggles `isDone`, reflected in a subsequent
    `RunBoard.load`.
- **App (build + on-device feel):** build-verified; a device pass for the gesture layering
  (tap/swipe/drag) and the check-off feel, since that's not exercisable in `swift test`.

## 10. Documentation follow-ups

When this lands, update:
- Master design spec `docs/superpowers/specs/2026-06-22-routey-design.md` §6 — note the
  Today's Run drive-loop UI shipped, the TabView home, and the `RunBoard` read-model.
- Roadmap `docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md` — mark the M5
  Today's Run UI drive-loop as implemented (proof-of-delivery, filters, follow-ups still
  deferred).

**As-built 2026-06-30:** Completed in `codex/todays-run-ui`. The app now opens to
a Run/Routes/Search TabView, generates today's run for the first route, observes
`RunBoard` via SQLiteData `@Fetch`, supports single check-off, "Done through
here", read-only `RunStopDetailView`, and drag reorder. Snap-to-Add is in the
Run tab toolbar. Proof-of-delivery/outcome logging UI, filters, follow-up task
UI, and the broader device gesture pass are still follow-up work.

## 11. Carrier-agnostic guarantee

All seed data, fixtures, and sample copy use invented placeholders only (no employer name,
real street/site names, or civic numbers), per the public-repo rule in CLAUDE.md / AGENTS.md.
