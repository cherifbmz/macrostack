import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var model = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showProjects = false
    @State private var previewMagnified = false
    @State private var rangeStep = 0
    private let accent = Color(red: 0.78, green: 0.94, blue: 0.52)

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                topBar
                viewfinder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                lensPicker
                modePicker
                captureBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(white: 0.035).ignoresSafeArea())
        .tint(accent)
        .task {
            await model.start()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                await model.refreshHardware()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && !showProjects && model.result == nil { Task { await model.start() } }
            else if phase == .background { model.suspend() }
        }
        .onChange(of: model.selectedCameraID) { _ in rangeStep = 0; previewMagnified = false }
        .sheet(isPresented: $showSettings) {
            CaptureSettingsView(model: model)
        }
        .sheet(isPresented: $showProjects, onDismiss: resumeCamera) { ProjectGalleryView() }
        .sheet(item: $model.result, onDismiss: resumeCamera) { result in
            Group {
                if result.mode == .burst { BurstResultView(result: result) }
                else { ResultView(result: result) }
            }.onAppear { model.suspend() }
        }
        .alert("MacroStack", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func resumeCamera() {
        if scenePhase == .active { Task { await model.start() } }
    }

    private var topBar: some View {
        HStack {
            Text("MacroStack").font(.title3.weight(.semibold)).tracking(-0.5)
            Spacer()
            Button { model.setLight(model.torchLevel > 0 ? 0 : model.lightStrength) } label: {
                Image(systemName: model.torchLevel > 0 ? "flashlight.on.fill" : "flashlight.off.fill")
                    .foregroundStyle(model.torchLevel > 0 ? accent : .white)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Flashlight")
            .accessibilityValue(model.torchLevel > 0 ? "On" : (model.torchAvailable ? "Off" : "Unavailable"))
            .accessibilityIdentifier("flashlightButton")
            .disabled(!model.isReady || model.controlsLocked || (!model.torchAvailable && model.torchLevel == 0))
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 48, height: 48)
            }
            .accessibilityLabel("Capture settings").accessibilityIdentifier("settingsButton")
            .disabled(model.controlsLocked)
        }.foregroundStyle(.white)
    }

    private var viewfinder: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, proxy.size.height * 3 / 4)
            ZStack {
                Color(white: 0.075)
                if model.isReady {
                    CameraPreview(session: model.camera.session, onFocus: { model.autofocus(at: $0, imagePoint: $1) })
                        .frame(width: width, height: width * 4 / 3)
                        .overlay { compositionOverlay }
                        .scaleEffect(previewMagnified ? 2 : 1)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "camera.macro").font(.system(size: 42, weight: .light)).foregroundStyle(accent)
                        Text("Your next close-up").font(.headline)
                        Text(model.status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Open camera") { Task { await model.start() } }
                            .buttonStyle(.bordered).accessibilityIdentifier("retryCamera")
                    }.padding(28)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .overlay(alignment: .topLeading) {
                if model.isReady {
                    Text(model.selectedCamera?.subtitle ?? "Camera")
                        .font(.caption.weight(.medium)).padding(10)
                        .background(.black.opacity(0.55), in: Capsule()).padding(12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if model.isReady {
                    Button { previewMagnified.toggle() } label: {
                        Image(systemName: previewMagnified ? "minus.magnifyingglass" : "plus.magnifyingglass")
                            .frame(width: 44, height: 44).background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel(previewMagnified ? "Normal preview" : "Magnify preview only")
                    .padding(10).disabled(model.isBusy)
                }
            }
            .overlay(alignment: .bottom) {
                if rangeStep > 0 && !model.isBusy { rangeGuide.padding(10) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    private var compositionOverlay: some View {
        GeometryReader { geometry in
            if model.settings.showGrid {
                Path { path in
                    for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                        path.move(to: CGPoint(x: geometry.size.width * fraction, y: 0))
                        path.addLine(to: CGPoint(x: geometry.size.width * fraction, y: geometry.size.height))
                        path.move(to: CGPoint(x: 0, y: geometry.size.height * fraction))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * fraction))
                    }
                }.stroke(.white.opacity(0.35), lineWidth: 0.5)
            }
            let region = model.settings.subjectRegion
            RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.65), lineWidth: 1)
                .frame(width: geometry.size.width * region.width, height: geometry.size.height * region.height)
                .position(x: geometry.size.width * region.midX, y: geometry.size.height * (1 - region.midY))
        }.allowsHitTesting(false)
    }

    private var rangeGuide: some View {
        VStack(spacing: 6) {
            HStack {
                Text(rangeStep == 1 ? "1 · Tap the nearest detail" : (rangeStep == 2 ? "2 · Tap the farthest detail" : "Focus range ready"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    rangeStep = 0
                    model.settings.automaticFocus = true
                } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Use automatic focus range")
            }
            HStack {
                if rangeStep < 3 {
                    Button(rangeStep == 1 ? "Set near point" : "Set far point") {
                        model.markEndpoint(near: rangeStep == 1)
                        rangeStep += 1
                    }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                } else {
                    Button("Preview near") { model.previewFocus(model.settings.near) }
                    Button("Preview far") { model.previewFocus(model.settings.far) }
                    Button("Done") { rangeStep = 0 }
                }
            }.buttonStyle(.bordered).disabled(!model.isReady || model.controlsLocked)
        }.padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var lensPicker: some View {
        HStack(spacing: 6) {
            ForEach(model.cameras) { camera in
                Button { model.switchCamera(to: camera.id) } label: {
                    Text(camera.title).font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(minHeight: 44)
                        .foregroundStyle(model.selectedCameraID == camera.id ? .black : .white)
                        .background(model.selectedCameraID == camera.id ? accent : Color(white: 0.12), in: Capsule())
                }
                .accessibilityLabel(camera.subtitle)
                .accessibilityAddTraits(model.selectedCameraID == camera.id ? .isSelected : [])
                .disabled(!model.isReady || model.controlsLocked)
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(ShootingStyle.allCases) { style in
                Button {
                    rangeStep = 0
                    model.selectStyle(style)
                } label: {
                    VStack(spacing: 5) {
                        Text(style.rawValue).font(.subheadline.weight(.semibold))
                        Capsule().fill(ShootingStyle.selected(for: model.settings.mode) == style ? accent : .clear)
                            .frame(width: 18, height: 3)
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(ShootingStyle.selected(for: model.settings.mode) == style ? accent : .white.opacity(0.6))
                .accessibilityIdentifier("mode" + style.rawValue)
                .accessibilityAddTraits(ShootingStyle.selected(for: model.settings.mode) == style ? .isSelected : [])
                .disabled(model.controlsLocked || (style == .still && !model.canStackFocus) || (style == .moving && !model.canUseMoving))
            }
        }
    }

    private var captureBar: some View {
        VStack(spacing: 6) {
            if model.isBusy {
                ProgressView(value: model.progress).tint(accent)
                Text(model.status).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                    .accessibilityIdentifier("captureStatus")
            } else {
                Text(captureHint).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .accessibilityIdentifier("captureStatus")
            }
            HStack {
                Button { model.suspend(); showProjects = true } label: {
                    VStack(spacing: 5) { Image(systemName: "square.stack").font(.title3); Text("Projects").font(.caption2) }
                        .frame(width: 76, height: 64)
                }.accessibilityIdentifier("projectsButton").disabled(model.controlsLocked)
                Spacer(minLength: 10)
                Button {
                    if model.isBusy { model.cancel() } else { rangeStep = 0; model.capture() }
                } label: {
                    ZStack {
                        Circle().stroke(.white.opacity(0.9), lineWidth: 3).frame(width: 76, height: 76)
                        if model.isBusy { RoundedRectangle(cornerRadius: 6).fill(accent).frame(width: 26, height: 26) }
                        else { Circle().fill(accent).frame(width: 62, height: 62) }
                    }.frame(width: 84, height: 84)
                }
                .accessibilityLabel(model.isBusy ? "Cancel capture" : (model.settings.mode == .single ? "Take photo" : "Capture \(model.settings.totalFrames) photos"))
                .accessibilityIdentifier("shutterButton")
                .disabled(!model.isBusy && (!model.isReady || model.controlsLocked))
                Spacer(minLength: 10)
                Button {
                    if model.settings.mode.sweepsFocus { rangeStep = rangeStep == 0 ? 1 : 0 }
                    else { model.autofocus() }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "viewfinder").font(.title3)
                        Text(model.settings.mode.sweepsFocus ? "Focus range" : "Focus").font(.caption2)
                    }.frame(width: 76, height: 64)
                }.disabled(!model.isReady || model.controlsLocked || !model.canStackFocus)
            }.foregroundStyle(.white)
        }
        .frame(minHeight: 116)
    }

    private var captureHint: String {
        if model.isAdjusting { return "Focusing…" }
        if !model.isReady { return "Camera preview appears here when available" }
        if rangeStep > 0 { return "Tap the subject, wait for focus, then set the point" }
        if model.settings.mode == .burst { return "Moving · \(model.settings.burstCount) photos · 1/\(model.settings.shutterDenominator) s" }
        if model.settings.mode == .single { return "One photo · Tap to focus" }
        return "\(model.settings.totalFrames) photos · \(model.settings.automaticFocus ? "Auto focus range" : "Custom focus range") · Hold still"
    }
}

private struct ResultView: View {
    let result: StackResult
    @Environment(\.dismiss) private var dismiss
    @State private var showReference = false
    @State private var saving = false
    @State private var savedSelections: Set<Bool> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if result.mode != .single {
                    Picker("Comparison", selection: $showReference) {
                        Text("Stack").tag(false)
                        Text("Best single").tag(true)
                    }.pickerStyle(.segmented)
                }
                ZoomablePhoto(image: showReference ? result.reference : result.image)
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Text("Pinch to zoom · double tap for detail").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Button(savedSelections.contains(showReference) ? "Saved" : (saving ? "Saving…" : "Save to Photos")) { save() }
                        .buttonStyle(.borderedProminent).disabled(saving || savedSelections.contains(showReference))
                    ShareLink(item: showReference ? result.referenceURL : result.url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.bordered)
                }.controlSize(.large)
                DisclosureGroup("Photo details") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(result.frames) photos · \(Int(result.image.size.width)) × \(Int(result.image.size.height)) px")
                            Text(result.captureNotes)
                            if result.rejected > 0 { Text("\(result.rejected) softer photos excluded.") }
                            if result.fallbacks > 0 { Text("\(result.fallbacks) photos used simpler alignment. Check edges carefully.") }
                            Text("Saved in Projects. Close this photo to inspect originals, re-stack, or adjust detail there.")
                        }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 120)
                }.font(.subheadline)
            }
            .padding()
            .navigationTitle(result.mode == .single ? "Your photo" : "Your stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        saving = true
        let selection = showReference
        let url = selection ? result.referenceURL : result.url
        Task { @MainActor in
            defer { saving = false }
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                errorMessage = "Allow MacroStack to add photos in Settings, or use Share to save a copy to Files."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
                savedSelections.insert(selection)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
