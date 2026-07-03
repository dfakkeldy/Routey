import Foundation
import RouteyDomain
import RouteyImport
import SQLiteData

enum ScreenshotMode {
  static let launchArgument = "--screenshot-mode"

  static var isEnabled: Bool {
    CommandLine.arguments.contains(launchArgument)
      || ProcessInfo.processInfo.environment["ROUTEY_SCREENSHOT_MODE"] == "1"
      || ProcessInfo.processInfo.environment["FASTLANE_SNAPSHOT"] == "1"
  }

  static func configuredDatabase() throws -> any DatabaseWriter {
    let databaseURL = URL.temporaryDirectory.appending(path: "RouteyScreenshotMode.sqlite")
    try removeExistingDatabase(at: databaseURL)

    let database = try routeyDatabase(path: databaseURL.path())
    _ = try RouteImporter.importRoute(
      named: "Routey Demo Loop",
      from: sampleRoute,
      into: database
    )
    return database
  }

  private static func removeExistingDatabase(at url: URL) throws {
    let fileManager = FileManager.default
    for suffix in ["", "-shm", "-wal"] {
      let fileURL = URL(fileURLWithPath: url.path() + suffix)
      if fileManager.fileExists(atPath: fileURL.path) {
        try fileManager.removeItem(at: fileURL)
      }
    }
  }

  private static var sampleRoute: ParseResult {
    ParseResult(
      stops: [
        ParsedStop(
          tieOut: "Case A",
          civicNumber: 102,
          street: "Example Ridge Road",
          occupantName: "Alex Example",
          notes: "Parcel shelf marker",
          sourceLine: 1
        ),
        ParsedStop(
          tieOut: "Case A",
          civicNumber: 118,
          street: "Example Ridge Road",
          occupantName: "Jordan Sample",
          notes: "Shared roadside box",
          sourceLine: 2
        ),
        ParsedStop(
          tieOut: "Case B",
          civicNumber: 202,
          street: "Sample Cove Drive",
          occupantName: "Taylor Placeholder",
          notes: "Door delivery note",
          sourceLine: 3
        ),
        ParsedStop(
          tieOut: "Case C",
          civicNumber: 44,
          street: "Demo Orchard Lane",
          occupantName: "Morgan Fixture",
          notes: "Oversize parcel",
          sourceLine: 4
        ),
      ]
    )
  }
}
