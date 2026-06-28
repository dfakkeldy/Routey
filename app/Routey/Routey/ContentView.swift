import SQLiteData
import SwiftUI
import RouteyModel

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @FetchAll(Route.order { $0.name }) private var routes: [Route]
  @State private var isImportingRoute = false

  var body: some View {
    NavigationStack {
      List(routes) { route in
        NavigationLink(value: route) {
          VStack(alignment: .leading) {
            Text(route.name.isEmpty ? "Untitled route" : route.name)
            if !route.rtaFSA.isEmpty {
              Text(route.rtaFSA)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle("Routes (\(routes.count))")
      .navigationDestination(for: Route.self) { route in
        RouteStopsView(route: route)
      }
      .navigationDestination(for: ContentDestination.self) { destination in
        switch destination {
        case .search:
          SearchView()
        }
      }
      .toolbar {
        NavigationLink(value: ContentDestination.search) {
          Label("Search", systemImage: "magnifyingglass")
        }

        Button("Import", systemImage: "square.and.arrow.down") {
          isImportingRoute = true
        }
      }
      .sheet(isPresented: $isImportingRoute) {
        ImportRouteView()
      }
      .overlay {
        if routes.isEmpty {
          ContentUnavailableView("No Routes", systemImage: "map")
        }
      }
      .task {
        await RouteySyncing.synchronize(reason: "route list appeared", using: syncEngine)
      }
      .onChange(of: scenePhase) { _, phase in
        switch phase {
        case .active:
          Task {
            await RouteySyncing.synchronize(reason: "app became active", using: syncEngine)
          }
        case .background:
          Task {
            await RouteySyncing.sendChanges(reason: "app entered background", using: syncEngine)
          }
        case .inactive:
          break
        @unknown default:
          break
        }
      }
    }
  }
}

private enum ContentDestination: Hashable {
  case search
}

#Preview {
  ContentView()
}
