import XCTest
import CoreImage
import simd
import Vision
@testable import MacroStack

final class StackEngineTests: XCTestCase {
    func testNoiseAverageUsesLinearLight() throws {
        let engine = try StackEngine(maximumDimension: 64, registerImages: false, protectMotion: false)
        try engine.add(image: solid(0))
        try engine.add(image: solid(255))
        try engine.finishGroup()
        let values = bytes(try engine.outputImage())
        // Average of black and white in linear light is about 188 in sRGB, not 128.
        XCTAssertEqual(Int(values[0]), 188, accuracy: 4)
        XCTAssertEqual(values[0], values[1])
        XCTAssertEqual(engine.frameCount, 2)
    }

    func testAveragingReducesDeterministicNoise() throws {
        let engine = try StackEngine(maximumDimension: 64, registerImages: false)
        // Anticorrelated noise gives a stringent check that both captures are used.
        for invert in [false, true] {
            let input = fixture(size: 64) { x, y in
                let positive = ((x * 17 + y * 31) % 2 == 0) != invert
                return positive ? 143 : 113
            }
            try engine.add(image: input)
        }
        try engine.finishGroup()
        let values = bytes(try engine.outputImage())
        let errors = stride(from: 0, to: values.count, by: 4).map { abs(Double(values[$0]) - 128) }
        XCTAssertLessThan(errors.reduce(0, +) / Double(errors.count), 3)
    }

    func testFocusFusionRecoversDetailFromBothPlanes() throws {
        let size = 128
        let truth = fixture(size: size) { x, y in ((x / 4 + y / 4) % 2 == 0) ? 220 : 30 }
        let blurred = truth.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3]).cropped(to: truth.extent)
        let left = truth.cropped(to: CGRect(x: 0, y: 0, width: size / 2, height: size))
            .composited(over: blurred).cropped(to: truth.extent)
        let right = truth.cropped(to: CGRect(x: size / 2, y: 0, width: size / 2, height: size))
            .composited(over: blurred).cropped(to: truth.extent)
        let engine = try StackEngine(maximumDimension: size, registerImages: false)
        try engine.add(image: left)
        try engine.finishGroup()
        try engine.add(image: right)
        try engine.finishGroup()
        let final = bytes(try engine.outputImage())
        let expected = bytes(render(truth))
        let first = bytes(render(left))
        let second = bytes(render(right))
        let leftRegion = 8..<56
        let rightRegion = 72..<120
        XCTAssertLessThan(error(final, expected, width: size, columns: leftRegion), error(second, expected, width: size, columns: leftRegion) * 0.6)
        XCTAssertLessThan(error(final, expected, width: size, columns: rightRegion), error(first, expected, width: size, columns: rightRegion) * 0.6)
    }

    func testRegistrationDirectionForKnownShift() throws {
        let reference = fixture(size: 256) { x, y in
            // Deterministic texture with nonrepeating structure for Vision registration.
            let value = ((x / 3) &* 73856093) ^ ((y / 3) &* 19349663)
            return UInt8(truncatingIfNeeded: value)
        }
        let engine = try StackEngine(maximumDimension: 256)
        try engine.add(image: reference)
        let shifted = reference.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: 3, y: -2))
            .cropped(to: reference.extent)
        let correction = try engine.alignment(for: shifted)
        XCTAssertEqual(correction.tx, -3, accuracy: 0.6)
        XCTAssertEqual(correction.ty, 2, accuracy: 0.6)
        let aligned = try engine.register(shifted)
        XCTAssertLessThan(error(bytes(render(aligned.image, in: reference.extent)), bytes(render(reference)), width: 256, columns: 16..<240), 12, alignmentDiagnostic(shifted, reference))
        try engine.add(image: shifted)
        try engine.finishGroup()
        let result = try engine.outputImage()
        XCTAssertLessThan(result.width, 256)
        XCTAssertLessThan(result.height, 256)
    }

    func testUnfinishedGroupCannotBeExported() throws {
        let engine = try StackEngine(maximumDimension: 64, registerImages: false)
        XCTAssertThrowsError(try engine.outputImage())
        try engine.add(image: solid(100))
        XCTAssertThrowsError(try engine.outputImage())
        try engine.finishGroup()
        XCTAssertNoThrow(try engine.outputImage())
    }

    func testOutputResolutionCap() throws {
        let engine = try StackEngine(maximumDimension: 32, registerImages: false)
        try engine.add(image: solid(128))
        try engine.finishGroup()
        let output = try engine.outputImage()
        XCTAssertEqual(output.width, 32)
        XCTAssertEqual(output.height, 32)
    }

    func testSofterRepeatDoesNotBlurSharpFrame() throws {
        let sharp = fixture(size: 128) { x, y in ((x / 4 + y / 4) % 2 == 0) ? 220 : 30 }
        let blurred = sharp.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3]).cropped(to: sharp.extent)
        let engine = try StackEngine(maximumDimension: 128, registerImages: false)
        XCTAssertTrue(try engine.add(image: sharp))
        XCTAssertFalse(try engine.add(image: blurred))
        try engine.finishGroup()
        XCTAssertEqual(engine.rejectedFrames, 1)
        XCTAssertLessThan(error(bytes(try engine.outputImage()), bytes(render(sharp)), width: 128, columns: 8..<120), 2)
    }

    func testMovingPatchIsNotAveragedIntoReference() throws {
        let original = fixture(size: 128) { x, y in ((x / 3 + y / 3) % 2 == 0) ? 120 : 60 }
        let moving = fixture(size: 128) { x, y in
            if (48..<64).contains(x) && (48..<64).contains(y) { return 250 }
            return ((x / 3 + y / 3) % 2 == 0) ? 120 : 60
        }
        let engine = try StackEngine(maximumDimension: 128, registerImages: false)
        try engine.add(image: original)
        try engine.add(image: moving)
        try engine.finishGroup()
        let actual = bytes(try engine.outputImage())
        let expected = bytes(render(original))
        XCTAssertLessThan(error(actual, expected, width: 128, columns: 50..<62), 3)
    }

    func testPerspectiveRegistrationCorrectsScaleAndRotation() throws {
        let size = 256
        let reference = fixture(size: size) { x, y in
            UInt8(truncatingIfNeeded: ((x / 5) &* 73856093) ^ ((y / 5) &* 19349663))
        }
        let transform = CGAffineTransform(translationX: -128, y: -128)
            .concatenating(CGAffineTransform(scaleX: 1.035, y: 1.035))
            .concatenating(CGAffineTransform(rotationAngle: 0.018))
            .concatenating(CGAffineTransform(translationX: 130, y: 126))
        let moving = reference.clampedToExtent().transformed(by: transform).cropped(to: reference.extent)
        let engine = try StackEngine(maximumDimension: size)
        try engine.add(image: reference)
        let registered = try engine.register(moving)
        let truth = bytes(render(reference))
        let initialError = error(bytes(render(moving)), truth, width: size, columns: 32..<224)
        let correctedError = error(bytes(render(registered.image, in: reference.extent)), truth, width: size, columns: 32..<224)
        XCTAssertEqual(engine.translationFallbacks, 0)
        XCTAssertLessThan(correctedError, initialError * 0.65, alignmentDiagnostic(moving, reference))
    }

    func testInvalidWarpIsRejected() throws {
        let image = solid(100)
        var matrix = matrix_identity_float3x3
        matrix.columns.2.x = 1000
        XCTAssertThrowsError(try ImageAlignment.warp(image, matrix: matrix, registrationScale: 1))
        matrix.columns.2.x = .nan
        XCTAssertThrowsError(try ImageAlignment.warp(image, matrix: matrix, registrationScale: 1))
    }

    func testRegistrationScaleConvertsThumbnailPixelsToFullSize() throws {
        let reference = fixture(size: 128) { x, y in UInt8(truncatingIfNeeded: x * 31 ^ y * 17) }
        let shifted = reference.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: 4, y: -2)).cropped(to: reference.extent)
        var matrix = matrix_identity_float3x3
        matrix.columns.2 = SIMD3(-2, 1, 1)
        let aligned = try ImageAlignment.warp(shifted, matrix: matrix, registrationScale: 0.5)
        XCTAssertLessThan(error(bytes(render(aligned.image, in: reference.extent)), bytes(render(reference)), width: 128, columns: 8..<120), 2)
        XCTAssertEqual(aligned.validRect.maxX, 124, accuracy: 0.01)
        XCTAssertEqual(aligned.validRect.minY, 2, accuracy: 0.01)
    }

    func testComparisonUsesIdenticalCrop() throws {
        let image = fixture(size: 128) { x, y in UInt8(truncatingIfNeeded: x * 31 ^ y * 17) }
        let engine = try StackEngine(maximumDimension: 128, registerImages: false)
        try engine.add(image: image)
        try engine.finishGroup()
        let output = try engine.outputImage()
        let reference = try engine.referenceImage()
        XCTAssertEqual(output.width, reference.width)
        XCTAssertEqual(output.height, reference.height)
        XCTAssertLessThan(error(bytes(output), bytes(reference), width: 128, columns: 8..<120), 2)
    }

    func testAutomaticSweepStartsAtFocusedSubjectAndStaysInRange() {
        for center: Float in [0, 0.02, 0.5, 0.98, 1] {
            var settings = StackSettings()
            settings.center(on: center)
            XCTAssertEqual(settings.positions.first, center)
            XCTAssertEqual(settings.positions.count, settings.focusSteps)
            XCTAssertTrue(settings.positions.allSatisfy { (0...1).contains($0) })
            XCTAssertEqual(Set(settings.positions).count, settings.focusSteps)
        }
    }

    func testSingleModeTakesOneFullResolutionPhoto() {
        var settings = StackSettings()
        settings.mode = .single
        settings.center(on: 0.72)
        XCTAssertEqual(settings.totalFrames, 1)
        XCTAssertEqual(settings.positions, [0.72])
        XCTAssertEqual(settings.maximumDimension, 4096)
    }

    func testSubjectRegionChoosesSharpInsectOverSharpBackground() throws {
        let truth = fixture(size: 128) { x, y in ((x / 3 + y / 3) % 2 == 0) ? 220 : 30 }
        let blurred = truth.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3]).cropped(to: truth.extent)
        let subject = CGRect(x: 48, y: 48, width: 32, height: 32)
        let sharpBackground = blurred.cropped(to: subject).composited(over: truth).cropped(to: truth.extent)
        let sharpInsect = truth.cropped(to: subject).composited(over: blurred).cropped(to: truth.extent)
        let engine = try StackEngine(maximumDimension: 128, subjectRegion: CGRect(x: 0.375, y: 0.375, width: 0.25, height: 0.25), bestFrameOnly: true)
        try engine.add(image: sharpBackground)
        try engine.add(image: sharpInsect)
        XCTAssertEqual(engine.bestFrameIndex, 1)
        XCTAssertLessThan(error(bytes(try engine.outputImage()), bytes(render(sharpInsect)), width: 128, columns: 8..<120), 2)
    }

    func testBurstNeverAlignsBlendsOrCropsMovingSubject() throws {
        let first = fixture(size: 128) { x, y in UInt8(truncatingIfNeeded: x * 31 ^ y * 17) }
        let second = first.clampedToExtent().transformed(by: CGAffineTransform(translationX: 40, y: 24)).cropped(to: first.extent)
        let engine = try StackEngine(maximumDimension: 128, bestFrameOnly: true)
        try engine.add(image: first)
        try engine.add(image: second)
        try engine.finishGroup()
        let output = try engine.outputImage()
        XCTAssertEqual(output.width, 128)
        XCTAssertEqual(output.height, 128)
        XCTAssertEqual(engine.frameCount, 2)
        XCTAssertEqual(engine.rejectedFrames, 0)
        XCTAssertEqual(engine.translationFallbacks, 0)
        let chosen = engine.bestFrameIndex == 0 ? first : second
        XCTAssertLessThan(error(bytes(output), bytes(render(chosen)), width: 128, columns: 8..<120), 2)
    }

    func testInsectPresetsAndSubjectRegionAtEdges() {
        var settings = StackSettings()
        settings.useStillInsectPreset()
        XCTAssertEqual(settings.mode, .focus)
        XCTAssertEqual(settings.totalFrames, 9)
        XCTAssertEqual(settings.repeats, 1)
        XCTAssertEqual(settings.focusSpan, 0.06)
        settings.useMovingInsectPreset()
        XCTAssertEqual(settings.mode, .burst)
        XCTAssertEqual(settings.totalFrames, 5)
        XCTAssertEqual(settings.positions.count, 1)
        XCTAssertEqual(settings.timerSeconds, 0)
        XCTAssertTrue(settings.keepOriginals)
        for point in [0.0, 0.01, 0.5, 0.99, 1.0] {
            settings.subjectX = point; settings.subjectY = 1 - point
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(settings.subjectRegion))
            XCTAssertEqual(settings.subjectRegion.width, 0.24, accuracy: 0.0001)
        }
    }

    func testShortShutterCompensatesISOAndReportsInsufficientLight() throws {
        let plan = try ExposurePlan.make(meteredSeconds: 1.0 / 50, meteredISO: 100, denominator: 500,
            minimumSeconds: 1.0 / 10000, maximumSeconds: 1, minimumISO: 25, maximumISO: 1600)
        XCTAssertEqual(plan.seconds, 1.0 / 500, accuracy: 0.000001)
        XCTAssertEqual(plan.iso, 1000, accuracy: 0.01)
        XCTAssertFalse(plan.needsMoreLight)
        let dark = try ExposurePlan.make(meteredSeconds: 1.0 / 30, meteredISO: 800, denominator: 1000,
            minimumSeconds: 1.0 / 10000, maximumSeconds: 1, minimumISO: 25, maximumISO: 1600)
        XCTAssertEqual(dark.iso, 1600)
        XCTAssertTrue(dark.needsMoreLight)
    }

    func testShutterRespectsHardwareLimitsAndRejectsInvalidMetering() throws {
        let plan = try ExposurePlan.make(meteredSeconds: 1.0 / 500, meteredISO: 25, denominator: 2000,
            minimumSeconds: 1.0 / 1000, maximumSeconds: 1.0 / 30, minimumISO: 50, maximumISO: 1600)
        XCTAssertEqual(plan.seconds, 1.0 / 1000, accuracy: 0.000001)
        XCTAssertEqual(plan.iso, 50)
        XCTAssertThrowsError(try ExposurePlan.make(meteredSeconds: .nan, meteredISO: 100, denominator: 500,
            minimumSeconds: 1.0 / 1000, maximumSeconds: 1, minimumISO: 25, maximumISO: 1600))
    }

    private func solid(_ value: UInt8) -> CIImage { fixture(size: 64) { _, _ in value } }

    private func alignmentDiagnostic(_ moving: CIImage, _ reference: CIImage) -> String {
        let request = VNHomographicImageRegistrationRequest(targetedCIImage: moving, options: [:])
        do {
            try VNImageRequestHandler(ciImage: reference, options: [:]).perform([request])
            guard let matrix = request.results?.first?.warpTransform else { return "No homography" }
            let flip = simd_float3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, -1, 0), SIMD3(0, Float(reference.extent.height), 1)))
            var details = "Vision matrix: \(matrix)"
            for (name, candidate) in [("forward", matrix), ("inverse", simd_inverse(matrix)), ("flip", flip * matrix * flip), ("inverseFlip", flip * simd_inverse(matrix) * flip)] {
                if let aligned = try? ImageAlignment.warp(moving, matrix: candidate, registrationScale: 1) {
                    let difference = error(bytes(render(aligned.image, in: reference.extent)), bytes(render(reference)), width: Int(reference.extent.width), columns: 32..<224)
                    details += " \(name): \(difference)"
                }
            }
            return details
        } catch { return "Diagnostic failed: \(error)" }
    }

    private func fixture(size: Int, pixel: (Int, Int) -> UInt8) -> CIImage {
        var data = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let value = pixel(x, y)
                let offset = (y * size + x) * 4
                data[offset] = value; data[offset + 1] = value; data[offset + 2] = value
            }
        }
        return CIImage(bitmapData: Data(data), bytesPerRow: size * 4,
                       size: CGSize(width: size, height: size), format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    private func render(_ image: CIImage, in bounds: CGRect? = nil) -> CGImage {
        // Registration changes image extent. Preserve the fixed reference canvas when
        // comparing pixels, so both byte buffers have the same origin and row stride.
        CIContext().createCGImage(image, from: bounds ?? image.extent, format: .RGBA8,
                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    private func error(_ actual: [UInt8], _ expected: [UInt8], width: Int, columns: Range<Int>) -> Double {
        var sum = 0.0
        var count = 0
        for y in 8..<(width - 8) {
            for x in columns {
                let index = (y * width + x) * 4
                sum += abs(Double(actual[index]) - Double(expected[index]))
                count += 1
            }
        }
        return sum / Double(count)
    }
}
