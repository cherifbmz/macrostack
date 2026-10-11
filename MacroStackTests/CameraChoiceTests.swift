import XCTest
@testable import MacroStack

final class CameraChoiceTests: XCTestCase {
    func testFixedFocusCameraStillSupportsPhotosAndNoiseReduction() {
        let camera = CameraChoice(id: "front", title: "Front", subtitle: "Front", supportsFocusStack: false, supportsCustomExposure: false, hasTorch: false)
        XCTAssertTrue(camera.supports(.single))
        XCTAssertTrue(camera.supports(.clean))
        XCTAssertFalse(camera.supports(.focus))
        XCTAssertFalse(camera.supports(.both))
        XCTAssertFalse(camera.supports(.burst))
    }

    func testFocusAndBurstCapabilitiesAreIndependent() {
        let fixed = CameraChoice(id: "a", title: "A", subtitle: "A", supportsFocusStack: false, supportsCustomExposure: true, hasTorch: false)
        XCTAssertTrue(fixed.supports(.burst))
        XCTAssertFalse(fixed.supports(.focus))
        let manual = CameraChoice(id: "b", title: "B", subtitle: "B", supportsFocusStack: true, supportsCustomExposure: false, hasTorch: true)
        XCTAssertTrue(manual.supports(.focus))
        XCTAssertTrue(manual.supports(.both))
        XCTAssertFalse(manual.supports(.burst))
    }

    func testHardwareSnapshotResolvesSelectedLensWithoutAssumingArrayOrder() {
        let front = CameraChoice(id: "front", title: "Front", subtitle: "Front", supportsFocusStack: false, supportsCustomExposure: false, hasTorch: false)
        let rear = CameraChoice(id: "rear", title: "1×", subtitle: "Main", supportsFocusStack: true, supportsCustomExposure: true, hasTorch: true)
        let state = CameraHardwareState(cameras: [front, rear], selectedID: "rear", torchAvailable: false, torchLevel: 0)
        XCTAssertEqual(state.selected, rear)
        XCTAssertFalse(state.torchAvailable) // Having hardware doesn't imply current torch availability.
        XCTAssertNil(CameraHardwareState(cameras: [front], selectedID: "missing", torchAvailable: false, torchLevel: 0).selected)
    }

    func testSimpleModeLabelsRetainAdvancedProcessingChoices() {
        XCTAssertEqual(ShootingStyle.selected(for: .focus), .still)
        XCTAssertEqual(ShootingStyle.selected(for: .both), .still)
        XCTAssertEqual(ShootingStyle.selected(for: .clean), .still)
        XCTAssertEqual(ShootingStyle.selected(for: .burst), .moving)
        XCTAssertEqual(ShootingStyle.selected(for: .single), .photo)
    }
}
