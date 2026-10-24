import XCTest

final class CaptureComposerUITests: XCTestCase {
    func testAcceptedCaptureKeepsOriginalDestinationVisibleAfterSwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo-data"]
        app.launch()
        app.tabBars.buttons["Capture"].tap()

        let send = app.buttons["Send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        if !send.isHittable { app.swipeUp() }
        send.tap()

        let receipt = app.staticTexts["Accepted by Atlas Studio · Brain"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        let editor = app.textViews.firstMatch
        XCTAssertEqual(editor.value as? String, "")

        app.swipeDown()
        app.buttons["Daily Log"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        if !receipt.isHittable { app.swipeUp() }
        XCTAssertTrue(receipt.exists)
    }
}
