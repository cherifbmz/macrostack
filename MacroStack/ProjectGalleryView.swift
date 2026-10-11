import SwiftUI
import Photos

@MainActor
struct ProjectGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [SavedProject] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Reading saved projects…") }
                if !loading && projects.isEmpty {
                    Text("Your captures appear here automatically. Keep original camera photos enabled to re-stack them later.")
                }
                ForEach(projects) { project in
                    NavigationLink {
                        ProjectDetailView(project: project)
                    } label: {
                        HStack(spacing: 12) {
                            PhotoThumbnail(url: project.cover).frame(width: 64, height: 72).clipped()
                            VStack(alignment: .leading, spacing: 5) {
                                Text(project.date, style: .date).font(.headline)
                                Text(project.date, style: .time).font(.caption)
                                Text("\(project.settings?.mode.rawValue ?? "Capture") · \(project.frames.count) originals · \(project.versions.count) versions")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar { Button("Done") { dismiss() } }
            .task {
                do { projects = try await Task.detached(priority: .utility) { try ProjectFiles.list() }.value }
                catch { errorMessage = error.localizedDescription }
                loading = false
            }
            .alert("Projects", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}

@MainActor
struct ProjectDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: ProjectModel
    @State private var displayed: UIImage?
    @State private var original: UIImage?
    @State private var loadedURL: URL?
    @State private var holdOriginal = false
    @State private var inspectFrame: SourceFrame?

    init(project: SavedProject) { _model = StateObject(wrappedValue: ProjectModel(project: project)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !model.project.versions.isEmpty { versionViewer }
                if model.isProcessing {
                    ProgressView(value: model.progress)
                    Text(model.status).font(.caption)
                    Button("Cancel processing", role: .cancel) { model.cancel() }
                } else {
                    if !model.status.isEmpty { Text(model.status).font(.caption).foregroundStyle(.secondary) }
                    if model.selectedVersion != nil { versionTools }
                }
                sourceTools
                Text("Original captures and previous results are preserved. Versions may have different alignment crops. These files are stored on this iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle("Inspect & re-stack")
        .onDisappear { model.cancel() }
        .onChange(of: scenePhase) { if $0 == .background { model.cancel() } }
        .task(id: model.selectedVersion) {
            guard let source = model.selectedVersion else { return }
            loadedURL = nil
            let master = model.project.directory.appendingPathComponent("MacroStack.jpg")
            do {
                let pair = try await Task.detached(priority: .userInitiated) {
                    let image = try ProjectFiles.preview(source)
                    return (image, try? ProjectFiles.preview(master))
                }.value
                try Task.checkCancellation()
                displayed = UIImage(cgImage: pair.0)
                original = pair.1.map { UIImage(cgImage: $0) }
                loadedURL = source
            } catch is CancellationError { }
            catch { model.errorMessage = error.localizedDescription }
        }
        .sheet(item: $inspectFrame) { FrameInspectView(frame: $0) }
        .alert("Project", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var versionViewer: some View {
        VStack(spacing: 12) {
            Picker("Version", selection: $model.selectedVersion) {
                ForEach(model.project.versions, id: \.self) { url in Text(ProjectFiles.title(url)).tag(Optional(url)) }
            }.disabled(model.isProcessing)
            if let displayed {
                ZoomablePhoto(image: holdOriginal ? (original ?? displayed) : displayed)
                    .frame(height: 390).clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay { if loadedURL != model.selectedVersion { ProgressView() } }
            } else { ProgressView().frame(height: 200) }
            if original != nil {
                Text(holdOriginal ? "Original result" : "Press and hold to compare with original")
                    .font(.caption).padding(12).frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .onLongPressGesture(minimumDuration: 0.01, maximumDistance: 80, pressing: { holdOriginal = $0 }, perform: {})
            }
            if let url = model.selectedVersion {
                HStack {
                    SavePhotoButton(url: url)
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }.disabled(model.isProcessing || loadedURL != url)
            }
        }
    }

    private var versionTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Separate detail / export version").font(.headline)
            Slider(value: $model.detailAmount, in: 0...1, step: 0.05)
            Text("Detail sharpening: \(Int(model.detailAmount * 100))% · set 0% to export without extra sharpening.")
                .font(.caption)
            Text("This adjusts existing edges, not AI reconstruction. Excess sharpening can exaggerate noise and halos. Start from Original result for each adjustment.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("File format", selection: $model.exportFormat) {
                ForEach(PhotoExport.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Button("Create new version") { model.makeVersion() }.buttonStyle(.borderedProminent)
                .disabled(loadedURL != model.selectedVersion)
        }
    }

    private var sourceTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Original frames").font(.headline)
            if model.project.frames.isEmpty {
                Text("This project has no retained originals. Enable Save original camera photos for future captures.").font(.caption)
            } else {
                if model.project.canRestack {
                    Text("Inspect frames, then exclude blurred or moved photos before re-stacking. Excluded files stay saved.").font(.caption)
                    HStack {
                        Button("Include all") { model.included = Set(model.project.frames.map(\.url)) }
                        Button("Clear selection") { model.included = [] }
                    }
                } else {
                    Text("Burst frames stay separate. Inspect and save the original you prefer.").font(.caption)
                }
                LazyVStack {
                  ForEach(model.project.frames) { frame in
                    HStack {
                        Button { inspectFrame = frame } label: {
                            HStack {
                                PhotoThumbnail(url: frame.url).frame(width: 56, height: 56).clipped()
                                Text("Photo \(frame.number)")
                            }
                        }
                        Spacer()
                        if model.project.canRestack {
                            Toggle("Include photo \(frame.number)", isOn: Binding(get: { model.included.contains(frame.url) }, set: {
                                if $0 { model.included.insert(frame.url) } else { model.included.remove(frame.url) }
                            })).labelsHidden()
                        }
                    }
                  }
                }
                if model.project.canRestack {
                    Toggle("Full resolution", isOn: $model.fullResolution)
                    Toggle("Align frames", isOn: $model.alignFrames)
                    Toggle("Protect moving pixels in averaging", isOn: $model.protectMotion)
                    Text("Keep alignment on for lens breathing. Motion protection affects repeated frames at the same focus position; it cannot make a moving insect safe to focus-stack.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Re-stack \(model.included.count) selected frames") { model.restack() }
                        .buttonStyle(.borderedProminent).disabled(model.included.isEmpty)
                }
            }
        }.disabled(model.isProcessing)
    }
}

struct PhotoThumbnail: View {
    let url: URL?
    @State private var photo: UIImage?
    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            if let photo { Image(uiImage: photo).resizable().scaledToFill() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }.task(id: url) {
            guard let url else { return }
            let cg = try? await Task.detached(priority: .utility) { try ProjectFiles.preview(url, maximumDimension: 180) }.value
            guard !Task.isCancelled else { return }
            photo = cg.map { UIImage(cgImage: $0) }
        }
    }
}

struct FrameInspectView: View {
    let frame: SourceFrame
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let image { ZoomablePhoto(image: image) }
                else if failed { Text("Could not read this source photo.") }
                else { ProgressView() }
                HStack {
                    SavePhotoButton(url: frame.url)
                    ShareLink(item: frame.url) { Label("Share original", systemImage: "square.and.arrow.up") }
                }.padding()
            }
            .navigationTitle("Original photo \(frame.number)")
            .toolbar { Button("Done") { dismiss() } }
            .task {
                let url = frame.url
                let cg = try? await Task.detached(priority: .userInitiated) { try ProjectFiles.preview(url) }.value
                guard !Task.isCancelled else { return }
                image = cg.map { UIImage(cgImage: $0) }; failed = cg == nil
            }
        }
    }
}

struct SavePhotoButton: View {
    let url: URL
    @State private var saving = false
    @State private var saved: Set<URL> = []
    @State private var errorMessage: String?
    var body: some View {
        Button(saving ? "Saving…" : (saved.contains(url) ? "Saved" : "Save to Photos")) {
            let selected = url
            saving = true
            Task { @MainActor in
                defer { saving = false }
                let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard permission == .authorized || permission == .limited else {
                    errorMessage = "Allow photo access in Settings, or share to Files."; return
                }
                do {
                    try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: selected) }
                    saved.insert(selected)
                } catch { errorMessage = error.localizedDescription }
            }
        }.buttonStyle(.bordered).disabled(saving || saved.contains(url))
            .alert("Save photo", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }
}
