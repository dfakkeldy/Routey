import RouteyDomain
import RouteyModel
import SQLiteData
import SwiftUI

struct RunBoardView: View {
  let runID: TodaysRun.ID
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @Fetch private var board: RunBoard
  @State private var errorMessage = ""
  @State private var isShowingError = false

  init(runID: TodaysRun.ID) {
    self.runID = runID
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
          HStack(spacing: 12) {
            Button(action: { setDone(!stop.isDone, for: stop) }) {
              Image(systemName: stop.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(stop.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stop.isDone ? "Mark not done" : "Mark done")

            NavigationLink(value: stop.runStopID) {
              RunStopRowView(stop: stop)
            }
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(
              stop.isDone ? "Not Done" : "Done",
              systemImage: stop.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle"
            ) {
              setDone(!stop.isDone, for: stop)
            }
            .tint(stop.isDone ? .orange : .green)
          }
          .swipeActions(edge: .leading) {
            if !stop.isDone {
              Button("Done Through Here", systemImage: "checkmark.circle.fill") {
                checkOffThrough(stop)
              }
              .tint(.blue)
            }
          }
        }
      }
    }
    .navigationDestination(for: RunStop.ID.self) { runStopID in
      RunStopDetailView(runID: runID, runStopID: runStopID)
    }
    .alert("Couldn't Update Run", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func setDone(_ isDone: Bool, for stop: RunStopSummary) {
    do {
      try RunOperations.setRunStopDone(stop.runStopID, done: isDone, in: database)
      sendChanges(reason: isDone ? "run stop completed" : "run stop reopened")
    } catch {
      show(error)
    }
  }

  private func checkOffThrough(_ stop: RunStopSummary) {
    do {
      try RunOperations.bulkCheckOff(
        throughRunStop: stop.runStopID,
        runID: runID,
        in: database
      )
      sendChanges(reason: "run stops completed")
    } catch {
      show(error)
    }
  }

  private func sendChanges(reason: String) {
    Task {
      await RouteySyncing.sendChanges(reason: reason, using: syncEngine)
    }
  }

  private func show(_ error: any Error) {
    errorMessage = error.localizedDescription
    isShowingError = true
  }
}
