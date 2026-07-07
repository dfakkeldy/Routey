public enum RouteOptimizer {
  public static func optimize(
    start: NavigationCoordinate?,
    stops: [RouteStopCandidate]
  ) -> RouteOptimizationResult {
    guard !stops.isEmpty else {
      return RouteOptimizationResult(orderedStops: [], totalDistance: 0)
    }

    let nearest = nearestNeighborOrder(start: start, stops: stops)
    let improved = twoOpt(nearest, start: start)
    return result(for: improved, start: start)
  }

  public static func nearestNeighborPreview(
    start: NavigationCoordinate?,
    stops: [RouteStopCandidate]
  ) -> RouteOptimizationResult {
    result(for: nearestNeighborOrder(start: start, stops: stops), start: start)
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
          candidate.replaceSubrange(i...k, with: candidate[i...k].reversed())
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
}
