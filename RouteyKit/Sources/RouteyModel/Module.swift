import Foundation
import SQLiteData

@Table
public struct Module: Identifiable, Sendable {
  public let id: UUID
  public var stopID: Stop.ID
  public var name = ""
  public var sortIndex = 0.0
  public init(id: UUID = UUID(), stopID: Stop.ID, name: String = "", sortIndex: Double = 0) {
    self.id = id; self.stopID = stopID; self.name = name; self.sortIndex = sortIndex
  }
}
