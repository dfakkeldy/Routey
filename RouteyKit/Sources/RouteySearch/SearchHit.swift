import Foundation
import RouteyModel

public struct SearchHit: Equatable, Sendable {
  public var address: Address
  public var stopNickname: String
  public var tieOut: String
  public var moduleName: String?
  public var compartmentLabel: String?
  public var sharedCivics: [Int]
  public var tags: [SearchTag]

  public var tagNames: [String] {
    tags.map(\.name)
  }

  public init(
    address: Address,
    stopNickname: String,
    tieOut: String,
    moduleName: String?,
    compartmentLabel: String?,
    sharedCivics: [Int],
    tags: [SearchTag]
  ) {
    self.address = address
    self.stopNickname = stopNickname
    self.tieOut = tieOut
    self.moduleName = moduleName
    self.compartmentLabel = compartmentLabel
    self.sharedCivics = sharedCivics
    self.tags = tags
  }
}
