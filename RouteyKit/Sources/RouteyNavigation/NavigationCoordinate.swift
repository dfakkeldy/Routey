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
