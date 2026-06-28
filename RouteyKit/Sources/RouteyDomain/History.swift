import Foundation
import GRDB
import SQLiteData
import RouteyModel
import RouteySearch

public enum History {
  private enum DecodeError: Error {
    case invalidUUID(column: String, value: String)
  }

  public struct HistoryFilter: Sendable {
    public var dateFrom: Date?
    public var dateTo: Date?
    public var outcome: String?
    public var tagName: String?
    public var hasPhoto: Bool?

    public init(
      dateFrom: Date? = nil,
      dateTo: Date? = nil,
      outcome: String? = nil,
      tagName: String? = nil,
      hasPhoto: Bool? = nil
    ) {
      self.dateFrom = dateFrom
      self.dateTo = dateTo
      self.outcome = outcome
      self.tagName = tagName
      self.hasPhoto = hasPhoto
    }
  }

  public static func archive(
    runID: TodaysRun.ID,
    at archivedAt: Date,
    in database: any DatabaseWriter
  ) throws {
    try database.write { db in
      try TodaysRun.find(runID)
        .update { $0.archivedAt = #bind(archivedAt) }
        .execute(db)
    }
  }

  public static func records(
    matching filter: HistoryFilter,
    in database: any DatabaseReader
  ) throws -> [DeliveryRecord] {
    try database.read { db in
      try records(matching: filter, in: db)
    }
  }

  public static func records(
    forAddressQuery query: String,
    in database: any DatabaseReader
  ) throws -> [DeliveryRecord] {
    try database.read { db in
      let addressIDs = try SearchIndex.match(query, in: db)
      guard !addressIDs.isEmpty else { return [] }

      let placeholders = Array(repeating: "?", count: addressIDs.count).joined(separator: ", ")
      let sql = """
        SELECT "deliveryRecords".*
        FROM "deliveryRecords"
        WHERE "deliveryRecords"."addressID" IN (\(placeholders))
        ORDER BY "deliveryRecords"."loggedAt" DESC, "deliveryRecords"."id" ASC
        """
      let arguments = StatementArguments(addressIDs.map { $0.uuidString.lowercased() })
      return try fetchDeliveryRecords(db, sql: sql, arguments: arguments)
    }
  }

  private static func records(
    matching filter: HistoryFilter,
    in db: Database
  ) throws -> [DeliveryRecord] {
    var whereClauses = [String]()
    var arguments = StatementArguments()

    if let outcome = filter.outcome {
      whereClauses.append(#""deliveryRecords"."outcome" = ?"#)
      arguments += [outcome]
    }

    if let hasPhoto = filter.hasPhoto {
      whereClauses.append(
        hasPhoto
          ? #""deliveryRecords"."photoPath" IS NOT NULL"#
          : #""deliveryRecords"."photoPath" IS NULL"#
      )
    }

    if let dateFrom = filter.dateFrom {
      whereClauses.append(#""deliveryRecords"."loggedAt" >= ?"#)
      arguments += [dateFrom]
    }

    if let dateTo = filter.dateTo {
      whereClauses.append(#""deliveryRecords"."loggedAt" <= ?"#)
      arguments += [dateTo]
    }

    if let tagName = filter.tagName {
      whereClauses.append(
        """
        EXISTS (
          SELECT 1
          FROM "addressTags"
          JOIN "tags" ON "tags"."id" = "addressTags"."tagID"
          WHERE "addressTags"."addressID" = "deliveryRecords"."addressID"
            AND "tags"."name" = ?
        )
        """
      )
      arguments += [tagName]
    }

    let whereSQL = whereClauses.isEmpty
      ? ""
      : "\nWHERE " + whereClauses.joined(separator: "\n  AND ")
    let sql = """
      SELECT "deliveryRecords".*
      FROM "deliveryRecords"\(whereSQL)
      ORDER BY "deliveryRecords"."loggedAt" DESC, "deliveryRecords"."id" ASC
      """

    return try fetchDeliveryRecords(db, sql: sql, arguments: arguments)
  }

  private static func fetchDeliveryRecords(
    _ db: Database,
    sql: String,
    arguments: StatementArguments
  ) throws -> [DeliveryRecord] {
    try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
      let idString: String = row["id"]
      let runIDString: String = row["runID"]
      let addressIDString: String? = row["addressID"]
      let parcelIDString: String? = row["parcelID"]

      guard let id = UUID(uuidString: idString) else {
        throw DecodeError.invalidUUID(column: "id", value: idString)
      }
      guard let runID = UUID(uuidString: runIDString) else {
        throw DecodeError.invalidUUID(column: "runID", value: runIDString)
      }

      return DeliveryRecord(
        id: id,
        runID: runID,
        addressID: try addressIDString.map { value in
          guard let id = UUID(uuidString: value) else {
            throw DecodeError.invalidUUID(column: "addressID", value: value)
          }
          return id
        },
        parcelID: try parcelIDString.map { value in
          guard let id = UUID(uuidString: value) else {
            throw DecodeError.invalidUUID(column: "parcelID", value: value)
          }
          return id
        },
        outcome: row["outcome"],
        latitude: row["latitude"],
        longitude: row["longitude"],
        loggedAt: row["loggedAt"],
        photoPath: row["photoPath"]
      )
    }
  }
}
