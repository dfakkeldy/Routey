import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct HistoryArchiveTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func seedRuns(in database: DatabaseQueue) throws -> (target: TodaysRun.ID, unrelated: TodaysRun.ID) {
    let routeID = UUID()
    let targetRunID = UUID()
    let unrelatedRunID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try TodaysRun.insert {
        TodaysRun(
          id: targetRunID,
          routeID: routeID,
          serviceDate: "2026-06-22",
          createdAt: Date(timeIntervalSince1970: 1_782_000_000)
        )
      }
      .execute(db)
      try TodaysRun.insert {
        TodaysRun(
          id: unrelatedRunID,
          routeID: routeID,
          serviceDate: "2026-06-23",
          createdAt: Date(timeIntervalSince1970: 1_782_086_400)
        )
      }
      .execute(db)
    }

    return (targetRunID, unrelatedRunID)
  }

  @Test func archiveSetsArchivedAtForTargetRunOnly() throws {
    let database = try freshDB()
    let runs = try seedRuns(in: database)
    let archivedAt = Date(timeIntervalSince1970: 1_782_090_000)

    try History.archive(runID: runs.target, at: archivedAt, in: database)

    let target = try #require(try database.read { db in
      try TodaysRun.find(runs.target).fetchOne(db)
    })
    let unrelated = try #require(try database.read { db in
      try TodaysRun.find(runs.unrelated).fetchOne(db)
    })

    #expect(target.archivedAt == archivedAt)
    #expect(unrelated.archivedAt == nil)
  }
}
