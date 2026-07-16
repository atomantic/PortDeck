import XCTest

final class PortDeckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNewCompanionShellLaunches() {
        let app = XCUIApplication()
        app.launchArguments = ["-UseInMemoryStore"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Fleet"].exists)
        XCTAssertTrue(app.tabBars.buttons["Capture"].exists)
        XCTAssertTrue(app.tabBars.buttons["Actions"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertTrue(app.navigationBars["PortOS Fleet"].exists)
        XCTAssertTrue(app.buttons["Add an instance"].exists)
    }

    func testCaptureExplainsMissingInstance() {
        let app = XCUIApplication()
        app.launchArguments = ["-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["Capture"].tap()

        XCTAssertTrue(app.navigationBars["Capture"].exists)
        XCTAssertTrue(app.staticTexts["Add an instance first"].exists)
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-UseInMemoryStore"]
            app.launch()
        }
    }
}
