import RouteyDomain
import RouteyModel
import SQLiteData

struct RunBoardRequest: FetchKeyRequest {
  let runID: TodaysRun.ID

  func fetch(_ db: Database) throws -> RunBoard {
    try RunBoard.load(runID: runID, db)
  }
}
