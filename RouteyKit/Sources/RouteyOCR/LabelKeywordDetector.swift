public struct LabelFlags: OptionSet, Sendable {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static let signature = LabelFlags(rawValue: 1 << 0)
  public static let customs = LabelFlags(rawValue: 1 << 1)
  public static let registered = LabelFlags(rawValue: 1 << 2)
}

public enum LabelKeywordDetector {
  public static func detect(in text: String) -> LabelFlags {
    let phrase = AddressNormalizer.normalizedPhrase(text)
    var flags: LabelFlags = []

    if phrase.contains("signature") {
      flags.insert(.signature)
    }

    if phrase.contains("customs")
      || phrase.contains("duty")
      || phrase.contains("douane")
      || phrase.contains("declaration") {
      flags.insert(.customs)
    }

    if phrase.contains("registered")
      || phrase.contains("recommande") {
      flags.insert(.registered)
    }

    return flags
  }
}
