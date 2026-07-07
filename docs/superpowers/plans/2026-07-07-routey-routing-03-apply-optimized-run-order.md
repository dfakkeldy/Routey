# Routey Routing Plan 3: Apply Optimized Run Order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Routey suggest and apply an optimized order to coordinate-backed parcel stops in Today's Run.

**Architecture:** Keep optimization package-first and reversible. Domain code loads eligible `RunStop` rows, maps them to `RouteyNavigation.RouteStopCandidate`, and writes new `RunStop.sortIndex` values only when the user explicitly applies the suggestion.

**Tech Stack:** Swift 6, Swift Testing, SQLiteData, RouteyNavigation, SwiftUI.

## Global Constraints

- Manual reorder remains available.
- Optimization is a suggestion, not automatic.
- Stops without coordinates remain in their existing relative order and are surfaced as unresolved.
- No network calls in this plan.

---

## Learning Log From Previous Plan

- [ ] Before executing Task 1, append the final Plan 2 coordinate resolution API names and unresolved-coordinate behavior.
- [ ] Expected Plan 2 dependency: `CoordinateResolution.candidates(routeID:in:)` lists missing coordinates, and `CoordinateResolutionService.resolveMissingCoordinates(routeID:in:)` caches coordinates without requiring network at run time.

## Planned Files

- Modify: `RouteyKit/Package.swift` so `RouteyDomain` depends on `RouteyNavigation`.
- Create: `RouteyKit/Sources/RouteyDomain/RunOptimization.swift`
- Test: `RouteyKit/Tests/RouteyDomainTests/RunOptimizationTests.swift`
- Modify: `app/Routey/Routey/Run/RunBoardView.swift`

## Interfaces

```swift
public struct RunOptimizationSuggestion: Equatable, Sendable {
  public var orderedRunStopIDs: [RunStop.ID]
  public var unresolvedRunStopIDs: [RunStop.ID]
  public var totalDistance: Double
}

public enum RunOptimization {
  public static func suggest(runID: TodaysRun.ID, start: NavigationCoordinate?, in database: any DatabaseReader) throws -> RunOptimizationSuggestion
  public static func apply(_ suggestion: RunOptimizationSuggestion, to runID: TodaysRun.ID, in database: any DatabaseWriter) throws
}
```

## Tasks

### Task 1: Load Eligible Parcel Stops

- [ ] Write a failing test that seeds three run stops, parcels on two stops, coordinates on only one parcel stop, then expects one eligible ID and one unresolved ID.
- [ ] Implement `RunOptimization.suggest` candidate loading using existing query style and Swift dictionaries, not joins.
- [ ] Verify: `cd RouteyKit && swift test --filter RunOptimizationTests`.
- [ ] Commit: `feat(domain): load run optimization candidates`.

### Task 2: Generate Suggested Order

- [ ] Add a test with three coordinate-backed parcel stops where nearest-neighbor produces a different order than existing `sortIndex`.
- [ ] Call `RouteOptimizer.optimize(start:stops:)`.
- [ ] Return `orderedRunStopIDs` and `totalDistance`.
- [ ] Verify unresolved stops remain excluded from optimized IDs.
- [ ] Verify: `cd RouteyKit && swift test --filter RunOptimizationTests`.
- [ ] Commit: `feat(domain): suggest optimized run order`.

### Task 3: Apply Suggested Order

- [ ] Add a test that applies a suggestion and verifies `RunStop.sortIndex` is reassigned to `0, 1, 2...` for optimized stops.
- [ ] Keep unresolved stops after optimized parcel stops in their existing relative order.
- [ ] Implement `RunOptimization.apply`.
- [ ] Verify: `cd RouteyKit && swift test --filter RunOptimizationTests`.
- [ ] Commit: `feat(domain): apply optimized run order`.

### Task 4: Add Run UI Action

- [ ] Add an "Optimize" toolbar action to `RunBoardView`.
- [ ] Show confirmation before applying: "Use suggested order for parcel stops?"
- [ ] Show unresolved count in the confirmation.
- [ ] Apply with `RunOptimization.apply`.
- [ ] Keep drag reorder after applying.
- [ ] Verify app build through the Xcode build gate when feasible.
- [ ] Commit: `feat(app): add optimize run action`.

## Plan 3 Completion Handoff

- [ ] Update Plan 4 with the exact `RunOptimizationSuggestion` fields.
- [ ] Run `cd RouteyKit && swift test`.
- [ ] Run `git status --short --branch`.
