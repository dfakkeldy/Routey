import RouteyPersistence
import SQLiteData
import SwiftUI

@main
struct RouteyApp: App {
  init() {
    do {
      if ScreenshotMode.isEnabled {
        let database = try ScreenshotMode.configuredDatabase()
        prepareDependencies {
          $0.defaultDatabase = database
        }
      } else {
        let database = try routeyDatabase()
        let syncEngine = try routeySyncEngine(for: database)
        prepareDependencies {
          $0.defaultDatabase = database
          $0.defaultSyncEngine = syncEngine
        }
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
