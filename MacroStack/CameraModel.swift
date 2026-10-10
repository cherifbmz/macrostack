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
    let rejected: Int
    let fallbacks: Int
    let directory: URL
    let originalsSaved: Bool
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
    private var focusPoint = CGPoint(x: 0.5, y: 0.5)

    func start() async {
        foreground = true
        guard !isReady, !starting else { return }
        starting = true
        defer { starting = false }
        do {
            try await camera.start()
            guard foreground else { await camera.stop(); return }
            try await camera.setExposureBias(settings.exposureBias)
            if settings.automaticFocus {
                settings.center(on: try await camera.autofocus(at: focusPoint))
            } else { try await camera.focus(at: settings.near) }
            guard foreground else { return }
            isReady = true
            status = "Tap the subject to focus. Use Single for a quick photo or Both for a still subject."
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

    func autofocus(at point: CGPoint? = nil) {
        guard isReady, !isBusy, !isAdjusting else { return }
        if let point { focusPoint = point }
        isAdjusting = true
        status = "Focusing on your subject…"
        Task {
            defer { isAdjusting = false }
            do {
                let position = try await camera.autofocus(at: focusPoint)
                settings.center(on: position)
                status = "Focus ready. The sweep will start at your subject's focus."
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func updateExposure() {
        guard isReady, !isBusy else { return }
        let bias = settings.exposureBias
        Task {
            do { try await camera.setExposureBias(bias) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func capture() {
        guard isReady, !isBusy, !isAdjusting else { return }
        var settings = settings
        guard settings.automaticFocus || !settings.mode.sweepsFocus || abs(settings.near - settings.far) > 0.005 else {
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
                for seconds in stride(from: settings.timerSeconds, to: 0, by: -1) {
                    status = "Starting in \(seconds)… keep the phone still"
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                try await camera.setExposureBias(settings.exposureBias)
                if settings.automaticFocus {
                    status = "Autofocusing and metering your subject…"
                    settings.center(on: try await camera.autofocus(at: focusPoint))
                    self.settings.center(on: settings.focusCenter)
                }
                try Task.checkCancellation()
                let archive = try CaptureArchive(settings: settings)
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
                        if settings.keepOriginals {
                            let number = captured + 1
                            try await Task.detached(priority: .utility) {
                                try archive.saveOriginal(data, index: number, focus: position)
                            }.value
                        }
                        status = "Aligning photo \(captured + 1) of \(settings.totalFrames)…"
                        _ = try await worker.add(data: data)
                        captured += 1
                        progress = Double(captured) / Double(settings.totalFrames)
                    }
                    status = "Combining focus position \(index + 1)…"
                    try await worker.finishGroup()
                }
                try Task.checkCancellation()
                status = "Rendering your photo…"
                let (image, reference, rejected, fallbacks) = try await worker.finish()
                try Task.checkCancellation()
                // Encode large JPEGs off the UI thread, without sending photos to a server.
                let count = captured
                try await Task.detached(priority: .userInitiated) {
                    try archive.complete(image: image, reference: reference, frames: count, rejected: rejected, fallbacks: fallbacks)
                }.value
                try Task.checkCancellation()
                result = StackResult(image: UIImage(cgImage: image), reference: UIImage(cgImage: reference),
                                     url: archive.outputURL, referenceURL: archive.referenceURL, frames: captured,
                                     positions: settings.positions.count, rejected: rejected, fallbacks: fallbacks,
                                     directory: archive.directory, originalsSaved: settings.keepOriginals)
                status = "Photo ready. Pinch to inspect the stack and best single photo."
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

}

