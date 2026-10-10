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
        let count = max(2, focusSteps)
        let center = automaticFocus ? focusCenter : (lower + upper) / 2
        // Capture the focused subject first, giving registration a useful sharp reference.
        var values = (0..<count).map { lower + (upper - lower) * Float($0) / Float(count - 1) }
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

