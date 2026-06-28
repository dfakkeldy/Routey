import RouteyPersistence
import SQLiteData
import SwiftUI

@main
struct RouteyApp: App {
  init() {
    do {
      let database = try routeyDatabase()
      let syncEngine = try routeySyncEngine(for: database)
      prepareDependencies {
        $0.defaultDatabase = database
        $0.defaultSyncEngine = syncEngine
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
