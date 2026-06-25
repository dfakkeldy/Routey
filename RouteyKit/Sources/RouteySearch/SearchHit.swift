import Foundation
import RouteyModel

public struct SearchHit: Equatable, Sendable {
  public var address: Address
  public var stopNickname: String
  public var tieOut: String
  public var moduleName: String?
  public var compartmentLabel: String?
  public var sharedCivics: [Int]
  public var tagNames: [String]

  public init(
    address: Address,
    stopNickname: String,
    tieOut: String,
    moduleName: String?,
    compartmentLabel: String?,
    sharedCivics: [Int],
    tagNames: [String]
  ) {
    self.address = address
    self.stopNickname = stopNickname
    self.tieOut = tieOut
    self.moduleName = moduleName
    self.compartmentLabel = compartmentLabel
    self.sharedCivics = sharedCivics
    self.tagNames = tagNames
  }
}
