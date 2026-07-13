public struct LabelReadout: Equatable, Sendable {
  public var lines: [String]
  public var barcodes: [String]

  public init(lines: [String], barcodes: [String] = []) {
    self.lines = lines
    self.barcodes = barcodes
  }
}

public protocol LabelReading: Sendable {
  func read() async throws -> LabelReadout
}

public struct SnapMatchResult: Equatable, Sendable {
  public var band: MatchBand
  public var ranked: [ScoredAddressCandidate]
  public var flags: LabelFlags
  public var readout: LabelReadout
  public var components: AddressComponents

  public init(
    band: MatchBand,
    ranked: [ScoredAddressCandidate],
    flags: LabelFlags,
    readout: LabelReadout,
    components: AddressComponents
  ) {
    self.band = band
    self.ranked = ranked
    self.flags = flags
    self.readout = readout
    self.components = components
  }
}

public struct SnapPipeline: Sendable {
  public var reader: any LabelReading
  public var candidateProvider: @Sendable (AddressComponents) -> [AddressCandidate]

  public init(
    reader: any LabelReading,
    candidateProvider: @escaping @Sendable (AddressComponents) -> [AddressCandidate]
  ) {
    self.reader = reader
    self.candidateProvider = candidateProvider
  }

  public func process() async throws -> SnapMatchResult {
    let readout = try await reader.read()
    let text = readout.lines.joined(separator: "\n")
    let components = AddressNormalizer.normalize(text)
    let candidates = candidateProvider(components)
    let ranked = AddressMatcher.rank(components, against: candidates)
    let band = AddressMatcher.band(ranked, for: components)
    let flags = LabelKeywordDetector.detect(in: text)

    return SnapMatchResult(
      band: band,
      ranked: ranked,
      flags: flags,
      readout: readout,
      components: components
    )
  }
}
