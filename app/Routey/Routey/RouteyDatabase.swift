import SQLiteData
import RouteyPersistence
import RouteySearch

func routeyDatabase(configuration: Configuration = Configuration()) throws -> any DatabaseWriter {
  let database = try appDatabase(configuration: configuration)
  try database.write { db in
    try SearchIndex.install(db)
    try SearchIndex.rebuild(from: db)
  }
  return database
}
