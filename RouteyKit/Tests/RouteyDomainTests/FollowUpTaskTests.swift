import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct FollowUpTaskTests {
  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func seedRun(in database: DatabaseQueue) throws -> (TodaysRun.ID, Stop.ID, Address.ID) {
    let routeID = UUID()
    let stopID = UUID()
    let addressID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try Stop.insert {
        Stop(
          id: stopID,
          routeID: routeID,
          tieOut: "A",
          sortIndex: 0,
          kind: "pointOfCall",
          displayName: "Sample Stop"
        )
      }
      .execute(db)
      try Address.insert { Address(id: addressID, street: "Placeholder Road") }.execute(db)
    }

    let runID = try RunGeneration.generate(
      routeID: routeID,
      serviceDate: "2026-06-22",
      now: Date(timeIntervalSince1970: 1_782_000_000),
      into: database
    )

    return (runID, stopID, addressID)
  }

  @Test func createFollowUpTaskPersistsTargetAddressTextAndDoneState() throws {
    let database = try freshDB()
    let (runID, stopID, addressID) = try seedRun(in: database)

    let taskID = try RunOperations.createFollowUpTask(
      runID: runID,
      targetStopID: stopID,
      addressID: addressID,
      text: "Check sample note",
      in: database
    )

    let task = try #require(try database.read { db in
      try FollowUpTask.find(taskID).fetchOne(db)
    })

    #expect(task.runID == runID)
    #expect(task.targetStopID == stopID)
    #expect(task.addressID == addressID)
    #expect(task.text == "Check sample note")
    #expect(!task.isDone)
  }
}
