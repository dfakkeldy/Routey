public enum RouteOptimizer {
  public static func optimize(
    start: NavigationCoordinate?,
    stops: [RouteStopCandidate]
  ) -> RouteOptimizationResult {
    guard !stops.isEmpty else {
      return RouteOptimizationResult(orderedStops: [], totalDistance: 0)
    }

    let ordered = stops.sorted {
      ($0.existingSortIndex, $0.label, $0.id.uuidString)
        < ($1.existingSortIndex, $1.label, $1.id.uuidString)
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
