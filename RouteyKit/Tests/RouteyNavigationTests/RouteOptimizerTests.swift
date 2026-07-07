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
}
