import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var magnification: CGFloat = 1
    var focusEnabled = true
    var onTapObserved: (() -> Void)? = nil
    var onFocus: (CGPoint, CGPoint) -> Void

    /// The UIView stays the size of the visible viewport. Only the video layer grows.
    /// Scaling the representable itself lets its gesture recognizer reach adjacent controls.
    final class PreviewView: UIView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var onFocus: ((CGPoint, CGPoint) -> Void)?
        var onTapObserved: (() -> Void)?
        var focusEnabled = true
        var magnification: CGFloat = 1 {
            didSet { setNeedsLayout() }
        }
        private let focusRing = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            layer.addSublayer(previewLayer)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            focusRing.layer.borderColor = UIColor.systemYellow.cgColor
            focusRing.layer.borderWidth = 2
            focusRing.layer.cornerRadius = 8
            focusRing.isUserInteractionEnabled = false
            focusRing.isHidden = true
            addSubview(focusRing)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let zoom = max(1, min(2, magnification))
            previewLayer.bounds = CGRect(x: 0, y: 0, width: bounds.width * zoom, height: bounds.height * zoom)
            previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            bounds.contains(point) && super.point(inside: point, with: event)
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: self)
            guard focusEnabled, bounds.contains(location) else { return }
            onTapObserved?()
            let layerRect = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            let videoRect = layer.convert(layerRect, from: previewLayer)
            guard videoRect.width > 0, videoRect.height > 0, videoRect.contains(location) else { return }
            focusRing.frame = CGRect(x: location.x - 28, y: location.y - 28, width: 56, height: 56)
            focusRing.alpha = 1; focusRing.isHidden = false
            UIView.animate(withDuration: 0.4, delay: 1.2, options: [], animations: { self.focusRing.alpha = 0 }, completion: nil)
            let imagePoint = CGPoint(x: (location.x - videoRect.minX) / videoRect.width,
                                     y: 1 - (location.y - videoRect.minY) / videoRect.height)
            let layerPoint = previewLayer.convert(location, from: layer)
            onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint), imagePoint)
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.onFocus = onFocus
        view.onTapObserved = onTapObserved
        view.focusEnabled = focusEnabled
        if view.magnification != magnification { view.magnification = magnification }
        if let connection = view.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }
}
