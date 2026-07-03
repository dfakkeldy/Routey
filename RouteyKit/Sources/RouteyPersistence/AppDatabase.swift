import Foundation
import OSLog
import SQLiteData

private let logger = Logger(subsystem: "com.routey.app", category: "Database")

/// Opens or creates the app database, runs migrations, and returns the writer.
public func appDatabase(
  path: String? = nil,
  configuration: Configuration = Configuration()
) throws -> any DatabaseWriter {
  let database = try defaultDatabase(path: path, configuration: configuration)
  logger.info("open '\(database.path)'")
  try Schema.migrator.migrate(database)
  return database
}
