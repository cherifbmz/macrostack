import XCTest
import UIKit
@testable import MacroStack

@MainActor
final class PreviewHitTests: XCTestCase {
    func testMagnificationKeepsNativeHitAreaInsideViewport() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let button = UIButton(frame: CGRect(x: 270, y: 10, width: 48, height: 48))
        let preview = CameraPreview.PreviewView(frame: CGRect(x: 16, y: 80, width: 358, height: 478))
        root.addSubview(button)
        root.addSubview(preview)
        for zoom: CGFloat in [1, 2] {
            preview.magnification = zoom
            preview.layoutIfNeeded()
            XCTAssertTrue(root.hitTest(CGPoint(x: 294, y: 34), with: nil) === button)
            XCTAssertTrue(root.hitTest(CGPoint(x: 195, y: 300), with: nil) === preview)
            XCTAssertFalse(preview.point(inside: CGPoint(x: 278, y: -46), with: nil))
            XCTAssertEqual(preview.bounds.size, CGSize(width: 358, height: 478))
            XCTAssertEqual(preview.previewLayer.bounds.width, 358 * zoom, accuracy: 0.001)
        }
    }

    func testMagnifiedLayerCoordinatesKeepSubjectPositionCentered() {
        let preview = CameraPreview.PreviewView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        preview.magnification = 2
        preview.layoutIfNeeded()
        let center = preview.previewLayer.convert(CGPoint(x: 150, y: 200), from: preview.layer)
        XCTAssertEqual(center.x, 300, accuracy: 0.001)
        XCTAssertEqual(center.y, 400, accuracy: 0.001)
        let visibleCorner = preview.previewLayer.convert(CGPoint.zero, from: preview.layer)
        XCTAssertEqual(visibleCorner.x, 150, accuracy: 0.001)
        XCTAssertEqual(visibleCorner.y, 200, accuracy: 0.001)
        let roundTrip = preview.layer.convert(visibleCorner, from: preview.previewLayer)
        XCTAssertEqual(roundTrip.x, 0, accuracy: 0.001)
        XCTAssertEqual(roundTrip.y, 0, accuracy: 0.001)
    }
}
