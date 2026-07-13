import Foundation

public enum MatchBand: Equatable, Sendable {
  case autoAccept(UUID)
  case review([ScoredAddressCandidate])
  case noMatch

  public var isReview: Bool {
    if case .review = self {
      true
    } else {
      false
    }
  }
}

public enum AddressMatcher {
  public static func rank(
    _ components: AddressComponents,
    against candidates: [AddressCandidate]
  ) -> [ScoredAddressCandidate] {
    candidates
      .map { candidate in
        ScoredAddressCandidate(
          candidate: candidate,
          score: score(components, against: candidate)
        )
      }
      .sorted { lhs, rhs in
        if lhs.score == rhs.score {
          lhs.id.uuidString < rhs.id.uuidString
        } else {
          lhs.score > rhs.score
        }
      }
  }

  public static func band(
    _ ranked: [ScoredAddressCandidate],
    for components: AddressComponents
  ) -> MatchBand {
    guard let top = ranked.first, top.score >= 0.55 else {
      return .noMatch
    }

    let secondScore = ranked.dropFirst().first?.score ?? 0
    let margin = top.score - secondScore

    if top.score >= 0.90,
      margin >= 0.15,
      canAutoAccept(top.candidate, for: components) {
      return .autoAccept(top.id)
    }

    let reviewCandidates = ranked
      .filter { $0.score >= 0.55 }
      .prefix(5)
    return .review(Array(reviewCandidates))
  }

  private static func score(_ components: AddressComponents, against candidate: AddressCandidate) -> Double {
    let candidateComponents = AddressNormalizer.normalize(candidate.street)

    guard hasAddressSignal(components) else {
      return 0
    }

    guard !hasConfidentCivicMismatch(components, candidate) else {
      return 0
    }

    guard !hasConfidentStreetNumberMismatch(
      queryTokens: components.streetTokens,
      candidateTokens: candidateComponents.streetTokens
    ) else {
      return 0
    }

    var score = 0.0
    var total = 0.0

    if components.civicNumber != nil {
      total += 0.35
      if civicMatches(components, candidate) {
        score += 0.35
      }
    }

    if !components.streetTokens.isEmpty {
      total += 0.45
      score += 0.45 * tokenSimilarity(components.streetTokens, candidateComponents.streetTokens)
    }

    if let unit = components.unit {
      total += 0.25
      score += 0.25 * phraseSimilarity(unit, candidate.suite ?? "")
    }

    if let occupant = components.occupant {
      total += 0.30
      score += 0.30 * phraseSimilarity(occupant, candidate.occupantName ?? "")
    }

    if let postalCode = components.postalCode {
      total += 0.05
      if postalCode == normalizedPostalCode(candidate.postalCode) {
        score += 0.05
      }
    }

    if let routeNumber = components.routeNumber {
      total += 0.05
      let candidateRoute = candidateComponents.routeNumber
        ?? candidateComponents.streetTokens.joined(separator: " ")
      score += 0.05 * phraseSimilarity(routeNumber, candidateRoute)
    }

    guard total > 0 else { return 0 }
    return min(1, score / total)
  }

  private static func hasConfidentCivicMismatch(
    _ components: AddressComponents,
    _ candidate: AddressCandidate
  ) -> Bool {
    guard let civicNumber = components.civicNumber else { return false }

    if let candidateCivic = candidate.civicNumber {
      return candidateCivic != civicNumber
    }

    if let rangeFrom = candidate.civicRangeFrom, let rangeTo = candidate.civicRangeTo {
      return !(rangeFrom...rangeTo).contains(civicNumber)
    }

    return false
  }

  private static func civicMatches(
    _ components: AddressComponents,
    _ candidate: AddressCandidate
  ) -> Bool {
    guard let civicNumber = components.civicNumber else {
      return candidate.civicNumber == nil
        && candidate.civicRangeFrom == nil
        && candidate.civicRangeTo == nil
    }

    if candidate.civicNumber == civicNumber {
      return true
    }

    if let rangeFrom = candidate.civicRangeFrom, let rangeTo = candidate.civicRangeTo {
      return (rangeFrom...rangeTo).contains(civicNumber)
    }

    return false
  }

  private static func canAutoAccept(
    _ candidate: AddressCandidate,
    for components: AddressComponents
  ) -> Bool {
    hasAddressSignal(components) && civicMatches(components, candidate)
  }

  private static func hasAddressSignal(_ components: AddressComponents) -> Bool {
    components.civicNumber != nil
      || !components.streetTokens.isEmpty
      || components.routeNumber != nil
  }

  private static func hasConfidentStreetNumberMismatch(
    queryTokens: [String],
    candidateTokens: [String]
  ) -> Bool {
    let queryLabeledNumbers = labeledNumbers(queryTokens)
    let candidateLabeledNumbers = labeledNumbers(candidateTokens)

    for label in Set(queryLabeledNumbers.keys).intersection(candidateLabeledNumbers.keys) {
      if queryLabeledNumbers[label] != candidateLabeledNumbers[label] {
        return true
      }
    }

    let queryNumbers = Set(queryTokens.filter { $0.allSatisfy(\.isNumber) })
    let candidateNumbers = Set(candidateTokens.filter { $0.allSatisfy(\.isNumber) })

    return !queryNumbers.isEmpty
      && !candidateNumbers.isEmpty
      && queryNumbers.isDisjoint(with: candidateNumbers)
  }

  private static func labeledNumbers(_ tokens: [String]) -> [String: String] {
    var labels: [String: String] = [:]

    for (index, token) in tokens.enumerated() {
      switch token {
      case "lot", "highway", "concession", "county":
        if let number = firstNumber(in: tokens, after: index) {
          labels[token] = number
        }
      case "route" where index > tokens.startIndex && tokens[index - 1] == "rural":
        if let number = firstNumber(in: tokens, after: index) {
          labels["rural route"] = number
        }
      default:
        break
      }
    }

    return labels
  }

  private static func firstNumber(in tokens: [String], after index: Int) -> String? {
    tokens
      .dropFirst(index + 1)
      .first { $0.allSatisfy(\.isNumber) }
  }

  private static func tokenSimilarity(_ queryTokens: [String], _ candidateTokens: [String]) -> Double {
    guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }

    let querySet = Set(queryTokens)
    let candidateSet = Set(candidateTokens)
    let intersectionCount = querySet.intersection(candidateSet).count
    let unionCount = querySet.union(candidateSet).count
    let jaccard = unionCount == 0 ? 0 : Double(intersectionCount) / Double(unionCount)

    let nearestTokenAverage = queryTokens
      .map { queryToken in
        candidateTokens
          .map { wordSimilarity(queryToken, $0) }
          .max() ?? 0
      }
      .reduce(0, +) / Double(queryTokens.count)

    return max(jaccard, (jaccard + nearestTokenAverage) / 2)
  }

  private static func phraseSimilarity(_ lhs: String, _ rhs: String) -> Double {
    let lhsTokens = AddressNormalizer.normalizedTokens(lhs)
    let rhsTokens = AddressNormalizer.normalizedTokens(rhs)

    if lhsTokens == rhsTokens {
      return 1
    }

    let similarity = tokenSimilarity(lhsTokens, rhsTokens)
    return similarity * similarity
  }

  private static func wordSimilarity(_ lhs: String, _ rhs: String) -> Double {
    guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
    if lhs == rhs { return 1 }

    let distance = AddressNormalizer.damerauLevenshtein(lhs, rhs)
    let maximumLength = max(lhs.count, rhs.count)
    return max(0, 1 - (Double(distance) / Double(maximumLength)))
  }

  private static func normalizedPostalCode(_ postalCode: String?) -> String? {
    postalCode.map { AddressNormalizer.normalizedTokens($0).joined() }
  }
}
