import Foundation

struct CameraChoice: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let supportsFocusStack: Bool
    let supportsCustomExposure: Bool
    let hasTorch: Bool

    func supports(_ mode: StackMode) -> Bool {
        if mode.sweepsFocus { return supportsFocusStack }
        if mode == .burst { return supportsCustomExposure }
        return true
    }
}

struct CameraHardwareState: Sendable {
    let cameras: [CameraChoice]
    let selectedID: String?
    let torchAvailable: Bool
    let torchLevel: Float
    var selected: CameraChoice? { cameras.first { $0.id == selectedID } }
}

enum ShootingStyle: String, CaseIterable, Identifiable {
    case still = "Still", moving = "Moving", photo = "Photo"
    var id: String { rawValue }

    static func selected(for mode: StackMode) -> ShootingStyle {
        mode == .burst ? .moving : (mode == .single ? .photo : .still)
    }
}
