import RouteyDomain
import RouteyModel
import SQLiteData
import SwiftUI

struct RunBoardView: View {
  @Fetch private var board: RunBoard

  init(runID: TodaysRun.ID) {
    _board = Fetch(wrappedValue: .empty, RunBoardRequest(runID: runID))
  }

  var body: some View {
    List {
      Section {
        HStack {
          Text("\(board.doneCount)/\(board.total) done")
          Spacer()
          if board.signatureCount > 0 {
            Label("\(board.signatureCount)", systemImage: "signature")
          }
        }
        .font(.headline)
      }

      if board.stops.isEmpty {
        ContentUnavailableView("No stops yet", systemImage: "shippingbox")
      } else {
        ForEach(board.stops) { stop in
          RunStopRowView(stop: stop)
        }
      }
    }
  }
}
