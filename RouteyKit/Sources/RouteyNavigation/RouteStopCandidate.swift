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
