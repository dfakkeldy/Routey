import Foundation
import RouteyImport

public struct ImportSummary: Equatable, Sendable {
  public var routeID: UUID
  public var stopsCreated: Int
  public var skipped: [SkippedRow]

  public init(routeID: UUID, stopsCreated: Int, skipped: [SkippedRow]) {
    self.routeID = routeID
    self.stopsCreated = stopsCreated
    self.skipped = skipped
  }
}
