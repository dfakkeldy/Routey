import Foundation
import SQLiteData

@Table
public struct Tag: Identifiable, Sendable {
  public let id: UUID
  public var name = ""           // uniqueness enforced in app logic, NOT a DB constraint
  public var isWarning = false   // dog / scary-dog surface alerts
  public init(id: UUID = UUID(), name: String = "", isWarning: Bool = false) {
    self.id = id; self.name = name; self.isWarning = isWarning
  }
}
