import Foundation

enum StackMode: String, CaseIterable, Identifiable {
    case both = "Both"
    case focus = "Focus"
    case clean = "Noise"
    var id: String { rawValue }
}

struct StackSettings {
    var mode: StackMode = .both
    var near: Float = 0.05
    var far: Float = 0.35
    var focusSteps = 6
    var framesPerPosition = 3
    var fullResolution = false

    var positions: [Float] {
        if mode == .clean { return [near] }
        let lower = max(0, min(near, far))
        let upper = min(1, max(near, far))
        let count = max(2, focusSteps)
        return (0..<count).map { lower + (upper - lower) * Float($0) / Float(count - 1) }
    }

    var repeats: Int { mode == .focus ? 1 : max(2, framesPerPosition) }
    var totalFrames: Int { positions.count * repeats }
    var maximumDimension: Int { fullResolution ? 4096 : 2048 }
}

enum MacroError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

