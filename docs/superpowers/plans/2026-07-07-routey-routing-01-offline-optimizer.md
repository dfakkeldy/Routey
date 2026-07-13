# Routey Routing Plan 1: Offline Optimizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pure Swift `RouteyNavigation` package target that orders coordinate-backed stops offline.

**Architecture:** Keep optimization independent of SQLiteData and MapKit. Use Sendable value types, Haversine distance, nearest-neighbor construction, and 2-opt improvement so later plans can use it from both package and app code.

**Tech Stack:** Swift 6, Swift Testing, SwiftPM, Foundation.

## Global Constraints

- No third-party dependencies.
- No schema changes.
- No MapKit in this plan.
- Keep all fixtures invented and carrier-agnostic.
- Run `cd RouteyKit && swift test --filter RouteOptimizerTests`.

---

## Learning Log From Previous Plan

This is Plan 1. No previous-plan lessons apply.

## File Structure

- Modify: `RouteyKit/Package.swift` to add product `RouteyNavigation`, target `RouteyNavigation`, and test target `RouteyNavigationTests`.
- Create: `RouteyKit/Sources/RouteyNavigation/NavigationCoordinate.swift` for latitude/longitude and distance math.
- Create: `RouteyKit/Sources/RouteyNavigation/RouteStopCandidate.swift` for optimizer input.
- Create: `RouteyKit/Sources/RouteyNavigation/RouteOptimizationResult.swift` for optimizer output.
- Create: `RouteyKit/Sources/RouteyNavigation/RouteOptimizer.swift` for nearest-neighbor and 2-opt.
- Create: `RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift` for route-order tests.

### Task 1: Add Package Target

**Files:**
- Modify: `RouteyKit/Package.swift`
- Create: `RouteyKit/Sources/RouteyNavigation/NavigationCoordinate.swift`
- Create: `RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift`

**Interfaces:**
- Produces package product `RouteyNavigation`.

- [ ] **Step 1: Modify package manifest**

Add to `products`:

```swift
.library(name: "RouteyNavigation", targets: ["RouteyNavigation"]),
```

Add to `targets` before tests:

```swift
.target(name: "RouteyNavigation"),
```

Add to test targets:

```swift
.testTarget(
  name: "RouteyNavigationTests",
  dependencies: ["RouteyNavigation"]
),
```

- [ ] **Step 2: Add anchor source**

Create `RouteyKit/Sources/RouteyNavigation/NavigationCoordinate.swift`:

```swift
import Foundation

public struct NavigationCoordinate: Equatable, Sendable {
  public var latitude: Double
  public var longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
}
```

- [ ] **Step 3: Add target smoke test**

Create `RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift`:

```swift
import Testing
@testable import RouteyNavigation

@Suite struct RouteOptimizerTests {
  @Test func coordinateStoresLatitudeAndLongitude() {
    let coordinate = NavigationCoordinate(latitude: 45.1, longitude: -63.2)
    #expect(coordinate.latitude == 45.1)
    #expect(coordinate.longitude == -63.2)
  }
}
```

- [ ] **Step 4: Run test**

Run: `cd RouteyKit && swift test --filter RouteOptimizerTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Package.swift RouteyKit/Sources/RouteyNavigation RouteyKit/Tests/RouteyNavigationTests
git commit -m "feat(navigation): add RouteyNavigation package target"
```

### Task 2: Add Distance Math

**Files:**
- Modify: `RouteyKit/Sources/RouteyNavigation/NavigationCoordinate.swift`
- Modify: `RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift`

**Interfaces:**
- Produces `public func distance(to other: NavigationCoordinate) -> Double` returning meters.

- [ ] **Step 1: Add failing tests**

Append these tests inside `RouteOptimizerTests`:

```swift
@Test func distanceToSelfIsZero() {
  let coordinate = NavigationCoordinate(latitude: 45.0, longitude: -63.0)
  #expect(coordinate.distance(to: coordinate) == 0)
}

@Test func distanceUsesMeters() {
  let first = NavigationCoordinate(latitude: 45.0, longitude: -63.0)
  let second = NavigationCoordinate(latitude: 45.01, longitude: -63.0)
  let distance = first.distance(to: second)
  #expect(distance > 1_100)
  #expect(distance < 1_120)
}
```

- [ ] **Step 2: Run failing test**

Run: `cd RouteyKit && swift test --filter RouteOptimizerTests`

Expected: FAIL because `distance(to:)` is undefined.

- [ ] **Step 3: Implement Haversine distance**

Replace `NavigationCoordinate.swift` with:

```swift
import Foundation

public struct NavigationCoordinate: Equatable, Sendable {
  public var latitude: Double
  public var longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }

  public func distance(to other: NavigationCoordinate) -> Double {
    guard self != other else { return 0 }

    let earthRadius = 6_371_000.0
    let lat1 = latitude.radians
    let lat2 = other.latitude.radians
    let deltaLat = (other.latitude - latitude).radians
    let deltaLon = (other.longitude - longitude).radians

    let a = sin(deltaLat / 2) * sin(deltaLat / 2)
      + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadius * c
  }
}

private extension Double {
  var radians: Double { self * .pi / 180 }
}
```

- [ ] **Step 4: Run test**

Run: `cd RouteyKit && swift test --filter RouteOptimizerTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Sources/RouteyNavigation/NavigationCoordinate.swift RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift
git commit -m "feat(navigation): add coordinate distance math"
```

### Task 3: Add Optimizer Types and Stable Empty Behavior

**Files:**
- Create: `RouteyKit/Sources/RouteyNavigation/RouteStopCandidate.swift`
- Create: `RouteyKit/Sources/RouteyNavigation/RouteOptimizationResult.swift`
- Create: `RouteyKit/Sources/RouteyNavigation/RouteOptimizer.swift`
- Modify: `RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift`

**Interfaces:**
- Produces `RouteStopCandidate`, `OptimizedStop`, `RouteOptimizationResult`, and `RouteOptimizer.optimize(start:stops:)`.

- [ ] **Step 1: Add failing tests**

Append:

```swift
@Test func optimizingNoStopsReturnsEmptyResult() {
  let result = RouteOptimizer.optimize(start: nil, stops: [])
  #expect(result.orderedStops.isEmpty)
  #expect(result.totalDistance == 0)
}

@Test func optimizingSingleStopReturnsThatStop() {
  let stopID = UUID()
  let stop = RouteStopCandidate(
    id: stopID,
    label: "Sample stop",
    coordinate: NavigationCoordinate(latitude: 45.0, longitude: -63.0),
    existingSortIndex: 7
  )

  let result = RouteOptimizer.optimize(start: nil, stops: [stop])
  #expect(result.orderedStops.map(\.candidate.id) == [stopID])
  #expect(result.orderedStops.map(\.order) == [0])
  #expect(result.totalDistance == 0)
}
```

- [ ] **Step 2: Run failing test**

Run: `cd RouteyKit && swift test --filter RouteOptimizerTests`

Expected: FAIL because optimizer types are undefined.

- [ ] **Step 3: Implement types**

Create `RouteStopCandidate.swift`:

```swift
import Foundation

public struct RouteStopCandidate: Equatable, Identifiable, Sendable {
  public var id: UUID
  public var label: String
  public var coordinate: NavigationCoordinate
  public var existingSortIndex: Double

  public init(id: UUID, label: String, coordinate: NavigationCoordinate, existingSortIndex: Double) {
    self.id = id
    self.label = label
    self.coordinate = coordinate
    self.existingSortIndex = existingSortIndex
  }
}
```

Create `RouteOptimizationResult.swift`:

```swift
import Foundation

public struct OptimizedStop: Equatable, Identifiable, Sendable {
  public var candidate: RouteStopCandidate
  public var order: Int
  public var distanceFromPrevious: Double

  public var id: UUID { candidate.id }

  public init(candidate: RouteStopCandidate, order: Int, distanceFromPrevious: Double) {
    self.candidate = candidate
    self.order = order
    self.distanceFromPrevious = distanceFromPrevious
  }
}

public struct RouteOptimizationResult: Equatable, Sendable {
  public var orderedStops: [OptimizedStop]
  public var totalDistance: Double

  public init(orderedStops: [OptimizedStop], totalDistance: Double) {
    self.orderedStops = orderedStops
    self.totalDistance = totalDistance
  }
}
```

Create `RouteOptimizer.swift`:

```swift
public enum RouteOptimizer {
  public static func optimize(
    start: NavigationCoordinate?,
    stops: [RouteStopCandidate]
  ) -> RouteOptimizationResult {
    guard !stops.isEmpty else {
      return RouteOptimizationResult(orderedStops: [], totalDistance: 0)
    }

    let ordered = stops.sorted {
      ($0.existingSortIndex, $0.label, $0.id.uuidString) < ($1.existingSortIndex, $1.label, $1.id.uuidString)
    }
    return result(for: ordered, start: start)
  }

  private static func result(
    for stops: [RouteStopCandidate],
    start: NavigationCoordinate?
  ) -> RouteOptimizationResult {
    var previous = start
    var total = 0.0
    let optimized = stops.enumerated().map { index, stop in
      let distance = previous.map { $0.distance(to: stop.coordinate) } ?? 0
      previous = stop.coordinate
      total += distance
      return OptimizedStop(candidate: stop, order: index, distanceFromPrevious: distance)
    }
    return RouteOptimizationResult(orderedStops: optimized, totalDistance: total)
  }
}
```

- [ ] **Step 4: Run test**

Run: `cd RouteyKit && swift test --filter RouteOptimizerTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Sources/RouteyNavigation RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift
git commit -m "feat(navigation): add optimizer result types"
```

### Task 4: Add Nearest-Neighbor Ordering

**Files:**
- Modify: `RouteyKit/Sources/RouteyNavigation/RouteOptimizer.swift`
- Modify: `RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift`

**Interfaces:**
- Preserves `RouteOptimizer.optimize(start:stops:)`.

- [ ] **Step 1: Add failing test**

Append:

```swift
@Test func optimizerStartsWithNearestStopFromCurrentLocation() {
  let start = NavigationCoordinate(latitude: 45.0, longitude: -63.0)
  let far = RouteStopCandidate(
    id: UUID(),
    label: "Far",
    coordinate: NavigationCoordinate(latitude: 45.30, longitude: -63.0),
    existingSortIndex: 0
  )
  let near = RouteStopCandidate(
    id: UUID(),
    label: "Near",
    coordinate: NavigationCoordinate(latitude: 45.01, longitude: -63.0),
    existingSortIndex: 1
  )

  let result = RouteOptimizer.optimize(start: start, stops: [far, near])
  #expect(result.orderedStops.first?.candidate.id == near.id)
}
```

- [ ] **Step 2: Run failing test**

Run: `cd RouteyKit && swift test --filter RouteOptimizerTests`

Expected: FAIL because current implementation preserves sort order.

- [ ] **Step 3: Implement nearest-neighbor**

Replace `optimize(start:stops:)` and add helper:

```swift
  public static func optimize(
    start: NavigationCoordinate?,
    stops: [RouteStopCandidate]
  ) -> RouteOptimizationResult {
    guard !stops.isEmpty else {
      return RouteOptimizationResult(orderedStops: [], totalDistance: 0)
    }

    let ordered = nearestNeighborOrder(start: start, stops: stops)
    return result(for: ordered, start: start)
  }

  private static func nearestNeighborOrder(
    start: NavigationCoordinate?,
    stops: [RouteStopCandidate]
  ) -> [RouteStopCandidate] {
    var remaining = stops
    var current = start ?? stops.sorted {
      ($0.existingSortIndex, $0.label, $0.id.uuidString) < ($1.existingSortIndex, $1.label, $1.id.uuidString)
    }[0].coordinate
    var ordered: [RouteStopCandidate] = []

    while !remaining.isEmpty {
      let nextIndex = remaining.indices.min { lhs, rhs in
        let left = current.distance(to: remaining[lhs].coordinate)
        let right = current.distance(to: remaining[rhs].coordinate)
        if left != right { return left < right }
        return (remaining[lhs].existingSortIndex, remaining[lhs].label, remaining[lhs].id.uuidString)
          < (remaining[rhs].existingSortIndex, remaining[rhs].label, remaining[rhs].id.uuidString)
      }!
      let next = remaining.remove(at: nextIndex)
      ordered.append(next)
      current = next.coordinate
    }

    return ordered
  }
```

- [ ] **Step 4: Run test**

Run: `cd RouteyKit && swift test --filter RouteOptimizerTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Sources/RouteyNavigation/RouteOptimizer.swift RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift
git commit -m "feat(navigation): order stops by nearest neighbor"
```

### Task 5: Add 2-Opt Improvement

**Files:**
- Modify: `RouteyKit/Sources/RouteyNavigation/RouteOptimizer.swift`
- Modify: `RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift`

**Interfaces:**
- Preserves `RouteOptimizer.optimize(start:stops:)`.

- [ ] **Step 1: Add regression test**

Append:

```swift
@Test func twoOptDoesNotIncreaseTotalDistance() {
  let start = NavigationCoordinate(latitude: 45.0, longitude: -63.0)
  let stops = [
    RouteStopCandidate(id: UUID(), label: "A", coordinate: .init(latitude: 45.00, longitude: -63.10), existingSortIndex: 0),
    RouteStopCandidate(id: UUID(), label: "B", coordinate: .init(latitude: 45.10, longitude: -63.00), existingSortIndex: 1),
    RouteStopCandidate(id: UUID(), label: "C", coordinate: .init(latitude: 45.10, longitude: -63.10), existingSortIndex: 2),
    RouteStopCandidate(id: UUID(), label: "D", coordinate: .init(latitude: 45.00, longitude: -63.00), existingSortIndex: 3),
  ]

  let nearestOnly = RouteOptimizer.nearestNeighborPreview(start: start, stops: stops)
  let optimized = RouteOptimizer.optimize(start: start, stops: stops)

  #expect(optimized.totalDistance <= nearestOnly.totalDistance)
  #expect(optimized.orderedStops.map(\.candidate.id).sorted { $0.uuidString < $1.uuidString }
    == stops.map(\.id).sorted { $0.uuidString < $1.uuidString })
}
```

- [ ] **Step 2: Run failing test**

Run: `cd RouteyKit && swift test --filter RouteOptimizerTests`

Expected: FAIL because `nearestNeighborPreview` is undefined.

- [ ] **Step 3: Implement preview and 2-opt**

Add to `RouteOptimizer`:

```swift
  public static func nearestNeighborPreview(
    start: NavigationCoordinate?,
    stops: [RouteStopCandidate]
  ) -> RouteOptimizationResult {
    result(for: nearestNeighborOrder(start: start, stops: stops), start: start)
  }
```

Change `optimize` to:

```swift
    let nearest = nearestNeighborOrder(start: start, stops: stops)
    let improved = twoOpt(nearest, start: start)
    return result(for: improved, start: start)
```

Add:

```swift
  private static func twoOpt(
    _ stops: [RouteStopCandidate],
    start: NavigationCoordinate?
  ) -> [RouteStopCandidate] {
    guard stops.count >= 4 else { return stops }

    var best = stops
    var bestDistance = pathDistance(best, start: start)
    var improved = true

    while improved {
      improved = false
      for i in 0..<(best.count - 2) {
        for k in (i + 1)..<best.count {
          var candidate = best
          candidate[i...k].reverse()
          let candidateDistance = pathDistance(candidate, start: start)
          if candidateDistance < bestDistance {
            best = candidate
            bestDistance = candidateDistance
            improved = true
          }
        }
      }
    }

    return best
  }

  private static func pathDistance(
    _ stops: [RouteStopCandidate],
    start: NavigationCoordinate?
  ) -> Double {
    var previous = start
    return stops.reduce(into: 0.0) { total, stop in
      if let previous {
        total += previous.distance(to: stop.coordinate)
      }
      previous = stop.coordinate
    }
  }
```

- [ ] **Step 4: Run all package tests**

Run: `cd RouteyKit && swift test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Sources/RouteyNavigation/RouteOptimizer.swift RouteyKit/Tests/RouteyNavigationTests/RouteOptimizerTests.swift
git commit -m "feat(navigation): improve route order with two opt"
```

## Plan 1 Completion Handoff

- [ ] Add a "Learning Log From Previous Plan" entry to Plan 2 with the final public interfaces and any deviations.
- [ ] Run `git status --short --branch`.
- [ ] Continue to Plan 2 only after Plan 1 tests pass.
