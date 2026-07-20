import Foundation
import RouteyModel

public struct AddressCandidate: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var civicNumber: Int?
  public var civicRangeFrom: Int?
  public var civicRangeTo: Int?
  public var suite: String?
  public var street: String
  public var occupantName: String?
  public var postalCode: String?
  public var locator: String?
  public var tagNames: [String]
  public var warningTagNames: [String]

  public var hasWarning: Bool {
    !warningTagNames.isEmpty
  }

  public init(
    id: UUID = UUID(),
    civicNumber: Int? = nil,
    civicRangeFrom: Int? = nil,
    civicRangeTo: Int? = nil,
    suite: String? = nil,
    street: String,
    occupantName: String? = nil,
    postalCode: String? = nil,
    locator: String? = nil,
    tagNames: [String] = [],
    warningTagNames: [String] = []
  ) {
    self.id = id
    self.civicNumber = civicNumber
    self.civicRangeFrom = civicRangeFrom
    self.civicRangeTo = civicRangeTo
    self.suite = suite
    self.street = street
    self.occupantName = occupantName
    self.postalCode = postalCode
    self.locator = locator
    self.tagNames = tagNames
    self.warningTagNames = warningTagNames
  }

  public init(_ address: Address) {
    self.init(
      id: address.id,
      civicNumber: address.civicNumber,
      civicRangeFrom: address.civicRangeFrom,
      civicRangeTo: address.civicRangeTo,
      suite: address.suite,
      street: address.street,
      occupantName: address.occupantName,
      postalCode: address.postalCode
    )
  }
}

public struct ScoredAddressCandidate: Equatable, Identifiable, Sendable {
  public var candidate: AddressCandidate
  public var score: Double

  public var id: UUID {
    candidate.id
  }

  public init(candidate: AddressCandidate, score: Double) {
    self.candidate = candidate
    self.score = score
  }
}
