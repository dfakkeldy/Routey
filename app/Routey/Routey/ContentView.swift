import SQLiteData
import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Dependency(\.defaultSyncEngine) private var syncEngine

  var body: some View {
    TabView {
      Tab("Run", systemImage: "shippingbox") {
        RunView()
      }

      Tab("Routes", systemImage: "map") {
        RoutesView()
      }

      Tab("Search", systemImage: "magnifyingglass") {
        NavigationStack {
          SearchView()
        }
      }
    }
    .task {
      await RouteySyncing.synchronize(reason: "app appeared", using: syncEngine)
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

#Preview {
  ContentView()
}
