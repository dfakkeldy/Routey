import Foundation
import SQLiteData
import RouteyModel

public enum RunGeneration {
  @discardableResult
  public static func generate(
    routeID: Route.ID,
    serviceDate: String,
    now: Date,
    into database: any DatabaseWriter
  ) throws -> TodaysRun.ID {
    try database.write { db in
      if let existingRun = try TodaysRun.all.fetchAll(db).first(where: {
        $0.routeID == routeID && $0.serviceDate == serviceDate
      }) {
        return existingRun.id
      }

      let runID = UUID()
      try TodaysRun.insert {
        TodaysRun(
          id: runID,
          routeID: routeID,
          serviceDate: serviceDate,
          createdAt: now
        )
      }
      .execute(db)

      let stops = try Stop
        .where { $0.routeID.eq(#bind(routeID)) }
        .order { $0.sortIndex }
        .fetchAll(db)

      for stop in stops {
        try RunStop.insert {
          RunStop(
            runID: runID,
            stopID: stop.id,
            tieOut: stop.tieOut,
            displayName: stop.displayName,
            kind: stop.kind,
            sortIndex: stop.sortIndex,
            isDone: false
          )
        }
        .execute(db)
      }

      return runID
    }
  }
}
