import Foundation
import SQLiteData

@Table
public nonisolated struct Route: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var name = ""
  public var rtaFSA = ""
  public var isBorrowed = false
  public init(id: UUID = UUID(), name: String = "", rtaFSA: String = "", isBorrowed: Bool = false) {
    self.id = id; self.name = name; self.rtaFSA = rtaFSA; self.isBorrowed = isBorrowed
  }
}
