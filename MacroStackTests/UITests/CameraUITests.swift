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

    private func launchPreviewFixture(unavailableTorch: Bool = false) {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-preview-interaction-testing"]
        if unavailableTorch { app.launchArguments.append("-torch-unavailable-testing") }
        app.launch()
        XCTAssertTrue(app.buttons["magnifyPreviewButton"].waitForExistence(timeout: 10))
    }

    private func assertFocusTaps(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.staticTexts["captureStatus"].label, "Preview test · Focus taps: \(count)", file: file, line: line)
    }

    func testFlashlightDoesNotFocusPreviewAtNormalOrMagnifiedSize() {
        launchPreviewFixture()
        let preview = app.descendants(matching: .any)["cameraPreview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        // Prove the actual UIKit gesture recognizer is active, even without video hardware.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertFocusTaps(1)
        let light = app.buttons["flashlightButton"]
        for magnified in [false, true] {
            if magnified { app.buttons["magnifyPreviewButton"].tap() }
            assertFocusTaps(1)
            // Tap physical screen coordinates, including padding around the icon.
            light.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertEqual(light.value as? String, "On")
            assertFocusTaps(1)
            light.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
            XCTAssertEqual(light.value as? String, "Off")
            assertFocusTaps(1)
        }
        screenshot("Flashlight-hit-region-magnified")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertFocusTaps(2)
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Capture settings"].waitForExistence(timeout: 5))
        app.buttons["settingsDone"].tap()
        assertFocusTaps(2)
    }

    func testUnavailableFlashlightDoesNotPassTouchesToMagnifiedPreview() {
        launchPreviewFixture(unavailableTorch: true)
        app.buttons["magnifyPreviewButton"].tap()
        let light = app.buttons["flashlightButton"]
        XCTAssertFalse(light.isEnabled)
        light.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertFocusTaps(0)
        let preview = app.descendants(matching: .any)["cameraPreview"].firstMatch
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertFocusTaps(1)
    }

}
