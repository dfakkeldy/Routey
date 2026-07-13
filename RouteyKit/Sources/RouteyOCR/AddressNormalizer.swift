import Foundation

public struct AddressComponents: Equatable, Sendable {
  public var civicNumber: Int?
  public var unit: String?
  public var routeNumber: String?
  public var streetTokens: [String]
  public var occupant: String?
  public var postalCode: String?
  public var rawLines: [String]

  public init(
    civicNumber: Int? = nil,
    unit: String? = nil,
    routeNumber: String? = nil,
    streetTokens: [String] = [],
    occupant: String? = nil,
    postalCode: String? = nil,
    rawLines: [String] = []
  ) {
    self.civicNumber = civicNumber
    self.unit = unit
    self.routeNumber = routeNumber
    self.streetTokens = streetTokens
    self.occupant = occupant
    self.postalCode = postalCode
    self.rawLines = rawLines
  }
}

public enum AddressNormalizer {
  public static func normalize(_ text: String) -> AddressComponents {
    let rawLines = text
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    var civicNumber: Int?
    var unit: String?
    var routeNumber: String?
    var streetTokens: [String] = []
    var occupant: String?
    var postalCode: String?

    for rawLine in rawLines {
      let postalResult = removingPostalCode(from: rawTokens(rawLine))
      if postalCode == nil {
        postalCode = postalResult.postalCode
      }

      let unitResult = removingUnit(from: expandedTokens(postalResult.tokens))
      if unit == nil {
        unit = unitResult.unit
      }

      var tokens = unitResult.tokens
      guard !tokens.isEmpty else { continue }
      var lineHadCivic = false

      if shouldTreatAsOccupant(tokens), occupant == nil {
        occupant = tokens.joined(separator: " ")
        continue
      }

      if civicNumber == nil, let extraction = extractingCivic(from: tokens) {
        civicNumber = extraction.civic
        lineHadCivic = true
        tokens = extraction.remainingTokens
      }

      let routeResult = extractingRouteNumber(from: tokens)
      if routeNumber == nil {
        routeNumber = routeResult.routeNumber
      }
      tokens = routeResult.streetTokens

      if containsStreetEvidence(tokens) || lineHadCivic || routeResult.routeNumber != nil {
        streetTokens.append(contentsOf: tokens)
      }
    }

    return AddressComponents(
      civicNumber: civicNumber,
      unit: unit,
      routeNumber: routeNumber,
      streetTokens: streetTokens,
      occupant: occupant,
      postalCode: postalCode,
      rawLines: rawLines
    )
  }

  public static func damerauLevenshtein(_ lhs: String, _ rhs: String) -> Int {
    let a = Array(lhs)
    let b = Array(rhs)

    guard !a.isEmpty else { return b.count }
    guard !b.isEmpty else { return a.count }

    var distances = Array(
      repeating: Array(repeating: 0, count: b.count + 1),
      count: a.count + 1
    )

    for index in 0...a.count {
      distances[index][0] = index
    }

    for index in 0...b.count {
      distances[0][index] = index
    }

    for row in 1...a.count {
      for column in 1...b.count {
        let substitutionCost = a[row - 1] == b[column - 1] ? 0 : 1
        var best = min(
          distances[row - 1][column] + 1,
          distances[row][column - 1] + 1,
          distances[row - 1][column - 1] + substitutionCost
        )

        if row > 1,
          column > 1,
          a[row - 1] == b[column - 2],
          a[row - 2] == b[column - 1] {
          best = min(best, distances[row - 2][column - 2] + 1)
        }

        distances[row][column] = best
      }
    }

    return distances[a.count][b.count]
  }

  static func normalizedTokens(_ text: String) -> [String] {
    expandedTokens(rawTokens(text))
  }

  static func normalizedPhrase(_ text: String) -> String {
    normalizedTokens(text).joined(separator: " ")
  }

  private static func rawTokens(_ text: String) -> [String] {
    var normalized = ""
    let folded = text.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    .lowercased()

    for scalar in folded.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        normalized.unicodeScalars.append(scalar)
      } else {
        normalized.append(" ")
      }
    }

    return normalized
      .split(separator: " ")
      .map(String.init)
  }

  private static func expandedTokens(_ tokens: [String]) -> [String] {
    tokens.flatMap { token -> [String] in
      switch token {
      case "st", "str", "rue":
        ["street"]
      case "ave", "av":
        ["avenue"]
      case "rd", "ch", "chemin":
        ["road"]
      case "hwy":
        ["highway"]
      case "conc":
        ["concession"]
      case "rr":
        ["rural", "route"]
      case "apt", "apartment", "suite", "ste":
        ["unit"]
      case "n", "north", "nord":
        ["north"]
      case "s", "south", "sud":
        ["south"]
      case "e", "east", "est":
        ["east"]
      case "w", "west", "o", "ouest":
        ["west"]
      default:
        [token]
      }
    }
  }

  private static func removingPostalCode(from tokens: [String]) -> (tokens: [String], postalCode: String?) {
    for index in tokens.indices {
      if isFullPostalCode(tokens[index]) {
        var remaining = tokens
        let postalCode = remaining.remove(at: index)
        return (remaining, postalCode)
      }

      let nextIndex = tokens.index(after: index)
      if nextIndex < tokens.endIndex,
        isPostalCodePrefix(tokens[index]),
        isPostalCodeSuffix(tokens[nextIndex]) {
        var remaining = tokens
        let postalCode = remaining[index] + remaining[nextIndex]
        remaining.remove(at: nextIndex)
        remaining.remove(at: index)
        return (remaining, postalCode)
      }
    }

    return (tokens, nil)
  }

  private static func removingUnit(from tokens: [String]) -> (tokens: [String], unit: String?) {
    var remaining: [String] = []
    var unit: String?
    var index = tokens.startIndex

    while index < tokens.endIndex {
      let token = tokens[index]
      let nextIndex = tokens.index(after: index)

      if token == "unit", nextIndex < tokens.endIndex {
        unit = unit ?? tokens[nextIndex]
        index = tokens.index(after: nextIndex)
      } else {
        remaining.append(token)
        index = nextIndex
      }
    }

    return (remaining, unit)
  }

  private static func extractingCivic(from tokens: [String]) -> (civic: Int, remainingTokens: [String])? {
    if let first = tokens.first,
      let civic = Int(first),
      tokens.dropFirst().contains(where: { $0.contains(where: \.isLetter) }) {
      return (civic, Array(tokens.dropFirst()))
    }

    if let last = tokens.last,
      let civic = Int(last),
      containsStreetEvidence(Array(tokens.dropLast())),
      !containsRouteNumberEvidence(tokens) {
      return (civic, Array(tokens.dropLast()))
    }

    return nil
  }

  private static func extractingRouteNumber(
    from tokens: [String]
  ) -> (routeNumber: String?, streetTokens: [String]) {
    if let ruralIndex = tokens.firstIndex(of: "rural") {
      let routeIndex = tokens.index(after: ruralIndex)
      let numberIndex = routeIndex < tokens.endIndex ? tokens.index(after: routeIndex) : tokens.endIndex
      if routeIndex < tokens.endIndex,
        numberIndex < tokens.endIndex,
        tokens[routeIndex] == "route",
        tokens[numberIndex].allSatisfy(\.isNumber) {
        var remaining = tokens
        remaining.removeSubrange(ruralIndex...numberIndex)
        return ("rural route \(tokens[numberIndex])", remaining)
      }
    }

    if tokens.contains("concession"), let number = tokens.last(where: { $0.allSatisfy(\.isNumber) }) {
      return ("concession \(number)", tokens)
    }

    if let highwayIndex = tokens.firstIndex(of: "highway") {
      let highwayNumberIndex = tokens.index(after: highwayIndex)
      if highwayNumberIndex < tokens.endIndex, tokens[highwayNumberIndex].allSatisfy(\.isNumber) {
        var routeNumber = "highway \(tokens[highwayNumberIndex])"
        if let lotIndex = tokens.firstIndex(of: "lot") {
          let lotNumberIndex = tokens.index(after: lotIndex)
          if lotNumberIndex < tokens.endIndex, tokens[lotNumberIndex].allSatisfy(\.isNumber) {
            routeNumber += " lot \(tokens[lotNumberIndex])"
          }
        }
        return (routeNumber, tokens)
      }
    }

    if let countyIndex = tokens.firstIndex(of: "county") {
      let roadIndex = tokens.index(after: countyIndex)
      let numberIndex = roadIndex < tokens.endIndex ? tokens.index(after: roadIndex) : tokens.endIndex
      if roadIndex < tokens.endIndex,
        numberIndex < tokens.endIndex,
        tokens[roadIndex] == "road",
        tokens[numberIndex].allSatisfy(\.isNumber) {
        return ("county road \(tokens[numberIndex])", tokens)
      }
    }

    return (nil, tokens)
  }

  private static func containsStreetEvidence(_ tokens: [String]) -> Bool {
    !Set(tokens).isDisjoint(with: streetEvidence)
  }

  private static func containsRouteNumberEvidence(_ tokens: [String]) -> Bool {
    !Set(tokens).isDisjoint(with: routeNumberEvidence)
  }

  private static func shouldTreatAsOccupant(_ tokens: [String]) -> Bool {
    tokens.contains { $0.contains { $0.isLetter } }
      && tokens.first.flatMap(Int.init) == nil
      && !containsStreetEvidence(tokens)
      && !containsRouteNumberEvidence(tokens)
      && !tokens.contains(where: handlingWords.contains)
  }

  private static func isFullPostalCode(_ token: String) -> Bool {
    let characters = Array(token)
    return characters.count == 6
      && characters[0].isLetter
      && characters[1].isNumber
      && characters[2].isLetter
      && characters[3].isNumber
      && characters[4].isLetter
      && characters[5].isNumber
  }

  private static func isPostalCodePrefix(_ token: String) -> Bool {
    let characters = Array(token)
    return characters.count == 3
      && characters[0].isLetter
      && characters[1].isNumber
      && characters[2].isLetter
  }

  private static func isPostalCodeSuffix(_ token: String) -> Bool {
    let characters = Array(token)
    return characters.count == 3
      && characters[0].isNumber
      && characters[1].isLetter
      && characters[2].isNumber
  }

  private static let streetEvidence: Set<String> = [
    "avenue",
    "boulevard",
    "concession",
    "county",
    "drive",
    "highway",
    "lane",
    "lot",
    "road",
    "street",
    "terrace",
    "trail",
    "way",
  ]

  private static let routeNumberEvidence: Set<String> = [
    "concession",
    "county",
    "highway",
    "lot",
    "route",
    "rural",
  ]

  private static let handlingWords: Set<String> = [
    "customs",
    "declaration",
    "douane",
    "duty",
    "handling",
    "recommande",
    "registered",
    "required",
    "requise",
    "signature",
  ]
}
