import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    private static let projectDirectory: String = {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }()

    private lazy var configuration: [String: String] = {
        let paths = [
            "\(Self.projectDirectory)/.screenshot_config.json",
            "/tmp/portdeck_screenshot_config.json"
        ]
        for path in paths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                return dictionary
            }
        }
        return [:]
    }()

    private var deviceType: String { configuration["device"] ?? "iphone_6.9" }
    private var outputDirectory: String {
        configuration["output_dir"] ?? "\(Self.projectDirectory)/screenshots"
    }
    private var targetScreen: String? {
        guard let screen = configuration["target_screen"], !screen.isEmpty else { return nil }
        return screen
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [DemoModeLaunchArgument.value]
        app.launch()
        XCTAssertTrue(app.navigationBars["PortOS Fleet"].waitForExistence(timeout: 5))
    }

    func testCaptureIPhoneScreenshots() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        try captureAppStoreScreenshots()
    }

    func testCaptureIPadScreenshots() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        try captureAppStoreScreenshots()
    }

    private func captureAppStoreScreenshots() throws {
        saveScreenshot("01_fleet")

        let studio = app.staticTexts["Atlas Studio"].firstMatch
        XCTAssertTrue(studio.waitForExistence(timeout: 4))
        studio.tap()
        XCTAssertTrue(app.staticTexts["Federation"].waitForExistence(timeout: 4))
        saveScreenshot("02_federation")

        selectTab("Capture")
        XCTAssertTrue(app.navigationBars["Capture"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Send"].waitForExistence(timeout: 2))
        saveScreenshot("03_capture")

        selectTab("Actions")
        XCTAssertTrue(app.staticTexts["Recent Brain entries"].waitForExistence(timeout: 5))
        saveScreenshot("04_actions")

        app.staticTexts["Recent Brain entries"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Recent Brain entries"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Last 5 captures."].waitForExistence(timeout: 5))
        saveScreenshot("05_action_results")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let focusSession = app.staticTexts["Start Focus Session"].firstMatch
        XCTAssertTrue(focusSession.waitForExistence(timeout: 4))
        scrollUntilHittable(focusSession)
        focusSession.tap()
        XCTAssertTrue(app.navigationBars["Start Focus Session"].waitForExistence(timeout: 4))
        saveScreenshot("06_action_form")

        selectTab("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))
        if UIDevice.current.userInterfaceIdiom == .phone {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
        }
        saveScreenshot("07_privacy")
    }

    /// The action list grows as PortOS adds palette entries, so scroll rather than assume
    /// a row sits above the fold.
    private func scrollUntilHittable(_ element: XCUIElement, attempts: Int = 5) {
        for _ in 0..<attempts where !element.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func selectTab(_ name: String) {
        let tabButton = app.tabBars.buttons[name]
        if tabButton.waitForExistence(timeout: 2) {
            tabButton.tap()
            return
        }
        let button = app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing \(name) tab")
        button.tap()
    }

    private func saveScreenshot(_ name: String) {
        if let targetScreen, targetScreen != name { return }

        // Let navigation and liquid-glass tab transitions finish before rasterizing.
        Thread.sleep(forTimeInterval: 0.8)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(deviceType)_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = "\(outputDirectory)/en/\(deviceType)"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(
            to: URL(fileURLWithPath: "\(directory)/\(name).png"),
            options: .atomic
        )
    }
}

/// UI-test bundles cannot import the app target, so keep the launch contract in one tiny mirror.
private enum DemoModeLaunchArgument {
    static let value = "-demo-data"
}
