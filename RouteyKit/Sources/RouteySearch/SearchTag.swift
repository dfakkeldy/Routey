import Foundation

public struct SearchTag: Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var isWarning: Bool

  public init(id: UUID, name: String, isWarning: Bool) {
    self.id = id
    self.name = name
    self.isWarning = isWarning
  }
}
