import Foundation
import SQLiteData

@Table
public nonisolated struct RunStop: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var runID: TodaysRun.ID
  public var stopID: Stop.ID? = nil
  public var tieOut = ""
  public var displayName = ""
  public var kind = "pointOfCall"
  public var sortIndex = 0.0
  public var isDone = false

  public init(
    id: UUID = UUID(),
    runID: TodaysRun.ID,
    stopID: Stop.ID? = nil,
    tieOut: String = "",
    displayName: String = "",
    kind: String = "pointOfCall",
    sortIndex: Double = 0,
    isDone: Bool = false
  ) {
    self.id = id
    self.runID = runID
    self.stopID = stopID
    self.tieOut = tieOut
    self.displayName = displayName
    self.kind = kind
    self.sortIndex = sortIndex
    self.isDone = isDone
  }
}
