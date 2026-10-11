import XCTest
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import MacroStack

final class ProjectTests: XCTestCase {
    func testLegacySettingsPreserveCaptureGroupingAndNewSettingsRoundTrip() throws {
        let legacy = Data(#"{"mode":"Both","focusSteps":10,"framesPerPosition":3,"near":0.1,"far":0.8,"automaticFocus":false}"#.utf8)
        var settings = try JSONDecoder().decode(StackSettings.self, from: legacy)
        XCTAssertEqual(settings.repeats, 3)
        XCTAssertEqual(settings.totalFrames, 30)
        XCTAssertFalse(settings.automaticFocus)
        XCTAssertEqual(settings.captureQuality, .quality)
        XCTAssertEqual(settings.focusSpacing, .linear)
        settings.captureQuality = .balanced; settings.focusSpacing = .near
        let roundTrip = try JSONDecoder().decode(StackSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(roundTrip.captureQuality, .balanced)
        XCTAssertEqual(roundTrip.focusSpacing, .near)
        XCTAssertEqual(roundTrip.positions, settings.positions)
    }

    func testTwentyFrameSpacingRetainsEndpointsAndUniqueSubjectFocus() {
        for spacing in FocusSpacing.allCases {
            for center: Float in [0, 0.02, 0.5, 0.98, 1] {
                var settings = StackSettings()
                settings.focusSteps = 20; settings.focusSpacing = spacing
                settings.center(on: center)
                XCTAssertEqual(settings.positions.count, 20)
                XCTAssertEqual(Set(settings.positions).count, 20)
                XCTAssertEqual(settings.positions.first, center)
                XCTAssertEqual(settings.positions.min(), settings.near)
                XCTAssertEqual(settings.positions.max(), settings.far)
            }
        }
        var settings = StackSettings()
        settings.automaticFocus = false; settings.near = 0.1; settings.far = 0.9
        settings.focusSteps = 20; settings.focusSpacing = .near
        let values = settings.positions.sorted()
        XCTAssertLessThan(values[1] - values[0], (values[19] - values[18]) * 0.25)
    }

    func testExcludedFramesDoNotRegroupDifferentFocusPlanes() {
        let base = URL(fileURLWithPath: "/test-project")
        let frames = (1...6).map { SourceFrame(url: base.appendingPathComponent("frame-\($0).jpg"), number: $0, group: ($0 - 1) / 2) }
        let selection = Set([frames[0].url, frames[3].url, frames[5].url])
        let groups = ProjectFiles.groups(frames, including: selection)
        XCTAssertEqual(groups.map { $0.map(\.number) }, [[1], [4], [6]])
        XCTAssertTrue(ProjectFiles.groups(frames, including: []).isEmpty)
    }

    func testGalleryLoadsLegacyAndIncompleteProjectsWithoutInventingFrames() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("capture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"mode":"Both","framesPerPosition":2}"#.utf8).write(to: directory.appendingPathComponent("settings.json"))
        for index in [1, 3, 4] {
            try ProjectFiles.write(fixture(), to: directory.appendingPathComponent(String(format: "frame-%03d-focus-0.2000.jpg", index)))
        }
        let project = try XCTUnwrap(ProjectFiles.list(at: root).first)
        XCTAssertEqual(project.frames.map(\.number), [1, 3, 4])
        XCTAssertEqual(project.frames.map(\.group), [0, 1, 1])
        XCTAssertTrue(project.versions.isEmpty)
        XCTAssertTrue(project.canRestack)
        try ProjectFiles.write(fixture(), to: directory.appendingPathComponent("MacroStack.jpg"))
        let completed = try ProjectFiles.load(directory)
        XCTAssertEqual(completed.cover?.lastPathComponent, "MacroStack.jpg")
        XCTAssertEqual(completed.frames.count, 3)
    }

    func testSeparateVersionsPreserveSourceBytesAndDimensions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("MacroStack.jpg")
        try ProjectFiles.write(fixture(), to: source)
        let before = try Data(contentsOf: source)
        let first = try ProjectFiles.createVersion(from: source, in: directory, amount: 0.4, format: .jpeg)
        let second = try ProjectFiles.createVersion(from: source, in: directory, amount: 0, format: .jpeg)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, source)
        XCTAssertEqual(try Data(contentsOf: source), before)
        let image = try ProjectFiles.preview(first)
        XCTAssertEqual(image.width, 48)
        XCTAssertEqual(image.height, 32)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.appendingPathExtension("json").path))
        XCTAssertEqual(try ProjectFiles.load(directory).versions.count, 3)
    }

    func testHEICExportWhenEncoderIsAvailable() throws {
        let types = CGImageDestinationCopyTypeIdentifiers() as! [String]
        guard types.contains(UTType.heic.identifier) else { throw XCTSkip("This simulator does not expose a HEIC encoder.") }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.heic")
        try ProjectFiles.write(fixture(), to: url, format: .heic)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.heic.identifier)
        XCTAssertEqual(try ProjectFiles.preview(url).width, 48)
    }

    func testDetailAdjustmentPreservesFlatFieldAndExtent() throws {
        let input = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4))
            .cropped(to: CGRect(x: 5, y: 7, width: 48, height: 32))
        let edited = ProjectFiles.detailImage(input, amount: 1)
        XCTAssertEqual(edited.extent, input.extent)
        let context = CIContext()
        let before = context.createCGImage(input, from: input.extent)!.dataProvider!.data! as Data
        let after = context.createCGImage(edited, from: edited.extent)!.dataProvider!.data! as Data
        XCTAssertEqual(before.count, after.count)
        XCTAssertTrue(zip(before, after).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacroStack-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fixture() -> CGImage {
        let image = CIImage(color: CIColor(red: 0.35, green: 0.5, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 48, height: 32))
        return CIContext().createCGImage(image, from: image.extent)!
    }
}
