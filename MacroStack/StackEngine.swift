import CoreImage
import ImageIO
import Vision
import simd

/// A streaming, linear-light prototype. Only a few rendered frames are retained.
/// Perspective registration tolerates small rotation and focus breathing, not subject motion.
final class StackEngine {
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let maximumDimension: Int
    private let registerImages: Bool
    private let selectionKernel: CIColorKernel
    private let averagingKernel: CIColorKernel
    private let blendKernel: CIColorKernel
    private let protectMotion: Bool
    private let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private var reference: CIImage?
    private var registrationReference: CIImage?
    private var registrationScale: CGFloat = 1
    private var commonRect = CGRect.zero
    private var mean: CIImage?
    private var groupCount = 0
    private var fused: CIImage?
    private var bestScore: CIImage?
    private var bestImage: CIImage?
    private var bestImageDetail: Float = -1
    private var groupDetail: Float = 0
    private(set) var frameCount = 0
    private(set) var groupTotal = 0
    private(set) var rejectedFrames = 0
    private(set) var translationFallbacks = 0

    init(maximumDimension: Int, registerImages: Bool = true, protectMotion: Bool = true) throws {
        self.maximumDimension = maximumDimension
        self.registerImages = registerImages
        self.protectMotion = protectMotion
        context = CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ])
        guard let kernel = CIColorKernel(source: """
            kernel vec4 chooseSharper(__sample candidate, __sample previous) {
                float ratio = (candidate.r + 0.0005) / (previous.r + 0.0005);
                float pick = smoothstep(1.04, 1.35, ratio);
                return vec4(pick, pick, pick, 1.0);
            }
            """) else { throw MacroError.message("The image processing kernel could not be loaded.") }
        selectionKernel = kernel
        guard let average = CIColorKernel(source: """
            kernel vec4 averageProtected(__sample previous, __sample candidate, float weight, float protect) {
                vec3 delta = abs(previous.rgb - candidate.rgb);
                float difference = max(delta.r, max(delta.g, delta.b));
                float agreement = mix(1.0, 1.0 - smoothstep(0.08, 0.24, difference), protect);
                return vec4(mix(previous.rgb, candidate.rgb, weight * agreement), 1.0);
            }
            """), let blend = CIColorKernel(source: """
            kernel vec4 blendDetail(__sample previous, __sample candidate,
                __sample previousLow, __sample candidateLow, __sample fineMask, __sample coarseMask) {
                vec3 low = mix(previousLow.rgb, candidateLow.rgb, coarseMask.r);
                vec3 detail = mix(previous.rgb - previousLow.rgb, candidate.rgb - candidateLow.rgb, fineMask.r);
                return vec4(clamp(low + detail, 0.0, 1.0), 1.0);
            }
            """) else { throw MacroError.message("Could not load image processing kernels.") }
        averagingKernel = average
        blendKernel = blend
    }

    @discardableResult func add(data: Data) throws -> Bool {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw MacroError.message("A captured photo could not be decoded.")
        }
        return try add(image: image)
    }

    /// Also used by synthetic image tests, without a camera.
    @discardableResult func add(image: CIImage) throws -> Bool {
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
            let registered = try register(input)
            input = registered.image
            commonRect = commonRect.intersection(registered.validRect)
            guard commonRect.width * commonRect.height > size.width * size.height * 0.72 else {
                throw MacroError.message("Too little overlap remains between photos. Keep the phone still and retry.")
            }
        }
        input = input.cropped(to: reference.extent)
        let detail = detailMetric(input)
        frameCount += 1
        if groupCount > 0 && groupDetail > 0.002 && detail < groupDetail * 0.65 {
            rejectedFrames += 1
            return false
        }
        if detail > bestImageDetail {
            bestImageDetail = detail
            bestImage = try rendered(input, in: reference.extent)
        }
        // A later, substantially sharper frame replaces a blurred group anchor.
        if groupCount > 0 && detail > max(0.002, groupDetail * 1.5) {
            rejectedFrames += groupCount
            mean = nil; groupCount = 0
        }
        if let mean {
            guard let average = averagingKernel.apply(extent: reference.extent,
                arguments: [mean, input, 1.0 / Double(groupCount + 1), protectMotion ? 1.0 : 0.0]) else {
                throw MacroError.message("Could not average these photos.")
            }
            self.mean = try rendered(average, in: reference.extent, highPrecision: true)
        } else { mean = try rendered(input, in: reference.extent, highPrecision: true) }
        groupDetail = max(groupDetail, detail)
        groupCount += 1
        return true
    }

    func finishGroup() throws {
        guard let mean, let reference else { throw MacroError.message("No photos at this focus position.") }
        let extent = reference.extent
        let score = try rendered(sharpness(mean), in: extent)
        if let fused, let bestScore {
            guard let selection = selectionKernel.apply(extent: extent, arguments: [score, bestScore]) else {
                throw MacroError.message("Could not calculate the focus selection mask.")
            }
            func blur(_ image: CIImage, _ radius: Double) -> CIImage {
                image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: extent)
            }
            guard let merged = blendKernel.apply(extent: extent, arguments: [
                fused, mean, blur(fused, 4), blur(mean, 4), blur(selection, 0.8), blur(selection, 8)
            ]) else { throw MacroError.message("Could not blend focus detail.") }
            self.fused = try rendered(merged, in: extent, highPrecision: true)
            self.bestScore = try rendered(score.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: bestScore]), in: extent)
        } else {
            fused = mean
            bestScore = score
        }
        self.mean = nil
        groupCount = 0
        groupDetail = 0
        groupTotal += 1
        context.clearCaches()
    }

    func outputImage() throws -> CGImage {
        guard groupCount == 0, let fused else { throw MacroError.message("Finish each focus group before exporting.") }
        return try export(fused)
    }

    private func export(_ image: CIImage) throws -> CGImage {
        // Shrink inward, never outward: exclude every translated edge and interpolation fringe.
        let inset = registerImages && frameCount > 1 ? commonRect.insetBy(dx: 3, dy: 3) : commonRect
        let crop = CGRect(x: ceil(inset.minX), y: ceil(inset.minY),
                          width: floor(inset.maxX) - ceil(inset.minX), height: floor(inset.maxY) - ceil(inset.minY))
        guard crop.width > 0, crop.height > 0,
              let output = context.createCGImage(image, from: crop, format: .RGBA8, colorSpace: colorSpace) else {
            throw MacroError.message("Could not render the finished image.")
        }
        return output
    }

    func referenceImage() throws -> CGImage {
        guard let bestImage else { throw MacroError.message("Missing comparison photo.") }
        return try export(bestImage)
    }

    private func sharpness(_ image: CIImage) -> CIImage {
        image.clampedToExtent()
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.65])
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0])
            .cropped(to: image.extent)
    }

    private func rendered(_ image: CIImage, in rect: CGRect, highPrecision: Bool = false) throws -> CIImage {
        if highPrecision {
            let rowBytes = Int(rect.width) * 8
            var data = Data(count: rowBytes * Int(rect.height))
            data.withUnsafeMutableBytes { buffer in
                context.render(image, toBitmap: buffer.baseAddress!, rowBytes: rowBytes,
                               bounds: rect, format: .RGBAh, colorSpace: linearSpace)
            }
            return CIImage(bitmapData: data, bytesPerRow: rowBytes, size: rect.size, format: .RGBAh, colorSpace: linearSpace)
                .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        }
        guard let cg = context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: colorSpace) else {
            throw MacroError.message("Image processing ran out of resources. Try Standard resolution or fewer photos.")
        }
        return CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    private func detailMetric(_ image: CIImage) -> Float {
        let scale = min(1, 512 / max(image.extent.width, image.extent.height))
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let edges = sharpness(small)
        let average = edges.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: small.extent)])
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes {
            context.render(average, toBitmap: $0.baseAddress!, rowBytes: 16,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: linearSpace)
        }
        return pixel[0]
    }

    func register(_ image: CIImage) throws -> RegisteredFrame {
        guard let registrationReference else { throw MacroError.message("Missing alignment reference.") }
        let request = VNHomographicImageRegistrationRequest(targetedCIImage: try registrationImage(image), options: [:])
        do {
            try VNImageRequestHandler(ciImage: registrationReference, options: [:]).perform([request])
        } catch { /* Use a constrained translation fallback if perspective registration fails. */ }
        if let observation = request.results?.first {
            // Vision supplies destination-to-source sampling coordinates (WWDC17 session 510).
            // PerspectiveTransform needs forward source-to-destination corners instead.
            // Invalid geometry must fail here, not silently fall back to translation.
            return try ImageAlignment.warp(image, matrix: simd_inverse(observation.warpTransform), registrationScale: registrationScale)
        }
        let correction = try alignment(for: image)
        let matrix = simd_float3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, 1, 0),
                                             SIMD3(Float(correction.tx), Float(correction.ty), 1)))
        let result = try ImageAlignment.warp(image, matrix: matrix, registrationScale: 1)
        translationFallbacks += 1
        return result
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

    func add(data: Data) async throws -> Bool {
        try await run { guard let engine = self.engine else { throw MacroError.message("No active stack.") }; return try engine.add(data: data) }
    }

    func finishGroup() async throws {
        try await run { guard let engine = self.engine else { throw MacroError.message("No active stack.") }; try engine.finishGroup() }
    }

    func finish() async throws -> (CGImage, CGImage, Int, Int) {
        try await run {
            guard let engine = self.engine else { throw MacroError.message("No active stack.") }
            defer { self.engine = nil }
            return (try engine.outputImage(), try engine.referenceImage(), engine.rejectedFrames, engine.translationFallbacks)
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
