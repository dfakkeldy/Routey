import CoreLocation
import RouteyDomain

enum AppleAddressGeocoder {
  static func service() -> CoordinateResolutionService {
    CoordinateResolutionService(resolve: resolve)
  }

  static func resolve(_ query: String) async throws -> ResolvedCoordinate? {
    let geocoder = CLGeocoder()
    let placemarks = try await geocoder.geocodeAddressString(query)
    guard let coordinate = placemarks.first?.location?.coordinate else { return nil }
    return ResolvedCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
  }
}
