import XCTest

final class CameraUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCameraControlsStayReachableWithoutScrolling() {
        XCTAssertTrue(app.frame.contains(app.buttons["shutterButton"].frame))
        XCTAssertTrue(app.buttons["projectsButton"].isHittable)
        XCTAssertTrue(app.buttons["settingsButton"].isHittable)
        XCTAssertFalse(app.buttons["shutterButton"].isEnabled)
        XCTAssertFalse(app.buttons["flashlightButton"].isEnabled)
        app.buttons["modePhoto"].tap()
        screenshot("Camera-screen")
    }

    func testSettingsOpenAndCloseWithoutLosingCameraScreen() {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Capture settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Full resolution"].exists)
        screenshot("Capture-settings")
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.buttons["shutterButton"].waitForExistence(timeout: 5))
    }

    func testProjectsAreOneTapAway() {
        app.buttons["projectsButton"].tap()
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))
        screenshot("Projects-empty")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["shutterButton"].waitForExistence(timeout: 5))
    }
}
