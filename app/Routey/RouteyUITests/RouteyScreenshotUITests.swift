import XCTest

@MainActor
final class RouteyScreenshotUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testAppStoreScreenshots() throws {
    launchScreenshotApp()

    XCTAssertTrue(app.staticTexts["Routey Demo Loop"].waitForExistence(timeout: 10))
    captureScreenshot(named: "01-routes")

    tapCell(containing: "Routey Demo Loop")
    XCTAssertTrue(app.staticTexts["102 Example Ridge Road"].waitForExistence(timeout: 5))
    captureScreenshot(named: "02-route-stops")

    tapCell(containing: "102 Example Ridge Road")
    XCTAssertTrue(app.navigationBars["102 Example Ridge Road"].waitForExistence(timeout: 5))
    captureScreenshot(named: "03-stop-detail")

    goBack()
    goBack()
    app.buttons["Search"].tap()

    let searchField = app.searchFields.firstMatch
    XCTAssertTrue(searchField.waitForExistence(timeout: 5))
    searchField.tap()
    searchField.typeText("sample")
    XCTAssertTrue(app.staticTexts["202 Sample Cove Drive"].waitForExistence(timeout: 5))
    captureScreenshot(named: "04-search")
  }

  private func launchScreenshotApp() {
    app = XCUIApplication()
    setupSnapshot(app)
    app.launchArguments += [ScreenshotLaunchArgument.mode]
    app.launchEnvironment["ROUTEY_SCREENSHOT_MODE"] = "1"
    app.launchEnvironment["FASTLANE_SNAPSHOT"] = "1"
    app.launch()
  }

  private func captureScreenshot(named name: String) {
    snapshot(name, timeWaitingForIdle: 0)

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func tapCell(containing text: String) {
    let cell = app.cells.containing(.staticText, identifier: text).firstMatch
    XCTAssertTrue(cell.waitForExistence(timeout: 5))
    cell.tap()
  }

  private func goBack() {
    let backButton = app.navigationBars.buttons.element(boundBy: 0)
    XCTAssertTrue(backButton.waitForExistence(timeout: 5))
    backButton.tap()
  }
}

private enum ScreenshotLaunchArgument {
  static let mode = "--screenshot-mode"
}
