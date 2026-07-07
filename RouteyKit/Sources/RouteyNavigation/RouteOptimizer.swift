public enum RouteOptimizer {
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
    var current = start ?? stops.sorted(by: precedesInStableOrder)[0].coordinate
    var ordered: [RouteStopCandidate] = []

    while !remaining.isEmpty {
      guard let nextIndex = remaining.indices.min(by: { lhs, rhs in
        let left = current.distance(to: remaining[lhs].coordinate)
        let right = current.distance(to: remaining[rhs].coordinate)
        if left != right { return left < right }
        return precedesInStableOrder(remaining[lhs], remaining[rhs])
      }) else {
        return ordered
      }

      let next = remaining.remove(at: nextIndex)
      ordered.append(next)
      current = next.coordinate
    }

    return ordered
  }

  private static func precedesInStableOrder(_ lhs: RouteStopCandidate, _ rhs: RouteStopCandidate) -> Bool {
    (lhs.existingSortIndex, lhs.label, lhs.id.uuidString)
      < (rhs.existingSortIndex, rhs.label, rhs.id.uuidString)
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
