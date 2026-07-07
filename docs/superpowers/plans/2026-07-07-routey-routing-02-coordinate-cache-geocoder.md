# Routey Routing Plan 2: Coordinate Cache and Geocoder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve missing route/address coordinates and cache them onto existing `Stop` and `Address` fields without changing the schema.

**Architecture:** Keep caching in existing synced columns. Use a concrete closure-injected resolver for tests, and use Core Location / MapKit only in the app-facing implementation. Do not block the run UI on network results.

**Tech Stack:** Swift 6, Swift Testing, SQLiteData, Core Location, MapKit.

## Global Constraints

- No schema changes. Use existing `Stop.latitude`, `Stop.longitude`, `Address.doorLatitude`, and `Address.doorLongitude`.
- No live geocoding hundreds of addresses during drive mode. Resolve at route build, manual edit, or explicit "Resolve Coordinates" action.
- Do not require network to start or continue Today's Run.
- Keep all fixtures invented.

---

## Learning Log From Previous Plan

- [ ] Before executing Task 1, append the final Plan 1 `RouteyNavigation` public APIs and any deviations from the planned optimizer behavior.
- [ ] Expected Plan 1 dependency: `RouteStopCandidate`, `NavigationCoordinate`, `RouteOptimizationResult`, and `RouteOptimizer.optimize(start:stops:)` exist in the `RouteyNavigation` product.

## Planned Files

- Modify: `RouteyKit/Package.swift` so `RouteyDomainTests` can import `RouteyNavigation` if Plan 1 requires it.
- Create: `RouteyKit/Sources/RouteyDomain/CoordinateResolution.swift`
- Test: `RouteyKit/Tests/RouteyDomainTests/CoordinateResolutionTests.swift`
- Create: `app/Routey/Routey/Navigation/AppleAddressGeocoder.swift`
- Create: `app/Routey/Routey/Navigation/CoordinateResolutionView.swift`
- Modify: `app/Routey/Routey/Routes/RouteStopsView.swift` to expose coordinate resolution from route detail.

## Interfaces

```swift
public struct AddressResolutionCandidate: Equatable, Sendable {
  public var addressID: Address.ID
  public var stopID: Stop.ID
  public var query: String
}

public struct ResolvedCoordinate: Equatable, Sendable {
  public var latitude: Double
  public var longitude: Double
}

public struct CoordinateResolutionService: Sendable {
  public var resolve: @Sendable (String) async throws -> ResolvedCoordinate?
  public func resolveMissingCoordinates(routeID: Route.ID, in database: any DatabaseWriter) async throws -> Int
}
```

## Tasks

### Task 1: Domain Candidate Builder

- [ ] Write `CoordinateResolutionTests` that seeds invented stops/addresses, one missing coordinate and one already cached coordinate, then expects only the missing address to produce a candidate query like `"101 Sample Road"`.
- [ ] Implement `CoordinateResolution.candidates(routeID:in:)`.
- [ ] Verify: `cd RouteyKit && swift test --filter CoordinateResolutionTests`.
- [ ] Commit: `feat(domain): list missing coordinate candidates`.

### Task 2: Cache Resolved Coordinates

- [ ] Add a failing test with a fake `CoordinateResolutionService(resolve:)` closure that returns `ResolvedCoordinate(latitude: 45.1, longitude: -63.2)`.
- [ ] Implement `resolveMissingCoordinates(routeID:in:)` to update both `Address.doorLatitude/doorLongitude` and `Stop.latitude/longitude` for the candidate's stop.
- [ ] Verify the test reads the updated rows from SQLite.
- [ ] Verify: `cd RouteyKit && swift test --filter CoordinateResolutionTests`.
- [ ] Commit: `feat(domain): cache resolved route coordinates`.

### Task 3: Apple Geocoder Wrapper

- [ ] Create `AppleAddressGeocoder` in the app target.
- [ ] Use `CLGeocoder.geocodeAddressString(_:)` as the baseline because Routey targets iOS 18 while newer `MKGeocodingRequest` requires newer availability gates.
- [ ] Return the first placemark location as `ResolvedCoordinate`.
- [ ] Handle no results by returning `nil`.
- [ ] Do not call it from app launch.
- [ ] Verify with app build through the Xcode build gate when feasible.
- [ ] Commit: `feat(app): add Apple address geocoder`.

### Task 4: Route UI Entry Point

- [ ] Add a route-level "Resolve Coordinates" action in `RouteStopsView` or a small `CoordinateResolutionView`.
- [ ] Show progress count and failures without blocking other route editing.
- [ ] Make copy conservative: "Resolve Coordinates", "Some addresses could not be located", "Try again when online".
- [ ] Verify manually in simulator with invented route data.
- [ ] Commit: `feat(app): add coordinate resolution action`.

## Plan 2 Completion Handoff

- [ ] Update Plan 3 with the concrete coordinate-cache APIs and any discovered MapKit/Core Location limitations.
- [ ] Run `cd RouteyKit && swift test`.
- [ ] Run `git status --short --branch`.
