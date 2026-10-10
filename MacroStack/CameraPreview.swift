import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onFocus: (CGPoint, CGPoint) -> Void

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onFocus: ((CGPoint, CGPoint) -> Void)?
        private let focusRing = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            focusRing.layer.borderColor = UIColor.systemYellow.cgColor
            focusRing.layer.borderWidth = 2
            focusRing.layer.cornerRadius = 8
            focusRing.isUserInteractionEnabled = false
            focusRing.isHidden = true
            addSubview(focusRing)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: self)
            let videoRect = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            guard videoRect.contains(location) else { return }
            focusRing.frame = CGRect(x: location.x - 28, y: location.y - 28, width: 56, height: 56)
            focusRing.alpha = 1; focusRing.isHidden = false
            UIView.animate(withDuration: 0.4, delay: 1.2, options: [], animations: { self.focusRing.alpha = 0 }, completion: nil)
            let imagePoint = CGPoint(x: (location.x - videoRect.minX) / videoRect.width,
                                     y: 1 - (location.y - videoRect.minY) / videoRect.height)
            onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: location), imagePoint)
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        view.onFocus = onFocus
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.onFocus = onFocus
        if let connection = view.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}

