import SQLiteData
import SwiftUI
import RouteyModel

struct ContentView: View {
  @FetchAll(Route.order { $0.name }) private var routes: [Route]
  @Dependency(\.defaultDatabase) private var database
  @State private var saveError: SaveError?

  var body: some View {
    NavigationStack {
      List(routes) { route in
        Text(route.name.isEmpty ? "Untitled route" : route.name)
      }
      .navigationTitle("Routes (\(routes.count))")
      .toolbar {
        Button("Add", systemImage: "plus", action: addRoute)
      }
      .alert(item: $saveError) { error in
        Alert(
          title: Text("Couldn't Save Route"),
          message: Text(error.message),
          dismissButton: .default(Text("OK"))
        )
      }
    }
  }

  private func addRoute() {
    do {
      try database.write { db in
        try Route.insert {
          Route(name: "Route \(routes.count + 1)")
        }
        .execute(db)
      }
    } catch {
      saveError = SaveError(message: error.localizedDescription)
    }
  }
}

private struct SaveError: Identifiable {
  let id = UUID()
  var message: String
}

#Preview {
  ContentView()
}
