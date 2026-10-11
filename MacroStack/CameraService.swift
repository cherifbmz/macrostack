@preconcurrency import AVFoundation
import Foundation

/// All session/device state lives on queue; callers can await operations from the UI.
final class CameraService: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "macrostack.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var configured = false
    private var cameras: [AVCaptureDevice] = []
    private var currentInput: AVCaptureDeviceInput?
    private var photoID: Int64?
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var photoResult: Result<Data, Error>?
    private var focusID: UUID?
    private var focusContinuation: CheckedContinuation<Void, Error>?
    private var autofocusID: UUID?
    private var autofocusContinuation: CheckedContinuation<Float, Error>?
    private var exposureID: UUID?
    private var exposureContinuation: CheckedContinuation<String, Error>?

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

    private func discoverCameras() -> [AVCaptureDevice] {
        let back = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .back).devices
        let front = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        return back + (front.map { [$0] } ?? [])
    }

    private func choice(_ camera: AVCaptureDevice) -> CameraChoice {
        let title: String
        let subtitle: String
        if camera.position == .front { title = "Front"; subtitle = "Front camera" }
        else if camera.deviceType == .builtInUltraWideCamera { title = "0.5×"; subtitle = "Ultra Wide · Macro" }
        else if camera.deviceType == .builtInTelephotoCamera { title = "Tele"; subtitle = "Telephoto · Distant detail" }
        else { title = "1×"; subtitle = "Main · Everyday photos" }
        return CameraChoice(id: camera.uniqueID, title: title, subtitle: subtitle,
            supportsFocusStack: camera.isLockingFocusWithCustomLensPositionSupported,
            supportsCustomExposure: camera.isExposureModeSupported(.custom), hasTorch: camera.hasTorch)
    }

    private func stateOnQueue() -> CameraHardwareState {
        CameraHardwareState(cameras: cameras.map(choice), selectedID: device?.uniqueID,
            torchAvailable: device.map { $0.hasTorch && $0.isTorchAvailable && $0.isTorchModeSupported(.on) } ?? false,
            torchLevel: device.map { $0.isTorchActive ? $0.torchLevel : 0 } ?? 0)
    }

    func hardwareState() async -> CameraHardwareState {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.stateOnQueue()) }
        }
    }

    private func updatePhotoDimensions(for camera: AVCaptureDevice) {
        output.maxPhotoQualityPrioritization = .quality
        if let largest = camera.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }) { output.maxPhotoDimensions = largest }
    }

    private func configure() throws {
        cameras = discoverCameras()
        guard let camera = cameras.first else {
            throw MacroError.message("No camera is available. Check camera access in Settings and retry on your iPhone.")
        }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { throw MacroError.message("Cannot open this camera.") }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw MacroError.message("Cannot configure photo capture.")
        }
        session.addOutput(output)
        updatePhotoDimensions(for: camera)
        currentInput = input
        device = camera
        configured = true
    }

    func selectCamera(id: String) async throws -> CameraHardwareState {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard self.photoContinuation == nil, self.focusContinuation == nil,
                          self.autofocusContinuation == nil, self.exposureContinuation == nil,
                          let next = self.cameras.first(where: { $0.uniqueID == id }) else {
                        throw MacroError.message("Wait for capture or focusing to finish before switching cameras.")
                    }
                    let input = try AVCaptureDeviceInput(device: next)
                    // Do not carry an illuminated torch or old lens positions across a camera change.
                    try self.turnTorchOff()
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    let old = self.currentInput
                    if let old { self.session.removeInput(old) }
                    guard self.session.canAddInput(input) else {
                        if let old, self.session.canAddInput(old) { self.session.addInput(old) }
                        throw MacroError.message("Could not switch cameras. The previous camera remains selected.")
                    }
                    self.session.addInput(input)
                    self.currentInput = input
                    self.device = next
                    self.updatePhotoDimensions(for: next)
                    continuation.resume(returning: self.stateOnQueue())
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func turnTorchOff() throws {
        guard let device, device.hasTorch, device.isTorchModeSupported(.off) else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.torchMode = .off
    }

    func setTorch(level: Float) async throws -> CameraHardwareState {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let device = self.device, self.session.isRunning else {
                        throw MacroError.message("Start the camera before using the light.")
                    }
                    if level <= 0 { try self.turnTorchOff() }
                    else {
                        guard device.hasTorch, device.isTorchAvailable, device.isTorchModeSupported(.on) else {
                            throw MacroError.message("The flashlight is unavailable on this camera or while the phone is too warm.")
                        }
                        try device.lockForConfiguration()
                        defer { device.unlockForConfiguration() }
                        try device.setTorchModeOn(level: min(1, max(0.01, level)))
                    }
                    continuation.resume(returning: self.stateOnQueue())
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func focus(at position: Float) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let device = self.device, self.session.isRunning else {
                    continuation.resume(throwing: MacroError.message("Start the camera before setting focus."))
                    return
                }
                guard device.isLockingFocusWithCustomLensPositionSupported else {
                    continuation.resume(throwing: MacroError.message("Manual focus is unavailable on this camera. Use Photo or Noise mode."))
                    return
                }
                guard self.focusContinuation == nil, self.autofocusContinuation == nil else {
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

    func autofocus(at point: CGPoint) async throws -> Float {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let device = self.device, self.session.isRunning,
                      self.focusContinuation == nil,
                      self.autofocusContinuation == nil else {
                    continuation.resume(throwing: MacroError.message("Autofocus is unavailable. Wait for the camera, or use manual focus."))
                    return
                }
                do {
                    try device.lockForConfiguration()
                    if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
                    if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
                    if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                    device.unlockForConfiguration()
                    let id = UUID()
                    self.autofocusID = id
                    self.autofocusContinuation = continuation
                    self.queue.asyncAfter(deadline: .now() + 0.4) {
                        self.pollAutofocus(id: id, deadline: Date().addingTimeInterval(6), stableSamples: 0)
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func pollAutofocus(id: UUID, deadline: Date, stableSamples: Int) {
        guard autofocusID == id, let continuation = autofocusContinuation else { return }
        guard let device, session.isRunning else {
            autofocusID = nil; autofocusContinuation = nil
            continuation.resume(throwing: CancellationError())
            return
        }
        let settled = !device.isAdjustingFocus && !device.isAdjustingExposure && !device.isAdjustingWhiteBalance
        let stable = settled ? stableSamples + 1 : 0
        if stable >= 3 {
            autofocusID = nil; autofocusContinuation = nil
            continuation.resume(returning: device.lensPosition)
        } else if Date() >= deadline {
            autofocusID = nil; autofocusContinuation = nil
            continuation.resume(throwing: MacroError.message("Focus or exposure could not settle. Add light, move slightly farther away, or set focus manually."))
        } else {
            queue.asyncAfter(deadline: .now() + 0.12) { self.pollAutofocus(id: id, deadline: deadline, stableSamples: stable) }
        }
    }

    func setExposureBias(_ value: Float) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let device = self.device else { throw MacroError.message("Camera unavailable.") }
                    try device.lockForConfiguration()
                    device.setExposureTargetBias(min(device.maxExposureTargetBias, max(device.minExposureTargetBias, value)), completionHandler: nil)
                    device.unlockForConfiguration()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
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

    func prepareBurstExposure(denominator: Int, continuousFocus: Bool) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let device = self.device, self.session.isRunning,
                      device.isExposureModeSupported(.custom), self.exposureContinuation == nil else {
                    continuation.resume(throwing: MacroError.message("Manual shutter is unavailable. Try Single mode."))
                    return
                }
                do {
                    let format = device.activeFormat
                    let plan = try ExposurePlan.make(meteredSeconds: CMTimeGetSeconds(device.exposureDuration),
                        meteredISO: device.iso, denominator: denominator,
                        minimumSeconds: CMTimeGetSeconds(format.minExposureDuration), maximumSeconds: CMTimeGetSeconds(format.maxExposureDuration),
                        minimumISO: format.minISO, maximumISO: format.maxISO)
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }
                    if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
                    if continuousFocus && device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    let id = UUID()
                    self.exposureID = id
                    self.exposureContinuation = continuation
                    device.setExposureModeCustom(duration: CMTime(seconds: plan.seconds, preferredTimescale: 1_000_000_000), iso: plan.iso) { _ in
                        self.queue.async {
                            self.finishBurstExposure(id: id, result: .success(plan.summary))
                        }
                    }
                    self.queue.asyncAfter(deadline: .now() + 5) {
                        self.finishBurstExposure(id: id, result: .failure(MacroError.message("Shutter adjustment timed out. Retry capture.")))
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func finishBurstExposure(id: UUID, result: Result<String, Error>) {
        guard exposureID == id, let continuation = exposureContinuation else { return }
        exposureID = nil; exposureContinuation = nil
        continuation.resume(with: result)
    }

    func photo(quality: CaptureQuality = .quality) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.session.isRunning, self.photoContinuation == nil else {
                    continuation.resume(throwing: MacroError.message("The camera is busy or interrupted."))
                    return
                }
                let codec: AVVideoCodecType = self.output.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
                settings.maxPhotoDimensions = self.output.maxPhotoDimensions
                // Speed prioritization keeps the explicit burst shutter/ISO settings.
                switch quality {
                case .speed: settings.photoQualityPrioritization = .speed
                case .balanced: settings.photoQualityPrioritization = .balanced
                case .quality: settings.photoQualityPrioritization = .quality
                }
                settings.flashMode = .off
                if let connection = self.output.connection(with: .video), connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
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
                if let id = self.exposureID { self.finishBurstExposure(id: id, result: .failure(CancellationError())) }
                if let pending = self.autofocusContinuation {
                    self.autofocusContinuation = nil; self.autofocusID = nil
                    pending.resume(throwing: CancellationError())
                }
                if let id = self.focusID { self.finishFocus(id: id, error: CancellationError()) }
                if let id = self.photoID { self.finishPhoto(id: id, error: CancellationError()) }
                try? self.turnTorchOff()
                if self.session.isRunning { self.session.stopRunning() }
                continuation.resume()
            }
        }
    }
}
