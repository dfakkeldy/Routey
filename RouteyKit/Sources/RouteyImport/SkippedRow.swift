public struct SkippedRow: Equatable, Sendable {
  public var line: Int
  public var raw: String
  public var reason: String

  public init(line: Int, raw: String, reason: String) {
    self.line = line
    self.raw = raw
    self.reason = reason
  }
}
