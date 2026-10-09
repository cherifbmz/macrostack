@preconcurrency import AVFoundation
import Foundation

/// All session/device state lives on queue; callers can await operations from the UI.
final class CameraService: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "macrostack.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var configured = false
    private var photoID: Int64?
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var photoResult: Result<Data, Error>?
    private var focusID: UUID?
    private var focusContinuation: CheckedContinuation<Void, Error>?

    func start() async throws {
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard allowed else {
            throw MacroError.message("Allow camera access in Settings to use MacroStack.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if !self.configured { try self.configure() }
                    if !self.session.isRunning { self.session.startRunning() }
                    guard self.session.isRunning else {
                        throw MacroError.message("The camera is unavailable. Close other camera apps and retry.")
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
              camera.isLockingFocusWithCustomLensPositionSupported else {
            throw MacroError.message("This prototype needs an Ultra Wide camera with manual focus, such as iPhone 13 Pro or Pro Max. The simulator cannot capture photos.")
        }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { throw MacroError.message("Cannot open the Ultra Wide camera.") }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw MacroError.message("Cannot configure photo capture.")
        }
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .quality
        if let largest = camera.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }) { output.maxPhotoDimensions = largest }
        device = camera
        configured = true
    }

    func focus(at position: Float) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let device = self.device, self.session.isRunning else {
                    continuation.resume(throwing: MacroError.message("Start the camera before setting focus."))
                    return
                }
                guard self.focusContinuation == nil else {
                    continuation.resume(throwing: MacroError.message("A focus adjustment is already running."))
                    return
                }
                do {
                    try device.lockForConfiguration()
                    let id = UUID()
                    self.focusID = id
                    self.focusContinuation = continuation
                    device.setFocusModeLocked(lensPosition: max(0, min(1, position))) { _ in
                        // Completion marks applied focus. Add a short settling interval before a still.
                        self.queue.asyncAfter(deadline: .now() + 0.12) { self.finishFocus(id: id, error: nil) }
                    }
                    device.unlockForConfiguration()
                    self.queue.asyncAfter(deadline: .now() + 5) {
                        self.finishFocus(id: id, error: MacroError.message("Focus adjustment timed out. Retry with the app in the foreground."))
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func finishFocus(id: UUID, error: Error?) {
        guard focusID == id, let continuation = focusContinuation else { return }
        focusContinuation = nil
        focusID = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    func lockExposure() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let device = self.device else { throw MacroError.message("Camera unavailable.") }
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }
                    guard device.isExposureModeSupported(.locked), device.isWhiteBalanceModeSupported(.locked) else {
                        throw MacroError.message("Exposure and white balance locking are required for stacking.")
                    }
                    device.exposureMode = .locked
                    device.whiteBalanceMode = .locked
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func restoreAutomaticExposure() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if let device = self.device, (try? device.lockForConfiguration()) != nil {
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
                    device.unlockForConfiguration()
                }
                continuation.resume()
            }
        }
    }

    func photo() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.session.isRunning, self.photoContinuation == nil else {
                    continuation.resume(throwing: MacroError.message("The camera is busy or interrupted."))
                    return
                }
                let codec: AVVideoCodecType = self.output.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
                settings.maxPhotoDimensions = self.output.maxPhotoDimensions
                settings.photoQualityPrioritization = .quality
                settings.flashMode = .off
                if let connection = self.output.connection(with: .video), connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                self.photoID = settings.uniqueID
                self.photoContinuation = continuation
                self.photoResult = nil
                self.output.capturePhoto(with: settings, delegate: self)
                self.queue.asyncAfter(deadline: .now() + 15) {
                    self.finishPhoto(id: settings.uniqueID, error: MacroError.message("Photo capture timed out. Keep the app open and retry."))
                }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let result: Result<Data, Error>
        if let error { result = .failure(error) }
        else if let data = photo.fileDataRepresentation() { result = .success(data) }
        else { result = .failure(MacroError.message("The camera returned an empty photo.")) }
        queue.async {
            guard self.photoID == id else { return }
            self.photoResult = result
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        queue.async { self.finishPhoto(id: resolvedSettings.uniqueID, error: error) }
    }

    private func finishPhoto(id: Int64, error: Error?) {
        guard photoID == id, let continuation = photoContinuation else { return }
        let result = error.map { Result<Data, Error>.failure($0) }
            ?? photoResult ?? .failure(MacroError.message("No processed image was received."))
        photoContinuation = nil
        photoResult = nil
        photoID = nil
        continuation.resume(with: result)
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if let id = self.focusID { self.finishFocus(id: id, error: CancellationError()) }
                if let id = self.photoID { self.finishPhoto(id: id, error: CancellationError()) }
                if self.session.isRunning { self.session.stopRunning() }
                continuation.resume()
            }
        }
    }
}
