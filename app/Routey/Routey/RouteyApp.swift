import SQLiteData
import SwiftUI
import RouteyPersistence

@main
struct RouteyApp: App {
  init() {
    do {
      try prepareDependencies {
        $0.defaultDatabase = try appDatabase()
      }
    } catch {
      fatalError("Failed to open Routey database: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
