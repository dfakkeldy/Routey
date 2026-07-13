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
