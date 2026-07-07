import Testing
@testable import RouteyNavigation

@Suite struct RouteOptimizerTests {
  @Test func coordinateStoresLatitudeAndLongitude() {
    let coordinate = NavigationCoordinate(latitude: 45.1, longitude: -63.2)
    #expect(coordinate.latitude == 45.1)
    #expect(coordinate.longitude == -63.2)
  }
}
