# Routey Routing Plan 4: Map Preview and Directions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a low-distraction map preview for Today's Run and a next-stop Apple Maps handoff.

**Architecture:** Use SwiftUI `Map` because the app target is iOS 18 and the first map view needs ordinary markers, camera control, and optional polylines. Avoid user-location permission in the first slice by showing route/run coordinates only; add live user location later when Drive Mode needs it.

**Tech Stack:** SwiftUI, MapKit, RouteyDomain.

## Global Constraints

- Do not request location authorization in this plan.
- Do not depend on MapKit directions for the offline parcel list.
- If directions fail, the map still shows markers and ordered straight-line context.
- Keep UI calm and truck-friendly.

---

## Learning Log From Previous Plan

- [x] Plan 3 landed `RunOptimizationSuggestion(orderedRunStopIDs:unresolvedRunStopIDs:totalDistance:)`, `RunOptimization.suggest(runID:start:in:)`, and `RunOptimization.apply(_:to:in:)`.
- [x] The Today's Run board now has an explicit `Optimize` toolbar action that previews/apply-confirms the optimized parcel stop order before rewriting `RunStop.sortIndex`.
- [x] Plan 4 can build map previews from cached coordinates and current run stops without changing the optimizer contract; unresolved run stops should remain visible as a count/empty state instead of blocking the map.

## Planned Files

- Create: `app/Routey/Routey/Navigation/RunMapSnapshot.swift`
- Create: `app/Routey/Routey/Navigation/RunMapView.swift`
- Create: `app/Routey/Routey/Navigation/AppleMapsHandoff.swift`
- Modify: `app/Routey/Routey/Run/RunBoardView.swift`

## Interfaces

```swift
struct RunMapStop: Identifiable, Equatable {
  var id: UUID
  var title: String
  var subtitle: String
  var order: Int
  var coordinate: CLLocationCoordinate2D
}

struct AppleMapsHandoff {
  static func openDestination(title: String, coordinate: CLLocationCoordinate2D)
}
```

## Tasks

### Task 1: Build Map Snapshot Model

- [x] Add a small app model that converts `RunOptimizationSuggestion` plus run stop detail into `[RunMapStop]`.
- [x] Keep stops without coordinates out of the map list and report their count.
- [x] Use invented preview data for SwiftUI previews if previews exist.
- [x] Commit: `feat(app): prepare run map snapshot`.

### Task 2: Add SwiftUI Map View

- [x] Create `RunMapView` using `Map(position:)`.
- [x] Render numbered markers for each coordinate-backed stop.
- [x] Render a `MapPolyline(coordinates:)` connecting stops in suggested order.
- [x] Use `.mapControls { MapCompass(); MapScaleView() }`.
- [x] Do not add `UserAnnotation()` yet.
- [x] Commit: `feat(app): add run map preview`.

### Task 3: Add Apple Maps Handoff

- [x] Implement `AppleMapsHandoff.openDestination(title:coordinate:)` using `MKMapItem`.
- [x] Add a button on selected stop or first next stop: "Open in Maps".
- [x] Use driving directions mode.
- [x] If no coordinate exists, disable the button.
- [x] Commit: `feat(app): add Apple Maps next-stop handoff`.

### Task 4: Wire From Today's Run

- [x] Add "Map" entry point from `RunBoardView`.
- [x] Pass the current run ID and load map stops from cached coordinates.
- [x] Show empty state: "Resolve coordinates to preview this run on a map."
- [x] Verify with app build through the Xcode build gate when feasible.
- [x] Commit: `feat(app): wire map preview into run board`.

## Plan 4 Completion Handoff

- [x] Update Plan 5 with any map model or UI conventions that should be reused for temporary routes.
- [x] Run `git status --short --branch`.
