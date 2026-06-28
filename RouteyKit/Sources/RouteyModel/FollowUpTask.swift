import Foundation
import SQLiteData

@Table
public nonisolated struct FollowUpTask: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var runID: TodaysRun.ID
  public var targetStopID: Stop.ID? = nil
  public var addressID: Address.ID? = nil
  public var text = ""
  public var isDone = false

  public init(
    id: UUID = UUID(),
    runID: TodaysRun.ID,
    targetStopID: Stop.ID? = nil,
    addressID: Address.ID? = nil,
    text: String = "",
    isDone: Bool = false
  ) {
    self.id = id
    self.runID = runID
    self.targetStopID = targetStopID
    self.addressID = addressID
    self.text = text
    self.isDone = isDone
  }
}
