import Foundation

enum StackMode: String, CaseIterable, Identifiable, Codable {
    case both = "Both"
    case focus = "Focus"
    case clean = "Noise"
    case single = "Single"
    case burst = "Burst"
    var id: String { rawValue }
    var sweepsFocus: Bool { self == .both || self == .focus }
}

enum CaptureQuality: String, Codable, CaseIterable, Identifiable {
    case speed = "Speed", balanced = "Balanced", quality = "Quality"
    var id: String { rawValue }
}

enum FocusSpacing: String, Codable, CaseIterable, Identifiable {
    case linear = "Even", near = "Near dense"
    var id: String { rawValue }
}

struct StackSettings: Codable {
    var mode: StackMode = .both
    var near: Float = 0.05
    var far: Float = 0.35
    var focusSteps = 7
    var framesPerPosition = 2
    var fullResolution = true
    var automaticFocus = true
    var focusSpan: Float = 0.12
    var focusCenter: Float = 0.2
    var timerSeconds = 2
    var exposureBias: Float = 0
    var keepOriginals = true
    var showGrid = false
    var burstCount = 5
    var shutterDenominator = 500
    var subjectX: Double = 0.5
    var subjectY: Double = 0.5
    var captureQuality: CaptureQuality = .quality
    var focusSpacing: FocusSpacing = .linear

    init() {}

    // Older projects don't contain newer settings. Preserve their values and default only missing keys.
    enum CodingKeys: String, CodingKey {
        case mode, near, far, focusSteps, framesPerPosition, fullResolution, automaticFocus, focusSpan, focusCenter
        case timerSeconds, exposureBias, keepOriginals, showGrid, burstCount, shutterDenominator, subjectX, subjectY
        case captureQuality, focusSpacing
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(StackMode.self, forKey: .mode) ?? mode
        near = try c.decodeIfPresent(Float.self, forKey: .near) ?? near
        far = try c.decodeIfPresent(Float.self, forKey: .far) ?? far
        focusSteps = try c.decodeIfPresent(Int.self, forKey: .focusSteps) ?? focusSteps
        framesPerPosition = try c.decodeIfPresent(Int.self, forKey: .framesPerPosition) ?? framesPerPosition
        fullResolution = try c.decodeIfPresent(Bool.self, forKey: .fullResolution) ?? fullResolution
        automaticFocus = try c.decodeIfPresent(Bool.self, forKey: .automaticFocus) ?? automaticFocus
        focusSpan = try c.decodeIfPresent(Float.self, forKey: .focusSpan) ?? focusSpan
        focusCenter = try c.decodeIfPresent(Float.self, forKey: .focusCenter) ?? focusCenter
        timerSeconds = try c.decodeIfPresent(Int.self, forKey: .timerSeconds) ?? timerSeconds
        exposureBias = try c.decodeIfPresent(Float.self, forKey: .exposureBias) ?? exposureBias
        keepOriginals = try c.decodeIfPresent(Bool.self, forKey: .keepOriginals) ?? keepOriginals
        showGrid = try c.decodeIfPresent(Bool.self, forKey: .showGrid) ?? showGrid
        burstCount = try c.decodeIfPresent(Int.self, forKey: .burstCount) ?? burstCount
        shutterDenominator = try c.decodeIfPresent(Int.self, forKey: .shutterDenominator) ?? shutterDenominator
        subjectX = try c.decodeIfPresent(Double.self, forKey: .subjectX) ?? subjectX
        subjectY = try c.decodeIfPresent(Double.self, forKey: .subjectY) ?? subjectY
        captureQuality = try c.decodeIfPresent(CaptureQuality.self, forKey: .captureQuality) ?? captureQuality
        focusSpacing = try c.decodeIfPresent(FocusSpacing.self, forKey: .focusSpacing) ?? focusSpacing
    }

    /// Portrait image coordinates, origin at the bottom left (not camera device coordinates).
    var subjectRegion: CGRect {
        CGRect(x: max(0, min(0.76, subjectX - 0.12)),
               y: max(0, min(0.76, subjectY - 0.12)), width: 0.24, height: 0.24)
    }

    mutating func useStillInsectPreset() {
        mode = .focus; focusSteps = 9; focusSpan = 0.06
        automaticFocus = true; fullResolution = true; timerSeconds = 2; keepOriginals = true
    }

    mutating func useMovingInsectPreset() {
        mode = .burst; burstCount = 5; shutterDenominator = 500
        automaticFocus = true; fullResolution = true; timerSeconds = 0; keepOriginals = true
    }

    mutating func center(on position: Float) {
        focusCenter = min(1, max(0, position))
        near = max(0, focusCenter - focusSpan / 2)
        far = min(1, focusCenter + focusSpan / 2)
    }

    var positions: [Float] {
        if !mode.sweepsFocus { return [automaticFocus ? focusCenter : near] }
        let lower = automaticFocus ? max(0, focusCenter - focusSpan / 2) : max(0, min(near, far))
        let upper = automaticFocus ? min(1, focusCenter + focusSpan / 2) : min(1, max(near, far))
        let count = min(20, max(2, focusSteps))
        let center = automaticFocus ? focusCenter : (lower + upper) / 2
        // Capture the focused subject first, giving registration a useful sharp reference.
        var values = (0..<count).map { index -> Float in
            let t = Float(index) / Float(count - 1)
            return lower + (upper - lower) * (focusSpacing == .near ? t * t : t)
        }
        if let nearest = values.indices.min(by: { abs(values[$0] - center) < abs(values[$1] - center) }) {
            values[nearest] = center
        }
        return values.sorted { abs($0 - center) == abs($1 - center) ? $0 < $1 : abs($0 - center) < abs($1 - center) }
    }

    var repeats: Int { mode == .burst ? max(2, burstCount) : (mode == .focus || mode == .single ? 1 : max(2, framesPerPosition)) }
    var totalFrames: Int { positions.count * repeats }
    var maximumDimension: Int { fullResolution ? 4096 : 2048 }
}

enum MacroError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

