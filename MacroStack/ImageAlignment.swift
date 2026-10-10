import CoreImage
import simd

struct RegisteredFrame {
    let image: CIImage
    let validRect: CGRect
}

enum ImageAlignment {
    /// Vision's warp maps floating-image pixels into reference-image pixels.
    static func warp(_ image: CIImage, matrix: simd_float3x3, registrationScale: CGFloat) throws -> RegisteredFrame {
        let rect = image.extent
        func project(_ x: CGFloat, _ y: CGFloat) throws -> CGPoint {
            let p = matrix * SIMD3<Float>(Float(x * registrationScale), Float(y * registrationScale), 1)
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite, p.z > 0.01 else {
                throw MacroError.message("Unstable alignment. Keep the phone still and reduce the focus range.")
            }
            return CGPoint(x: CGFloat(p.x / p.z) / registrationScale, y: CGFloat(p.y / p.z) / registrationScale)
        }
        let tl = try project(rect.minX, rect.maxY)
        let tr = try project(rect.maxX, rect.maxY)
        let bl = try project(rect.minX, rect.minY)
        let br = try project(rect.maxX, rect.minY)
        let pairs = [(tl, CGPoint(x: rect.minX, y: rect.maxY)), (tr, CGPoint(x: rect.maxX, y: rect.maxY)),
                     (bl, CGPoint(x: rect.minX, y: rect.minY)), (br, CGPoint(x: rect.maxX, y: rect.minY))]
        guard pairs.allSatisfy({ abs($0.0.x - $0.1.x) < rect.width * 0.12 && abs($0.0.y - $0.1.y) < rect.height * 0.12 }),
              tr.x > tl.x, br.x > bl.x, tl.y > bl.y, tr.y > br.y else {
            throw MacroError.message("Too much movement for a clean stack. Support the phone and try a narrower focus range.")
        }
        let left = max(rect.minX, tl.x, bl.x)
        let right = min(rect.maxX, tr.x, br.x)
        let bottom = max(rect.minY, bl.y, br.y)
        let top = min(rect.maxY, tl.y, tr.y)
        let valid = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
        guard valid.width > rect.width * 0.75, valid.height > rect.height * 0.75 else {
            throw MacroError.message("The aligned photos overlap too little. Try a smaller focus range.")
        }
        let warped = image.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(cgPoint: tl), "inputTopRight": CIVector(cgPoint: tr),
            "inputBottomLeft": CIVector(cgPoint: bl), "inputBottomRight": CIVector(cgPoint: br)
        ]).cropped(to: rect)
        return RegisteredFrame(image: warped, validRect: valid)
    }
}
