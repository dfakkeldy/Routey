import SQLiteData
import SwiftUI
import RouteyModel

struct ContentView: View {
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
      .toolbar {
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
    }
  }
}

#Preview {
  ContentView()
}
