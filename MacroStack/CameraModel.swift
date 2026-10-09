import SwiftUI
import Photos
import ImageIO
import UniformTypeIdentifiers

struct StackResult: Identifiable {
    let id = UUID()
    let image: UIImage
    let reference: UIImage
    let url: URL
    let referenceURL: URL
    let frames: Int
    let positions: Int
}

@MainActor
final class CameraModel: ObservableObject {
    let camera = CameraService()
    private let worker = StackWorker()
    @Published var settings = StackSettings()
    @Published var isReady = false
    @Published var isBusy = false
    @Published var isAdjusting = false
    @Published var progress = 0.0
    @Published var status = "Opening Ultra Wide camera…"
    @Published var errorMessage: String?
    @Published var result: StackResult?
    private var captureTask: Task<Void, Never>?
    private var starting = false
    private var foreground = true

    func start() async {
        foreground = true
        guard !isReady, !starting else { return }
        starting = true
        defer { starting = false }
        do {
            try await camera.start()
            guard foreground else { await camera.stop(); return }
            try await camera.focus(at: settings.near)
            guard foreground else { return }
            isReady = true
            status = "Frame your subject, then preview both focus endpoints."
        } catch is CancellationError { }
        catch { status = "Camera unavailable"; errorMessage = error.localizedDescription }
    }

    func suspend() {
        foreground = false
        isReady = false
        captureTask?.cancel()
        Task { await camera.stop() }
    }

    func previewFocus(_ position: Float) {
        guard isReady, !isBusy, !isAdjusting else { return }
        isAdjusting = true
        Task {
            defer { isAdjusting = false }
            do { try await camera.focus(at: position) }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func capture() {
        guard isReady, !isBusy, !isAdjusting else { return }
        let settings = settings
        guard settings.mode == .clean || abs(settings.near - settings.far) > 0.005 else {
            errorMessage = "Choose different focus endpoints, or use Noise mode for a fixed-focus burst."
            return
        }
        isBusy = true
        progress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        captureTask = Task {
            defer {
                isBusy = false
                captureTask = nil
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do {
                try await worker.begin(maximumDimension: settings.maximumDimension)
                try Task.checkCancellation()
                // Lock the metered preview exposure. Let the preview settle before pressing Capture.
                try await camera.lockExposure()
                var captured = 0
                for (index, position) in settings.positions.enumerated() {
                    try Task.checkCancellation()
                    status = "Setting focus \(index + 1) of \(settings.positions.count)…"
                    try await camera.focus(at: position)
                    for repeatIndex in 0..<settings.repeats {
                        try Task.checkCancellation()
                        status = "Focus \(index + 1)/\(settings.positions.count) · photo \(repeatIndex + 1)/\(settings.repeats)"
                        let data = try await camera.photo()
                        try Task.checkCancellation()
                        status = "Aligning photo \(captured + 1) of \(settings.totalFrames)…"
                        try await worker.add(data: data)
                        captured += 1
                        progress = Double(captured) / Double(settings.totalFrames)
                    }
                    status = "Combining focus position \(index + 1)…"
                    try await worker.finishGroup()
                }
                try Task.checkCancellation()
                status = "Rendering your photo…"
                let (image, reference) = try await worker.finish()
                try Task.checkCancellation()
                // Encode large JPEGs off the UI thread, without sending photos to a server.
                let urls = try await Task.detached(priority: .userInitiated) {
                    try Self.writeResults(image: image, reference: reference)
                }.value
                try Task.checkCancellation()
                result = StackResult(image: UIImage(cgImage: image), reference: UIImage(cgImage: reference),
                                     url: urls.0, referenceURL: urls.1, frames: captured, positions: settings.positions.count)
                status = "Stack complete. Compare it with the first photo before saving."
            } catch is CancellationError {
                status = "Capture cancelled."
                await worker.discard()
            } catch {
                status = "Stack could not be completed."
                errorMessage = error.localizedDescription
                await worker.discard()
            }
            await camera.restoreAutomaticExposure()
        }
    }

    func cancel() {
        captureTask?.cancel()
        status = "Cancelling after the current operation…"
    }

    nonisolated private static func writeResults(image: CGImage, reference: CGImage) throws -> (URL, URL) {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = documents.appendingPathComponent("Stacks/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("MacroStack.jpg")
        let original = directory.appendingPathComponent("First-photo.jpg")
        for (cgImage, url) in [(image, output), (reference, original)] {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw MacroError.message("Could not create the output file.")
            }
            CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.97] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw MacroError.message("Could not save the image. Check available storage.") }
        }
        return (output, original)
    }
}

