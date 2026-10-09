import CoreImage
import ImageIO
import Vision

/// A streaming, linear-light prototype. Only a few rendered frames are retained.
/// Translation registration assumes a supported phone and a stationary subject.
final class StackEngine {
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let maximumDimension: Int
    private let registerImages: Bool
    private let selectionKernel: CIColorKernel
    private var reference: CIImage?
    private var registrationReference: CIImage?
    private var registrationScale: CGFloat = 1
    private var commonRect = CGRect.zero
    private var mean: CIImage?
    private var groupCount = 0
    private var fused: CIImage?
    private var bestScore: CIImage?
    private(set) var frameCount = 0
    private(set) var groupTotal = 0

    init(maximumDimension: Int, registerImages: Bool = true) throws {
        self.maximumDimension = maximumDimension
        self.registerImages = registerImages
        context = CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ])
        guard let kernel = CIColorKernel(source: """
            kernel vec4 chooseSharper(__sample candidate, __sample previous) {
                float threshold = max(previous.r * 1.08, previous.r + 0.002);
                float pick = step(threshold, candidate.r);
                return vec4(pick, pick, pick, 1.0);
            }
            """) else { throw MacroError.message("The image processing kernel could not be loaded.") }
        selectionKernel = kernel
    }

    func add(data: Data) throws {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw MacroError.message("A captured photo could not be decoded.")
        }
        try add(image: image)
    }

    /// Also used by synthetic image tests, without a camera.
    func add(image: CIImage) throws {
        var input = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scale = min(1, CGFloat(maximumDimension) / max(input.extent.width, input.extent.height))
        if scale < 1 {
            input = input.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        }
        let size = CGRect(x: 0, y: 0, width: floor(input.extent.width), height: floor(input.extent.height))
        input = try rendered(input, in: size)

        if reference == nil {
            reference = input
            commonRect = size
            registrationScale = min(1, 1024 / max(size.width, size.height))
            registrationReference = try registrationImage(input)
        }
        guard let reference else { throw MacroError.message("Missing reference photo.") }
        guard input.extent.size == reference.extent.size else { throw MacroError.message("Photo dimensions changed during the stack.") }

        if registerImages && frameCount > 0 {
            let translation = try alignment(for: input)
            guard abs(translation.tx) < size.width * 0.03, abs(translation.ty) < size.height * 0.03 else {
                throw MacroError.message("The phone moved too far. Support it and try a smaller focus range.")
            }
            input = input.transformed(by: translation)
            commonRect = commonRect.intersection(input.extent)
            guard commonRect.width * commonRect.height > size.width * size.height * 0.85 else {
                throw MacroError.message("Too little overlap remains between photos. Keep the phone still and retry.")
            }
        }
        input = input.cropped(to: reference.extent)
        if let mean {
            // CIContext works in linear RGB: averaging gamma-encoded bytes would darken the result.
            let average = mean.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: input,
                kCIInputTimeKey: 1.0 / Double(groupCount + 1)
            ])
            self.mean = try rendered(average, in: reference.extent)
        } else { mean = try rendered(input, in: reference.extent) }
        groupCount += 1
        frameCount += 1
    }

    func finishGroup() throws {
        guard let mean, let reference else { throw MacroError.message("No photos at this focus position.") }
        let extent = reference.extent
        let score = try rendered(sharpness(mean), in: extent)
        if let fused, let bestScore {
            guard let selection = selectionKernel.apply(extent: extent, arguments: [score, bestScore]) else {
                throw MacroError.message("Could not calculate the focus selection mask.")
            }
            let feathered = selection.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.5]).cropped(to: extent)
            let merged = mean.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: fused, kCIInputMaskImageKey: feathered
            ])
            self.fused = try rendered(merged, in: extent)
            self.bestScore = try rendered(score.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: bestScore]), in: extent)
        } else {
            fused = mean
            bestScore = score
        }
        self.mean = nil
        groupCount = 0
        groupTotal += 1
        context.clearCaches()
    }

    func outputImage() throws -> CGImage {
        guard groupCount == 0, let fused else { throw MacroError.message("Finish each focus group before exporting.") }
        // Shrink inward, never outward: exclude every translated edge and interpolation fringe.
        let inset = registerImages && frameCount > 1 ? commonRect.insetBy(dx: 3, dy: 3) : commonRect
        let crop = CGRect(x: ceil(inset.minX), y: ceil(inset.minY),
                          width: floor(inset.maxX) - ceil(inset.minX), height: floor(inset.maxY) - ceil(inset.minY))
        guard crop.width > 0, crop.height > 0,
              let output = context.createCGImage(fused, from: crop, format: .RGBA8, colorSpace: colorSpace) else {
            throw MacroError.message("Could not render the finished image.")
        }
        return output
    }

    func referenceImage() throws -> CGImage {
        guard let reference, let result = context.createCGImage(reference, from: reference.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw MacroError.message("Could not render the reference image.")
        }
        return result
    }

    private func sharpness(_ image: CIImage) -> CIImage {
        image.clampedToExtent()
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.65])
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0])
            .cropped(to: image.extent)
    }

    private func rendered(_ image: CIImage, in rect: CGRect) throws -> CIImage {
        guard let cg = context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: colorSpace) else {
            throw MacroError.message("Image processing ran out of resources. Try Standard resolution or fewer photos.")
        }
        return CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    private func registrationImage(_ image: CIImage) throws -> CIImage {
        let scaled = image.transformed(by: CGAffineTransform(scaleX: registrationScale, y: registrationScale))
        return try rendered(scaled, in: scaled.extent.integral)
    }

    func alignment(for image: CIImage) throws -> CGAffineTransform {
        guard let registrationReference else { throw MacroError.message("Missing alignment reference.") }
        // Target is the floating image; handler supplies the fixed reference.
        let request = VNTranslationalImageRegistrationRequest(targetedCIImage: try registrationImage(image), options: [:])
        do { try VNImageRequestHandler(ciImage: registrationReference, options: [:]).perform([request]) }
        catch { throw MacroError.message("Could not align the photos. Add light, support the phone, or narrow the focus range.") }
        guard let result = request.results?.first else { throw MacroError.message("No reliable alignment was found.") }
        let transform = result.alignmentTransform
        guard transform.tx.isFinite, transform.ty.isFinite else { throw MacroError.message("Invalid image alignment.") }
        return CGAffineTransform(translationX: transform.tx / registrationScale, y: transform.ty / registrationScale)
    }
}

/// Serial processing keeps rendering and registration off the main thread.
final class StackWorker {
    private let queue = DispatchQueue(label: "macrostack.processing", qos: .userInitiated)
    private var engine: StackEngine?

    func begin(maximumDimension: Int) async throws {
        try await run { self.engine = try StackEngine(maximumDimension: maximumDimension) }
    }

    func add(data: Data) async throws {
        try await run { guard let engine = self.engine else { throw MacroError.message("No active stack.") }; try engine.add(data: data) }
    }

    func finishGroup() async throws {
        try await run { guard let engine = self.engine else { throw MacroError.message("No active stack.") }; try engine.finishGroup() }
    }

    func finish() async throws -> (CGImage, CGImage) {
        try await run {
            guard let engine = self.engine else { throw MacroError.message("No active stack.") }
            defer { self.engine = nil }
            return (try engine.outputImage(), try engine.referenceImage())
        }
    }

    func discard() async { try? await run { self.engine = nil } }

    private func run<T>(_ action: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                autoreleasepool {
                    do { continuation.resume(returning: try action()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
}
