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
  @State private var pendingOptimization: RunOptimizationSuggestion?
  @State private var isShowingOptimizationConfirmation = false

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
        .onMove(perform: move)
      }
    }
    .navigationDestination(for: RunStop.ID.self) { runStopID in
      RunStopDetailView(runID: runID, runStopID: runStopID)
    }
    .toolbar {
      Button("Optimize", systemImage: "arrow.up.arrow.down", action: optimizeRun)
        .disabled(board.stops.isEmpty)

      EditButton()
    }
    .alert(
      "Use suggested order for parcel stops?",
      isPresented: $isShowingOptimizationConfirmation,
      presenting: pendingOptimization
    ) { suggestion in
      Button("Use Order") {
        applyOptimization(suggestion)
      }
      Button("Cancel", role: .cancel) {
        pendingOptimization = nil
      }
    } message: { suggestion in
      Text(optimizationConfirmationMessage(for: suggestion))
    }
    .alert("Couldn't Update Run", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func optimizeRun() {
    do {
      let suggestion = try RunOptimization.suggest(runID: runID, start: nil, in: database)
      guard !suggestion.orderedRunStopIDs.isEmpty else {
        errorMessage = "Resolve coordinates first"
        isShowingError = true
        return
      }

      pendingOptimization = suggestion
      isShowingOptimizationConfirmation = true
    } catch {
      show(error)
    }
  }

  private func applyOptimization(_ suggestion: RunOptimizationSuggestion) {
    do {
      try RunOptimization.apply(suggestion, to: runID, in: database)
      pendingOptimization = nil
      sendChanges(reason: "run stops optimized")
    } catch {
      show(error)
    }
  }

  private func optimizationConfirmationMessage(for suggestion: RunOptimizationSuggestion) -> String {
    let unresolvedCount = suggestion.unresolvedRunStopIDs.count
    guard unresolvedCount > 0 else {
      return "All coordinate-backed parcel stops will be reordered."
    }

    let label = unresolvedCount == 1 ? "stop needs" : "stops need"
    return "\(unresolvedCount.formatted(.number)) parcel \(label) coordinates first."
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

  private func move(from offsets: IndexSet, to destination: Int) {
    let movedIDs = Set(offsets.map { board.stops[$0].runStopID })
    var reorderedStops = board.stops
    reorderedStops.move(fromOffsets: offsets, toOffset: destination)

    do {
      for stop in reorderedStops where movedIDs.contains(stop.runStopID) {
        let precedingID = precedingRunStopID(for: stop.runStopID, in: reorderedStops)
        try RunOperations.moveRunStop(
          stop.runStopID,
          after: precedingID,
          in: database
        )
      }
      sendChanges(reason: "run stops reordered")
    } catch {
      show(error)
    }
  }

  private func precedingRunStopID(
    for runStopID: RunStop.ID,
    in stops: [RunStopSummary]
  ) -> RunStop.ID? {
    guard let index = stops.firstIndex(where: { $0.runStopID == runStopID }), index > 0 else {
      return nil
    }
    return stops[index - 1].runStopID
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
