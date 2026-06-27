import RouteyPersistence
import SQLiteData
import SwiftUI

@main
struct RouteyApp: App {
  init() {
    do {
      let database = try routeyDatabase()
      try prepareDependencies {
        $0.defaultDatabase = database
        $0.defaultSyncEngine = try routeySyncEngine(for: database)
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
