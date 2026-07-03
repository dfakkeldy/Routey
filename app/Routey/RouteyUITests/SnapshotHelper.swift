import Foundation
import XCTest

@MainActor
func setupSnapshot(_ app: XCUIApplication, waitForAnimations: Bool = true) {
  Snapshot.setup(app, waitForAnimations: waitForAnimations)
}

@MainActor
func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20) {
  Snapshot.capture(name, timeWaitingForIdle: timeout)
}

@MainActor
private enum Snapshot {
  private static var app: XCUIApplication?
  private static var waitForAnimations = true

  static func setup(_ app: XCUIApplication, waitForAnimations: Bool = true) {
    self.app = app
    self.waitForAnimations = waitForAnimations

    guard let cacheDirectory else { return }

    if let language = read(cacheDirectory.appending(path: "language.txt")) {
      app.launchArguments += ["-AppleLanguages", "(\(language))"]
    }

    if let locale = read(cacheDirectory.appending(path: "locale.txt")) {
      app.launchArguments += ["-AppleLocale", locale]
    }

    app.launchArguments += ["-FASTLANE_SNAPSHOT", "YES", "-ui_testing"]
    app.launchArguments += launchArguments(from: cacheDirectory.appending(path: "snapshot-launch_arguments.txt"))
  }

  static func capture(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20) {
    if timeout > 0 {
      _ = XCTWaiter.wait(for: [], timeout: timeout)
    }

    if waitForAnimations {
      Thread.sleep(forTimeInterval: 1)
    }

    guard
      let screenshotsDirectory,
      var simulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
    else { return }

    do {
      try FileManager.default.createDirectory(
        at: screenshotsDirectory,
        withIntermediateDirectories: true
      )

      simulator = simulator.removingSimulatorClonePrefix
      let path = screenshotsDirectory.appending(path: "\(simulator)-\(name).png")
      try XCUIScreen.main.screenshot().pngRepresentation.write(to: path, options: .atomic)
    } catch {
      XCTFail("Could not write screenshot '\(name)': \(error)")
    }
  }

  private static var cacheDirectory: URL? {
    guard let simulatorHostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else {
      return nil
    }

    return URL(fileURLWithPath: simulatorHostHome)
      .appending(path: "Library")
      .appending(path: "Caches")
      .appending(path: "tools.fastlane")
  }

  private static var screenshotsDirectory: URL? {
    cacheDirectory?.appending(path: "screenshots")
  }

  private static func read(_ url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func launchArguments(from url: URL) -> [String] {
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
      return []
    }

    var arguments = [String]()
    var current = ""
    var isInsideQuotes = false

    for character in contents {
      if character == "\"" {
        isInsideQuotes.toggle()
      } else if character.isWhitespace && !isInsideQuotes {
        if !current.isEmpty {
          arguments.append(current)
          current = ""
        }
      } else {
        current.append(character)
      }
    }

    if !current.isEmpty {
      arguments.append(current)
    }

    return arguments
  }
}

private extension String {
  var removingSimulatorClonePrefix: String {
    guard hasPrefix("Clone "), let range = range(of: " of ") else {
      return self
    }

    return String(self[range.upperBound...])
  }
}

// SnapshotHelperVersion [1.30]
