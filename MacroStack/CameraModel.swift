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
    let mode: StackMode
    let candidates: [URL]
    let bestFrameIndex: Int
    let captureNotes: String
}

@MainActor
final class CameraModel: ObservableObject {
    let camera = CameraService()
    private let worker = StackWorker()
    @Published var settings: StackSettings = {
        var value = StackSettings()
        value.useStillInsectPreset()
        return value
    }()
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
    @Published var previewLensPosition: Float = 0.2

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
                previewLensPosition = settings.focusCenter
            } else { try await camera.focus(at: settings.near); previewLensPosition = settings.near }
            guard foreground else { return }
            isReady = true
            status = "Tap the insect's eye, then choose Still insect or Moving insect."
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
            do { try await camera.focus(at: position); previewLensPosition = position }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func autofocus(at point: CGPoint? = nil, imagePoint: CGPoint? = nil) {
        guard isReady, !isBusy, !isAdjusting else { return }
        if let point { focusPoint = point }
        if let imagePoint {
            settings.subjectX = imagePoint.x
            settings.subjectY = imagePoint.y
        }
        isAdjusting = true
        status = "Focusing on your subject…"
        Task {
            defer { isAdjusting = false }
            do {
                let position = try await camera.autofocus(at: focusPoint)
                previewLensPosition = position
                if settings.automaticFocus { settings.center(on: position) }
                status = settings.mode == .burst ? "Focus ready. Keep the insect inside the yellow box during the burst." : "Focus ready. The sweep will start at your subject's focus."
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

    func markEndpoint(near: Bool) {
        guard isReady, !isBusy, !isAdjusting else { return }
        settings.automaticFocus = false
        if near { settings.near = previewLensPosition } else { settings.far = previewLensPosition }
        status = near ? "Near bracket saved. Tap the farthest detail, then set Far." : "Far bracket saved. Preview both ends before capturing."
    }

    func capture() {
        guard isReady, !isBusy, !isAdjusting else { return }
        var settings = settings
        if settings.mode == .burst { settings.keepOriginals = true }
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
                let exposureNotes: String
                if settings.mode == .burst {
                    if !settings.automaticFocus { try await camera.focus(at: settings.near) }
                    exposureNotes = try await camera.prepareBurstExposure(denominator: settings.shutterDenominator,
                                                                          continuousFocus: settings.automaticFocus)
                } else {
                    try await camera.lockExposure()
                    exposureNotes = "\(settings.captureQuality.rawValue) capture with metered exposure."
                }
                try Task.checkCancellation()
                var originals: [URL] = []
                var captured = 0
                let captureStarted = Date()
                for (index, position) in settings.positions.enumerated() {
                    try Task.checkCancellation()
                    if settings.mode != .burst {
                        status = "Setting focus \(index + 1) of \(settings.positions.count)…"
                        try await camera.focus(at: position)
                    }
                    for repeatIndex in 0..<settings.repeats {
                        try Task.checkCancellation()
                        status = settings.mode == .burst
                            ? "Burst photo \(repeatIndex + 1)/\(settings.repeats) · \(exposureNotes)"
                            : "Focus \(index + 1)/\(settings.positions.count) · photo \(repeatIndex + 1)/\(settings.repeats)"
                        let data = try await camera.photo(quality: settings.mode == .burst ? .speed : settings.captureQuality)
                        try Task.checkCancellation()
                        let number = captured + 1
                        let lens: Float? = settings.mode == .burst && settings.automaticFocus ? nil : position
                        let file = try await Task.detached(priority: .utility) {
                            try archive.saveOriginal(data, index: number, focus: lens)
                        }.value
                        originals.append(file)
                        captured += 1
                        progress = 0.6 * Double(captured) / Double(settings.totalFrames)
                    }
                }
                let captureNotes = String(format: "Captured %d photos in %.1f seconds. ", captured, Date().timeIntervalSince(captureStarted)) + exposureNotes
                await camera.restoreAutomaticExposure()
                // Disk-backed capture keeps memory bounded and removes rendering pauses between photos.
                try await worker.begin(maximumDimension: settings.maximumDimension,
                                       subjectRegion: settings.subjectRegion, bestFrameOnly: settings.mode == .burst)
                for (index, file) in originals.enumerated() {
                    try Task.checkCancellation()
                    status = settings.mode == .burst ? "Checking insect detail in photo \(index + 1)/\(captured)…" : "Processing photo \(index + 1)/\(captured)…"
                    _ = try await worker.add(file: file)
                    if (index + 1) % settings.repeats == 0 { try await worker.finishGroup() }
                    progress = 0.6 + 0.4 * Double(index + 1) / Double(captured)
                }
                try Task.checkCancellation()
                status = "Rendering your photo…"
                let (image, reference, rejected, fallbacks, bestFrameIndex) = try await worker.finish()
                try Task.checkCancellation()
                // Encode large JPEGs off the UI thread, without sending photos to a server.
                let count = captured
                let temporaryFrames = settings.keepOriginals ? [] : originals
                try await Task.detached(priority: .userInitiated) {
                    try archive.complete(image: image, reference: reference, frames: count, rejected: rejected, fallbacks: fallbacks, notes: captureNotes)
                    try archive.discardTemporaryFrames(temporaryFrames)
                }.value
                try Task.checkCancellation()
                result = StackResult(image: UIImage(cgImage: image), reference: UIImage(cgImage: reference),
                                     url: archive.outputURL, referenceURL: archive.referenceURL, frames: captured,
                                     positions: settings.positions.count, rejected: rejected, fallbacks: fallbacks,
                                     directory: archive.directory, originalsSaved: settings.keepOriginals, mode: settings.mode,
                                     candidates: settings.mode == .burst ? originals : [], bestFrameIndex: bestFrameIndex,
                                     captureNotes: captureNotes)
                status = settings.mode == .burst ? "Burst ready. Review individual photos and choose the sharpest insect." : "Photo ready. Pinch to inspect the stack and best single photo."
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

