public struct ParsedStop: Equatable, Sendable {
  public var tieOut: String?
  public var civicNumber: Int?
  public var street: String
  public var occupantName: String?
  public var notes: String?
  public var sourceLine: Int

  public init(
    tieOut: String? = nil,
    civicNumber: Int? = nil,
    street: String,
    occupantName: String? = nil,
    notes: String? = nil,
    sourceLine: Int
  ) {
    self.tieOut = tieOut
    self.civicNumber = civicNumber
    self.street = street
    self.occupantName = occupantName
    self.notes = notes
    self.sourceLine = sourceLine
  }
}
