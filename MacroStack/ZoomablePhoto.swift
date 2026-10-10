import SwiftUI

struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage

    final class PhotoScrollView: UIScrollView, UIScrollViewDelegate {
        let photoView = UIImageView()
        private var fittedBounds = CGSize.zero
        private var imageSize = CGSize.zero

        override init(frame: CGRect) {
            super.init(frame: frame)
            delegate = self
            backgroundColor = .black
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            addSubview(photoView)
            let gesture = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
            gesture.numberOfTapsRequired = 2
            addGestureRecognizer(gesture)
            accessibilityLabel = "Photo. Pinch to zoom or double tap to inspect detail."
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func setImage(_ image: UIImage) {
            photoView.image = image
            if imageSize != image.size {
                imageSize = image.size
                fittedBounds = .zero
                setZoomScale(1, animated: false)
                photoView.frame = CGRect(origin: .zero, size: image.size)
            }
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard imageSize.width > 0, bounds.width > 0, bounds.height > 0 else { return }
            if fittedBounds != bounds.size {
                fittedBounds = bounds.size
                minimumZoomScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
                maximumZoomScale = max(minimumZoomScale * 8, 2)
                setZoomScale(minimumZoomScale, animated: false)
            }
            centerPhoto()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { photoView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }
        private func centerPhoto() {
            contentInset = UIEdgeInsets(top: max(0, (bounds.height - contentSize.height) / 2), left: max(0, (bounds.width - contentSize.width) / 2), bottom: 0, right: 0)
        }
        @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
            if zoomScale > minimumZoomScale * 1.1 { setZoomScale(minimumZoomScale, animated: true); return }
            let target = min(maximumZoomScale, max(minimumZoomScale * 3, 1 / UIScreen.main.scale))
            let point = gesture.location(in: photoView)
            let size = CGSize(width: bounds.width / target, height: bounds.height / target)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    func makeUIView(context: Context) -> PhotoScrollView {
        let view = PhotoScrollView()
        view.setImage(image)
        return view
    }
    func updateUIView(_ view: PhotoScrollView, context: Context) { view.setImage(image) }
}
