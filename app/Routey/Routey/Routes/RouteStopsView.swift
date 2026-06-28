import SQLiteData
import SwiftUI
import RouteyDomain
import RouteyModel

struct RouteStopsView: View {
  let route: Route
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @FetchAll private var stops: [Stop]
  @State private var filter = ""
  @State private var errorMessage = ""
  @State private var isShowingError = false

  init(route: Route) {
    self.route = route
    _stops = FetchAll(
      Stop
        .where { $0.routeID.eq(#bind(route.id)) }
        .order { $0.sortIndex }
    )
  }

  var body: some View {
    let visibleStops = filtered(stops)

    List {
      ForEach(visibleStops) { stop in
        NavigationLink(value: stop) {
          StopRowView(stop: stop)
        }
      }
      .onDelete { offsets in
        deleteStops(at: offsets, from: visibleStops)
      }
    }
    .navigationTitle(route.name.isEmpty ? "Route" : route.name)
    .navigationDestination(for: Stop.self) { stop in
      StopDetailView(stop: stop)
    }
    .searchable(text: $filter, prompt: "Filter stops")
    .toolbar {
      Button("Add Stop", systemImage: "plus", action: addStop)
    }
    .alert("Couldn't Edit Route", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func filtered(_ stops: [Stop]) -> [Stop] {
    guard !filter.isEmpty else { return stops }

    return stops.filter { stop in
      stop.displayName.localizedStandardContains(filter)
        || stop.tieOut.localizedStandardContains(filter)
    }
  }

  private func addStop() {
    do {
      try RouteEditing.addStop(
        routeID: route.id,
        tieOut: "",
        displayName: "New stop",
        after: stops.last?.id,
        into: database
      )
      sendChanges(reason: "stop added")
    } catch {
      show(error)
    }
  }

  private func deleteStops(at offsets: IndexSet, from visibleStops: [Stop]) {
    do {
      for offset in offsets {
        try RouteEditing.deleteStop(visibleStops[offset].id, in: database)
      }
      sendChanges(reason: "stop deleted")
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
