import SwiftUI
import Photos
import ImageIO

struct BurstResultView: View {
    let result: StackResult
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Int
    @State private var photo: UIImage
    @State private var loadedIndex: Int?
    @State private var metadata = ""
    @State private var saving = false
    @State private var saved: Set<URL> = []
    @State private var errorMessage: String?

    init(result: StackResult) {
        self.result = result
        _selected = State(initialValue: result.bestFrameIndex)
        _photo = State(initialValue: result.image)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("Individual photos — no stacking").font(.headline)
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(result.candidates.indices, id: \.self) { index in
                                Button("\(index + 1)" + (index == result.bestFrameIndex ? " ★" : "")) { selected = index }
                                    .buttonStyle(.bordered)
                                    .tint(index == selected ? .green : .gray)
                                    .accessibilityLabel("Photo \(index + 1)" + (index == result.bestFrameIndex ? ", suggested sharpest" : ""))
                            }
                        }
                    }
                    ZoomablePhoto(image: photo).frame(height: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay { if loadedIndex != selected { ProgressView().padding().background(.regularMaterial, in: Capsule()) } }
                    Text("Pinch to inspect the eye and fine hairs. ★ is a suggestion based on detail in the tapped area; choose another photo if it looks better.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(metadata).font(.caption.monospaced())
                    Text(result.captureNotes).font(.caption).foregroundStyle(.secondary)
                    Button(saving ? "Saving…" : (saved.contains(selectedURL) ? "Saved to Photos" : "Save photo \(selected + 1) to Photos")) { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(saving || loadedIndex != selected || saved.contains(selectedURL))
                    ShareLink(item: selectedURL) { Label("Share original photo \(selected + 1)", systemImage: "square.and.arrow.up") }
                        .disabled(loadedIndex != selected)
                    Text("Every original is also in Files → On My iPhone → MacroStack → Stacks. Saving and sharing use the original camera file.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("Your insect burst")
            .toolbar { Button("Done") { dismiss() } }
            .task(id: selected) {
                let index = selected
                let url = result.candidates[index]
                loadedIndex = nil
                do {
                    let preview = try await Task.detached(priority: .userInitiated) { try Self.load(url) }.value
                    try Task.checkCancellation()
                    photo = preview.0; metadata = preview.1; loadedIndex = index
                } catch is CancellationError { }
                catch { errorMessage = error.localizedDescription }
            }
            .alert("MacroStack", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var selectedURL: URL { result.candidates[selected] }

    nonisolated private static func load(_ url: URL) throws -> (UIImage, String) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else { throw MacroError.message("Could not load this original photo.") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        var detail: [String] = []
        if let time = exif?[kCGImagePropertyExifExposureTime] as? Double, time > 0 {
            detail.append("1/\(Int((1 / time).rounded())) s")
        }
        if let iso = (exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first {
            detail.append("ISO \(iso.intValue)")
        }
        return (UIImage(cgImage: cg), detail.joined(separator: " · "))
    }

    private func save() {
        let url = selectedURL
        saving = true
        Task { @MainActor in
            defer { saving = false }
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                errorMessage = "Allow MacroStack to add photos in Settings, or share the original to Files."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
                saved.insert(url)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
