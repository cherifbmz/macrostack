import Foundation

struct ExposurePlan {
    let seconds: Double
    let iso: Float
    let needsMoreLight: Bool

    static func make(meteredSeconds: Double, meteredISO: Float, denominator: Int,
                     minimumSeconds: Double, maximumSeconds: Double, minimumISO: Float, maximumISO: Float) throws -> ExposurePlan {
        guard meteredSeconds.isFinite, meteredSeconds > 0, meteredISO.isFinite, meteredISO > 0,
              denominator > 0, minimumSeconds.isFinite, maximumSeconds.isFinite,
              minimumSeconds > 0, maximumSeconds >= minimumSeconds,
              minimumISO.isFinite, maximumISO.isFinite, minimumISO > 0, maximumISO >= minimumISO else {
            throw MacroError.message("The camera returned invalid exposure limits.")
        }
        let seconds = max(minimumSeconds, min(maximumSeconds, 1 / Double(denominator)))
        let neededISO = Double(meteredISO) * meteredSeconds / seconds
        return ExposurePlan(seconds: seconds, iso: Float(max(Double(minimumISO), min(Double(maximumISO), neededISO))),
                            needsMoreLight: neededISO > Double(maximumISO) * 1.05)
    }

    var summary: String {
        let exposure = "1/\(Int((1 / seconds).rounded())) s · ISO \(Int(iso.rounded()))"
        return needsMoreLight ? exposure + " · ISO limit reached; add light to avoid a dark photo." : exposure
    }
}
