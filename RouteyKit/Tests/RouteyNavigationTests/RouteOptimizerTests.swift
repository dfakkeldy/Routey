import Foundation
import Testing
@testable import RouteyNavigation

@Suite struct RouteOptimizerTests {
  @Test func coordinateStoresLatitudeAndLongitude() {
    let coordinate = NavigationCoordinate(latitude: 45.1, longitude: -63.2)
    #expect(coordinate.latitude == 45.1)
    #expect(coordinate.longitude == -63.2)
  }

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

  @Test func twoOptDoesNotIncreaseTotalDistance() {
    let start = NavigationCoordinate(latitude: 45.0, longitude: -63.0)
    let stops = [
      RouteStopCandidate(
        id: UUID(),
        label: "A",
        coordinate: .init(latitude: 45.00, longitude: -63.10),
        existingSortIndex: 0
      ),
      RouteStopCandidate(
        id: UUID(),
        label: "B",
        coordinate: .init(latitude: 45.10, longitude: -63.00),
        existingSortIndex: 1
      ),
      RouteStopCandidate(
        id: UUID(),
        label: "C",
        coordinate: .init(latitude: 45.10, longitude: -63.10),
        existingSortIndex: 2
      ),
      RouteStopCandidate(
        id: UUID(),
        label: "D",
        coordinate: .init(latitude: 45.00, longitude: -63.00),
        existingSortIndex: 3
      ),
    ]

    let nearestOnly = RouteOptimizer.nearestNeighborPreview(start: start, stops: stops)
    let optimized = RouteOptimizer.optimize(start: start, stops: stops)

    let optimizedIDs = optimized.orderedStops.map(\.candidate.id).sorted { $0.uuidString < $1.uuidString }
    let inputIDs = stops.map(\.id).sorted { $0.uuidString < $1.uuidString }

    #expect(optimized.totalDistance <= nearestOnly.totalDistance)
    #expect(optimizedIDs == inputIDs)
  }
}
