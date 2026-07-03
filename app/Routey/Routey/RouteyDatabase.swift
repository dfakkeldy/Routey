import SQLiteData
import RouteyPersistence
import RouteySearch

func routeyDatabase(
  path: String? = nil,
  configuration: Configuration = Configuration()
) throws -> any DatabaseWriter {
  let database = try appDatabase(path: path, configuration: configuration)
  try database.write { db in
    try SearchIndex.install(db)
    try SearchIndex.rebuild(from: db)
  }
  return database
}
