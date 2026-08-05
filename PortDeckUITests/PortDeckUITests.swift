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

    func testReaderActionRendersEntriesOnOpenAndPagesOnDemand() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo-data"]
        app.launch()
        app.tabBars.buttons["Actions"].tap()

        let recentEntries = app.staticTexts["Recent Brain entries"].firstMatch
        XCTAssertTrue(recentEntries.waitForExistence(timeout: 5))
        recentEntries.tap()

        // The page fetches on open — no form to fill, and the entries render, not just the summary.
        XCTAssertTrue(app.staticTexts["Federation rollout: mirror the field kit before the demo, not after."]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Last 5 captures."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Jul 16, 2026"].firstMatch.exists)

        // Scrolling past the last entry widens the window.
        let sixthEntry = app.staticTexts["Draft a one-page brief on what the companion should never do offline."]
        XCTAssertFalse(sixthEntry.exists)
        for _ in 0..<4 where !sixthEntry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(sixthEntry.waitForExistence(timeout: 8))
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-UseInMemoryStore"]
            app.launch()
        }
    }
}
