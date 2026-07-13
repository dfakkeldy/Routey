import Foundation
import SQLiteData

@Table
public nonisolated struct TodaysRun: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var routeID: Route.ID
  public var serviceDate = ""
  public var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
  public var archivedAt: Date? = nil

  public init(
    id: UUID = UUID(),
    routeID: Route.ID,
    serviceDate: String = "",
    createdAt: Date = Date(timeIntervalSinceReferenceDate: 0),
    archivedAt: Date? = nil
  ) {
    self.id = id
    self.routeID = routeID
    self.serviceDate = serviceDate
    self.createdAt = createdAt
    self.archivedAt = archivedAt
  }
}
