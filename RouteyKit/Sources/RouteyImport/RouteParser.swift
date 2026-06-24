import Foundation

public enum RouteParser {
  public static func parse(_ text: String) -> ParseResult {
    let lines = text.components(separatedBy: .newlines)

    guard let header = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
      return ParseResult()
    }

    if isCSVHeader(header) {
      return parseCSV(lines)
    }

    return parseFreeform(lines)
  }

  private static func isCSVHeader(_ line: String) -> Bool {
    line
      .split(separator: ",", omittingEmptySubsequences: false)
      .map { normalized($0) }
      .contains("street")
  }

  private static func parseFreeform(_ lines: [String]) -> ParseResult {
    var result = ParseResult()

    for (index, raw) in lines.enumerated() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let sourceLine = index + 1

      guard !line.isEmpty else { continue }

      guard !line.allSatisfy({ !$0.isLetter && !$0.isNumber }) else {
        result.skipped.append(SkippedRow(line: sourceLine, raw: raw, reason: "no civic number or street"))
        continue
      }

      if let leading = leadingCivic(in: line) {
        result.stops.append(
          ParsedStop(civicNumber: leading.civicNumber, street: leading.street, sourceLine: sourceLine)
        )
      } else {
        result.stops.append(ParsedStop(street: line, sourceLine: sourceLine))
      }
    }

    return result
  }

  private static func leadingCivic(in line: String) -> (civicNumber: Int, street: String)? {
    let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)

    guard
      parts.count == 2,
      let civicNumber = Int(parts[0])
    else {
      return nil
    }

    let street = parts[1].trimmingCharacters(in: .whitespaces)
    guard !street.isEmpty else { return nil }
    return (civicNumber, street)
  }

  private static func parseCSV(_ lines: [String]) -> ParseResult {
    var result = ParseResult()
    var header: [String]?

    for (index, raw) in lines.enumerated() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let sourceLine = index + 1

      guard !line.isEmpty else { continue }

      if header == nil {
        header = raw
          .split(separator: ",", omittingEmptySubsequences: false)
          .map { normalized($0) }
        continue
      }

      guard let header else { continue }

      let fields = raw
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespaces) }

      guard fields.count <= header.count else {
        result.skipped.append(SkippedRow(line: sourceLine, raw: raw, reason: "more fields than headers"))
        continue
      }

      let civicNumber = field("civic", in: fields, header: header).flatMap(Int.init)
      let street = field("street", in: fields, header: header) ?? ""

      guard civicNumber != nil || !street.isEmpty else {
        result.skipped.append(SkippedRow(line: sourceLine, raw: raw, reason: "no civic number or street"))
        continue
      }

      result.stops.append(
        ParsedStop(
          tieOut: field("tieout", in: fields, header: header),
          civicNumber: civicNumber,
          street: street,
          occupantName: field("occupant", in: fields, header: header),
          notes: field("notes", in: fields, header: header),
          sourceLine: sourceLine
        )
      )
    }

    return result
  }

  private static func field(_ name: String, in fields: [String], header: [String]) -> String? {
    guard
      let index = header.firstIndex(of: name),
      index < fields.count
    else {
      return nil
    }

    return fields[index].isEmpty ? nil : fields[index]
  }

  private static func normalized(_ value: some StringProtocol) -> String {
    String(value).trimmingCharacters(in: .whitespaces).lowercased()
  }
}
