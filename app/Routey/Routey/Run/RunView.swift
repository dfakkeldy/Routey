import Foundation
import RouteyDomain
import RouteyModel
import SQLiteData
import SwiftUI

struct RunView: View {
  @Dependency(\.defaultDatabase) private var database
  @FetchAll(Route.order { $0.name }) private var routes: [Route]
  @State private var runID: TodaysRun.ID?
  @State private var isSnapping = false
  @State private var errorMessage = ""
  @State private var isShowingError = false

  var body: some View {
    NavigationStack {
      Group {
        if routes.first == nil {
          ContentUnavailableView(
            "No Route",
            systemImage: "map",
            description: Text("Import a route on the Routes tab to start a run.")
          )
        } else if let runID {
          RunBoardView(runID: runID)
        } else {
          ProgressView()
        }
      }
      .navigationTitle("Today's Run")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        Button("Snap Parcel", systemImage: "camera") {
          isSnapping = true
        }
        .disabled(routes.isEmpty)
      }
    }
    .task(id: routes.first?.id) {
      guard let route = routes.first else {
        runID = nil
        return
      }

      do {
        runID = try RunGeneration.generate(
          routeID: route.id,
          serviceDate: Self.serviceDate(for: .now),
          now: .now,
          into: database
        )
      } catch {
        show(error)
      }
    }
    .fullScreenCover(isPresented: $isSnapping) {
      if let route = routes.first {
        SnapView(route: route) {
          isSnapping = false
        }
      }
    }
    .alert("Couldn't Open Today's Run", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  static func serviceDate(for date: Date) -> String {
    date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
  }

  private func show(_ error: any Error) {
    errorMessage = error.localizedDescription
    isShowingError = true
  }
}
