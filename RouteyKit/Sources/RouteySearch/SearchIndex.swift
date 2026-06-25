import Foundation
import SQLiteData
import RouteyModel

public enum SearchIndex {
  public static func install(_ db: Database) throws {
    try db.execute(sql: """
      CREATE VIRTUAL TABLE IF NOT EXISTS addressSearch USING fts5(
        addressID UNINDEXED, civic, street, occupant, postal,
        prefix='2 3 4', tokenize='unicode61'
      )
      """)
  }

  public static func rebuild(from db: Database) throws {
    try db.execute(sql: "DELETE FROM addressSearch")

    let addresses = try Address.all.fetchAll(db)
    for address in addresses {
      try db.execute(
        sql: """
          INSERT INTO addressSearch (addressID, civic, street, occupant, postal)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          address.id.uuidString,
          address.civicNumber.map(String.init) ?? "",
          address.street.ftsSearchNormalized,
          address.occupantName?.ftsSearchNormalized ?? "",
          address.postalCode?.ftsSearchNormalized ?? "",
        ])
    }
  }

  public static func match(_ query: String, in db: Database) throws -> [UUID] {
    let tokens = query.ftsSearchNormalized.split { character in
      !character.isLetter && !character.isNumber
    }

    guard !tokens.isEmpty else { return [] }

    let ftsQuery = tokens.map { "\($0)*" }.joined(separator: " ")
    let ids = try String.fetchAll(
      db,
      sql: """
        SELECT addressID
        FROM addressSearch
        WHERE addressSearch MATCH ?
        ORDER BY rank
        """,
      arguments: [ftsQuery])

    return ids.compactMap(UUID.init(uuidString:))
  }
}

extension String {
  fileprivate var ftsSearchNormalized: String {
    let compatible = precomposedStringWithCompatibilityMapping
    return compatible.applyingTransform(.stripDiacritics, reverse: false) ?? compatible
  }
}
