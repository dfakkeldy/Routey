public struct ParsedStop: Equatable, Sendable {
  public var tieOut: String?
  public var civicNumber: Int?
  public var street: String
  public var occupantName: String?
  public var postalCode: String?
  public var notes: String?
  public var siteName: String?
  public var moduleName: String?
  public var compartmentLabel: String?
  public var tags: [String]
  public var warningTags: [String]
  public var sourceLine: Int

  public init(
    tieOut: String? = nil,
    civicNumber: Int? = nil,
    street: String,
    occupantName: String? = nil,
    postalCode: String? = nil,
    notes: String? = nil,
    siteName: String? = nil,
    moduleName: String? = nil,
    compartmentLabel: String? = nil,
    tags: [String] = [],
    warningTags: [String] = [],
    sourceLine: Int
  ) {
    self.tieOut = tieOut
    self.civicNumber = civicNumber
    self.street = street
    self.occupantName = occupantName
    self.postalCode = postalCode
    self.notes = notes
    self.siteName = siteName
    self.moduleName = moduleName
    self.compartmentLabel = compartmentLabel
    self.tags = tags
    self.warningTags = warningTags
    self.sourceLine = sourceLine
  }
}
