# Routey Routing Plan 5: Snap Temporary Route Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user start from a pile of parcels, snap labels, and build a temporary parcel-only route when no master route exists or no match is accepted.

**Architecture:** Add a domain service that creates a temporary route, draft stop, delivery point, address, today's run, and parcel from OCR components. Reuse Snap-to-Add pipeline and existing run UI instead of creating a separate product surface.

**Tech Stack:** Swift 6, Swift Testing, SQLiteData, RouteyOCR, RouteyDomain, SwiftUI.

## Global Constraints

- Temporary routes use invented/internal naming only, such as "Parcel Pile".
- Store raw OCR text and preserve uncertainty.
- Do not require geocoding to create the temporary route.
- Do not commit real parcel labels or addresses.
- Network failure cannot block parcel capture.

---

## Learning Log From Previous Plan

- [x] Plan 4 landed an app-local `RunMapSnapshot` that builds map stops from cached coordinates plus `RunOptimizationSuggestion`, keeping unresolved parcel stops as a count rather than blocking preview.
- [x] `RunMapView` is reached from the Today's Run toolbar with numbered annotations, a straight-line `MapPolyline`, compass/scale controls, and no user-location authorization request.
- [x] `AppleMapsHandoff.openDestination(title:coordinate:)` opens the selected or first mapped stop in Apple Maps driving mode; Routey still owns offline ordering and does not depend on directions for the parcel list.
- [x] Plan 5 temporary stops should populate the same route/run/stop/address tables so coordinate resolution, optimization, map preview, and Apple Maps handoff work without a separate temporary-map path.

## Planned Files

- Create: `RouteyKit/Sources/RouteyDomain/TemporaryRouteBuilder.swift`
- Test: `RouteyKit/Tests/RouteyDomainTests/TemporaryRouteBuilderTests.swift`
- Modify: `app/Routey/Routey/Snap/SnapViewModel.swift`
- Modify: `app/Routey/Routey/Run/RunView.swift`
- Modify: `app/Routey/Routey/Routes/RoutesView.swift`

## Interfaces

```swift
public struct TemporaryParcelInput: Equatable, Sendable {
  public var serviceDate: String
  public var labelSnapshot: String
  public var civicNumber: Int?
  public var street: String
  public var postalCode: String?
  public var trackingCode: String
  public var trackingSymbology: String
  public var requiresSignature: Bool
  public var isCustoms: Bool
  public var toDoor: Bool
}

public enum TemporaryRouteBuilder {
  public static func addParcelToTemporaryRoute(_ input: TemporaryParcelInput, into database: any DatabaseWriter) throws -> TodaysRun.ID
}
```

## Tasks

### Task 1: Create Temporary Route Domain Service

- [x] Write a failing test that calls `TemporaryRouteBuilder.addParcelToTemporaryRoute` in an empty database.
- [x] Expect one route named `"Parcel Pile"`, one stop, one address, one delivery point, one run, and one parcel.
- [x] Implement minimal domain service.
- [x] Verify: `cd RouteyKit && swift test --filter TemporaryRouteBuilderTests`.
- [x] Commit: `feat(domain): create temporary route from parcel`.

### Task 2: Reuse Existing Temporary Route

- [x] Add a test that calls the builder twice for the same service date.
- [x] Expect one route, one run, two stops, and two parcels.
- [x] Append new stops with increasing `sortIndex`.
- [x] Verify: `cd RouteyKit && swift test --filter TemporaryRouteBuilderTests`.
- [x] Commit: `feat(domain): append parcels to temporary route`.

### Task 3: Integrate Snap Fallback

- [x] Extend `SnapViewModel.accept(addressID:)` so when `addressID == nil` and the user chooses "Add as temporary stop", it calls `TemporaryRouteBuilder`.
- [x] Keep the existing matched-address path unchanged.
- [x] Show copy: "Added to Parcel Pile" and "You can sort this run before leaving."
- [x] Verify with existing OCR tests and app build.
- [x] Commit: `feat(app): add snap fallback to temporary route`.

### Task 4: Add Quick Pile Entry Point

- [x] Add an entry point from `RunView` when there are no routes: "Start Parcel Pile".
- [x] Present Snap flow without requiring a selected master route.
- [x] After first capture, navigate to Today's Run for the temporary route.
- [x] Verify with invented label fixture coverage in `TemporaryRouteBuilderTests` plus app build.
- [x] Commit: `feat(app): add parcel pile entry point`.

### Task 5: Final Verification

- [x] Run `cd RouteyKit && swift test`.
- [x] Run `git diff --check`.
- [x] Build app through the Xcode build gate when feasible.
- [x] Review public strings for carrier-agnostic wording.
- [x] Commit any final polish.

## Plan 5 Completion Handoff

- [ ] Push the branch.
- [ ] Open PR to `nightly`.
- [ ] Check hosted `Build gate + tests`.
- [ ] File a KB status note if the workflow materially changes Routey's product direction or release plan.
