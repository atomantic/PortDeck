import XCTest

final class PortOS_RecallUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SeedSampleData"]
        app.launch()

        // Verify Sessions tab is visible
        XCTAssertTrue(app.tabBars.buttons["Sessions"].exists)
        XCTAssertTrue(app.tabBars.buttons["Memories"].exists)
    }

    func testSessionsTabDisplaysSessions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SeedSampleData"]
        app.launch()

        // Sessions tab should be selected by default
        XCTAssertTrue(app.tabBars.buttons["Sessions"].isSelected)

        // Should show navigation title
        XCTAssertTrue(app.navigationBars["Sessions"].exists)
    }

    func testSwitchToMemoriesTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SeedSampleData"]
        app.launch()

        app.tabBars.buttons["Memories"].tap()
        XCTAssertTrue(app.navigationBars["Memories"].exists)
    }

    func testRecordButtonExists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SeedSampleData"]
        app.launch()

        // Record button should be in the toolbar
        XCTAssertTrue(app.buttons["Record"].exists)
    }

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launch()
        }
    }
}
