import Foundation
import RouteyDomain
import RouteyModel
import SQLiteData
import SwiftUI

struct RunView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Dependency(\.defaultDatabase) private var database
  @FetchAll(Route.order { $0.name }) private var routes: [Route]
  @State private var selectedRouteID: Route.ID?
  @State private var serviceDate = ServiceDate.local(for: .now)
  @State private var runID: TodaysRun.ID?
  @State private var isSnapping = false
  @State private var errorMessage = ""
  @State private var isShowingError = false

  private var selectedRoute: Route? {
    routes.first(where: { $0.id == selectedRouteID })
  }

  private var loadContext: RunLoadContext? {
    selectedRoute.map { RunLoadContext(routeID: $0.id, serviceDate: serviceDate) }
  }

  var body: some View {
    NavigationStack {
      Group {
        if routes.isEmpty {
          ContentUnavailableView {
            Label("No Route", systemImage: "map")
          } description: {
            Text("Import a route on the Routes tab to start a run.")
          } actions: {
            Button("Start Parcel Pile", systemImage: "shippingbox") {
              isSnapping = true
            }
            .buttonStyle(.borderedProminent)
          }
        } else if let runID {
          RunBoardView(runID: runID)
            .id(runID)
        } else {
          ProgressView()
        }
      }
      .navigationTitle("Today's Run")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if routes.count > 1 {
          ToolbarItem(placement: .topBarLeading) {
            Picker("Active Route", selection: $selectedRouteID) {
              ForEach(routes) { route in
                Text(route.name).tag(Optional(route.id))
              }
            }
            .pickerStyle(.menu)
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("Snap Parcel", systemImage: "camera") {
            isSnapping = true
          }
          .disabled(selectedRoute == nil)
        }
      }
    }
    .onChange(of: routes.map(\.id), initial: true) { _, _ in
      selectedRouteID = RunRouteSelection.preferredRouteID(
        in: routes,
        current: selectedRouteID
      )
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      refreshServiceDate()
    }
    .task(id: loadContext) {
      guard let request = loadContext else {
        runID = nil
        return
      }

      runID = nil
      do {
        let generatedRunID = try RunGeneration.generate(
          routeID: request.routeID,
          serviceDate: request.serviceDate,
          now: .now,
          into: database
        )
        guard !Task.isCancelled, loadContext == request else { return }
        runID = generatedRunID
      } catch {
        guard !Task.isCancelled else { return }
        show(error)
      }
    }
    .task {
      for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
        refreshServiceDate()
      }
    }
    .task {
      for await _ in NotificationCenter.default.notifications(named: .NSSystemTimeZoneDidChange) {
        refreshServiceDate()
      }
    }
    .fullScreenCover(isPresented: $isSnapping) {
      SnapView(route: selectedRoute) {
        isSnapping = false
      }
    }
    .alert("Couldn't Open Today's Run", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func refreshServiceDate(now: Date = .now) {
    serviceDate = ServiceDate.local(for: now)
  }

  private func show(_ error: any Error) {
    errorMessage = error.localizedDescription
    isShowingError = true
  }
}
