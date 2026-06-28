import OSLog
import SQLiteData

private let routeySyncLogger = Logger(subsystem: "com.routey.app", category: "Sync")

enum RouteySyncing {
  static func synchronize(reason: String, using syncEngine: SyncEngine) async {
    do {
      routeySyncLogger.info("sync start: \(reason, privacy: .public)")
      try await syncEngine.syncChanges()
      routeySyncLogger.info("sync complete: \(reason, privacy: .public)")
    } catch {
      routeySyncLogger.error(
        "sync failed: \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  static func sendChanges(reason: String, using syncEngine: SyncEngine) async {
    do {
      routeySyncLogger.info("send start: \(reason, privacy: .public)")
      try await syncEngine.sendChanges()
      routeySyncLogger.info("send complete: \(reason, privacy: .public)")
    } catch {
      routeySyncLogger.error(
        "send failed: \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
