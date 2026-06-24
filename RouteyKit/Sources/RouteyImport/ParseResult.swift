public struct ParseResult: Equatable, Sendable {
  public var stops: [ParsedStop]
  public var skipped: [SkippedRow]

  public init(stops: [ParsedStop] = [], skipped: [SkippedRow] = []) {
    self.stops = stops
    self.skipped = skipped
  }
}
