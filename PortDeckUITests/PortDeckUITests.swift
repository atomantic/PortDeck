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
        XCTAssertTrue(app.buttons["Explore Demo"].exists)
    }

    func testOfflineDemoCanBeEnteredAndExited() {
        let app = XCUIApplication()
        app.launchArguments = ["-UseInMemoryStore"]
        app.launch()

        let exploreDemo = app.buttons["Explore Demo"]
        XCTAssertTrue(exploreDemo.waitForExistence(timeout: 3))
        exploreDemo.tap()

        XCTAssertTrue(app.staticTexts["Offline Demo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Atlas Studio"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["Add an instance"].waitForExistence(timeout: 3))
    }

    func testOfflineDemoCanBeEnteredFromSettingsWithoutLogin() {
        let app = XCUIApplication()
        app.launchArguments = ["-UseInMemoryStore"]
        app.launch()
        app.tabBars.element(boundBy: 0).buttons["Settings"].tap()

        let exploreDemo = app.buttons["Explore offline demo"]
        app.swipeUp()
        XCTAssertTrue(exploreDemo.waitForExistence(timeout: 3))
        exploreDemo.tap()

        XCTAssertTrue(app.staticTexts["Offline Demo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Atlas Studio"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].exists)

        app.tabBars.element(boundBy: 0).buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Unavailable in offline demo"].waitForExistence(timeout: 3))
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
