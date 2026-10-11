import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var model = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHelp = false
    @State private var showProjects = false
    @State private var previewMagnified = false
    private let accent = Color(red: 0.66, green: 0.91, blue: 0.48)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ZStack(alignment: .bottomLeading) {
                        CameraPreview(session: model.camera.session, onFocus: { model.autofocus(at: $0, imagePoint: $1) })
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .background(.black)
                            .overlay {
                                GeometryReader { geometry in
                                    let region = model.settings.subjectRegion
                                    Rectangle().stroke(.yellow.opacity(0.8), lineWidth: 1)
                                        .frame(width: geometry.size.width * region.width, height: geometry.size.height * region.height)
                                        .position(x: geometry.size.width * region.midX, y: geometry.size.height * (1 - region.midY))
                                }.allowsHitTesting(false)
                                if model.settings.showGrid {
                                    GeometryReader { geometry in
                                        Path { path in
                                            for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                                                path.move(to: CGPoint(x: geometry.size.width * fraction, y: 0))
                                                path.addLine(to: CGPoint(x: geometry.size.width * fraction, y: geometry.size.height))
                                                path.move(to: CGPoint(x: 0, y: geometry.size.height * fraction))
                                                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * fraction))
                                            }
                                        }.stroke(.white.opacity(0.35), lineWidth: 0.5)
                                    }.allowsHitTesting(false)
                                }
                            }
                            .scaleEffect(previewMagnified ? 2 : 1)
                        Text("ULTRA WIDE · MACRO")
                            .font(.caption2.monospaced().weight(.semibold))
                            .padding(10).background(.black.opacity(0.6), in: Capsule()).padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12)))

                    Toggle("Magnify preview 2×", isOn: $previewMagnified).font(.caption)
                    Text("Tap the insect's eye. The yellow box marks the area used to judge sharpness. Preview magnification helps check focus; saved photos keep the full view.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.settings.mode.sweepsFocus && !model.isBusy {
                        HStack {
                            Button("Set Near") { model.markEndpoint(near: true) }
                            Button("Set Far") { model.markEndpoint(near: false) }
                            Button("Near ▶") { model.previewFocus(model.settings.near) }
                            Button("Far ▶") { model.previewFocus(model.settings.far) }
                        }.font(.caption).buttonStyle(.bordered).disabled(!model.isReady || model.isAdjusting)
                        Text("Tap the closest detail and Set Near; tap the farthest detail and Set Far. This switches to your manual range.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Text(model.status).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("captureStatus")
                    if model.isBusy {
                        ProgressView(value: model.progress).tint(accent)
                        Button("Cancel capture", role: .cancel) { model.cancel() }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                    } else {
                        Button { model.capture() } label: {
                            Label(model.settings.mode == .single ? "Take photo" : "Capture \(model.settings.totalFrames) photos", systemImage: "camera.aperture")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                        .disabled(!model.isReady || model.isAdjusting)
                        if !model.isReady {
                            Button("Retry camera") { Task { await model.start() } }
                        }
                        controls
                    }
                    Text("Still insect needs a supported phone and a motionless subject. Moving insect uses individual burst photos; keep the insect inside the yellow box. It does not track an insect across the frame.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color(white: 0.055))
            .navigationTitle("MacroStack")
            .toolbar {
                Button { model.suspend(); showProjects = true } label: { Image(systemName: "square.stack") }
                    .accessibilityLabel("Projects and re-stacking").disabled(model.isBusy || model.isAdjusting)
                Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("Capture instructions")
            }
            .task { await model.start() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await model.start() } }
                else if phase == .background { model.suspend() }
            }
            .sheet(isPresented: $showHelp) { help }
            .sheet(isPresented: $showProjects, onDismiss: { Task { await model.start() } }) { ProjectGalleryView() }
            .sheet(item: $model.result) { result in
                if result.mode == .burst { BurstResultView(result: result) }
                else { ResultView(result: result) }
            }
            .alert("MacroStack", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Still insect") { model.settings.useStillInsectPreset() }
                Button("Moving insect") { model.settings.useMovingInsectPreset() }
            }.buttonStyle(.bordered)
            Picker("Stacking", selection: $model.settings.mode) {
                ForEach(StackMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if model.settings.mode == .burst {
                Stepper("Burst photos: \(model.settings.burstCount)", value: $model.settings.burstCount, in: 3...8)
                Picker("Shutter speed", selection: $model.settings.shutterDenominator) {
                    Text("1/250 s").tag(250); Text("1/500 s").tag(500); Text("1/1000 s").tag(1000)
                }.pickerStyle(.segmented)
                Text("Shorter exposures reduce motion blur but need more light and can increase noise. Burst favors capture speed, keeps every original, and never blends frames. It is a sequence of still photos, not high-speed video.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Automatic focus setup", isOn: $model.settings.automaticFocus)
            if model.settings.automaticFocus {
                Button { model.autofocus() } label: {
                    Label(model.isAdjusting ? "Focusing…" : "Focus on subject", systemImage: "scope")
                }.buttonStyle(.bordered).disabled(!model.isReady || model.isAdjusting)
                Text(model.settings.mode == .burst
                     ? "Tap the insect and keep it in that area. Focus is checked before capture, then continuous autofocus adjusts during the burst."
                     : "Tap your subject in the preview. Focus is checked again before capture.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.settings.mode.sweepsFocus {
                    Picker("Focus depth", selection: $model.settings.focusSpan) {
                        Text("Shallow").tag(Float(0.06))
                        Text("Medium").tag(Float(0.12))
                        Text("Deep").tag(Float(0.24))
                    }.pickerStyle(.segmented)
                    Text("Start Shallow for small details. Use a wider sweep for deeper subjects; this is not a depth measurement.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                focusControl(title: model.settings.mode.sweepsFocus ? "Near endpoint" : "Focus position", value: $model.settings.near)
                if model.settings.mode.sweepsFocus { focusControl(title: "Far endpoint", value: $model.settings.far) }
            }
            if model.settings.mode.sweepsFocus {
                Stepper("Focus positions: \(model.settings.focusSteps)", value: $model.settings.focusSteps, in: 3...20)
                Picker("Focus spacing", selection: $model.settings.focusSpacing) {
                    ForEach(FocusSpacing.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text("Near dense puts more focus positions near the closest end. Spacing is based on lens position, not a measured depth map.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.settings.mode != .burst {
                Picker("Capture priority", selection: $model.settings.captureQuality) {
                    ForEach(CaptureQuality.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text("Speed uses lighter camera processing; Quality favors detail. Output resolution stays the same.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.settings.mode == .both || model.settings.mode == .clean {
                Stepper("Photos per position: \(model.settings.framesPerPosition)", value: $model.settings.framesPerPosition, in: 2...6)
            }
            HStack {
                Text("Exposure")
                Spacer()
                Text(String(format: "%+.1f EV", model.settings.exposureBias)).monospacedDigit()
            }
            Slider(value: $model.settings.exposureBias, in: -2...2, step: 0.1, onEditingChanged: { editing in
                if !editing { model.updateExposure() }
            })
            Picker("Capture timer", selection: $model.settings.timerSeconds) {
                Text("Off").tag(0); Text("2 seconds").tag(2); Text("5 seconds").tag(5)
            }
            Toggle("Full resolution", isOn: $model.settings.fullResolution)
            Text(model.settings.fullResolution
                 ? "Uses the captured photo size up to 4096 px on the long edge. More processing time and memory."
                 : "Standard: 2048 px on the long edge. Faster, but discards fine detail.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Save original camera photos", isOn: Binding(get: {
                model.settings.mode == .burst || model.settings.keepOriginals
            }, set: { model.settings.keepOriginals = $0 }))
                .disabled(model.settings.mode == .burst)
            Text("Originals are kept in Files → On My iPhone → MacroStack → Stacks. A stack can use tens of megabytes.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Composition grid", isOn: $model.settings.showGrid)
        }
        .font(.subheadline)
        .tint(accent)
    }

    private func focusControl(title: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
                Button("Preview") { model.previewFocus(value.wrappedValue) }
                    .disabled(!model.isReady || model.isAdjusting)
            }
            Slider(value: value, in: 0...1, onEditingChanged: { editing in
                if !editing { model.previewFocus(value.wrappedValue) }
            })
        }
    }

    private var help: some View {
        NavigationStack {
            List {
                Section("Your first stack") {
                    Text("1. Choose a still subject, such as a coin or a leaf indoors. Support the phone and add soft, steady light.")
                    Text("2. Start a few centimetres away. The Ultra Wide camera stays selected for the entire capture.")
                    Text("3. Leave Automatic focus setup on and tap your subject. Start with Shallow depth for fine details. Autofocus is repeated after the timer, and the sweep starts at that focus position.")
                    Text("4. Choose Still insect: 9 narrow focus positions, one photo per position, Full resolution and a two-second timer. Photos are captured first, then processed. Try Both only if noise is the main issue and everything remains motionless.")
                    Text("5. Pinch or double tap the result to inspect detail. Switch between Stack and Best single without losing your zoom. Save whichever looks better.")
                }
                Section("Modes") {
                    Text("Both averages repeated photos at each focus position, then combines the sharper regions.")
                    Text("Focus captures one photo per position. Noise averages several photos at the single focus position you choose.")
                    Text("Single takes one photo without stacking. Use it for moving subjects or to compare capture quality.")
                    Text("Moving insect selects Burst with 5 photos and a 1/500-second shutter. Continuous autofocus adjusts around the tapped area. Add steady light, keep the insect inside the yellow box, and review each original. Shorter shutter speeds cannot guarantee sharp wings or fast flight.")
                }
                Section("Prototype limits") {
                    Text("Perspective alignment corrects small shifts, rotations and focus breathing when enough shared detail is visible. Strong perspective changes, moving subjects and overlapping surfaces can still cause artifacts. Narrow the focus sweep if alignment fails.")
                    Text("Very soft repeated frames are excluded from averaging. Disagreeing pixels receive less averaging to reduce ghosting; this does not make moving subjects safe to stack.")
                    Text("Processing uses normal camera photos, not RAW. A stack is not guaranteed to beat Apple's Camera processing. Compare results on your own subjects.")
                    Text("Photos are processed on this iPhone. No account or internet connection is needed to take and stack photos.")
                }
                Section("Projects and versions") {
                    Text("Open Projects from the stacked-squares button. Reopen previous captures, inspect originals, exclude moved or blurred frames and re-stack into a separate result. Keep originals enabled when capturing.")
                    Text("Detail sharpening and JPEG/HEIC export create separate files. Set detail to 0% for format conversion alone. This is conventional sharpening, not neural reconstruction or added optical detail.")
                    Text("Hold the comparison label in Projects to show the original result. Earlier captures are supported when their original files and settings remain available.")
                }
            }
            .navigationTitle("Getting started")
            .toolbar { Button("Done") { showHelp = false } }
        }
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
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Comparison", selection: $showReference) {
                        Text("Stack").tag(false)
                        Text("Best single").tag(true)
                    }.pickerStyle(.segmented)
                    ZoomablePhoto(image: showReference ? result.reference : result.image)
                        .frame(height: 440).clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("Pinch to zoom · double tap for detail").font(.caption).foregroundStyle(.secondary)
                    Text("\(result.frames) photos · \(result.positions) focus positions · \(Int(result.image.size.width)) × \(Int(result.image.size.height)) px")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Best single is chosen by detail in the yellow subject box. Both views use the same aligned crop; compare at the same zoom and save the one you prefer.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(result.captureNotes).font(.caption).foregroundStyle(.secondary)
                    if result.rejected > 0 { Text("\(result.rejected) softer photos excluded from averaging.").font(.caption) }
                    if result.fallbacks > 0 { Text("\(result.fallbacks) photos used simpler alignment. Check edges carefully.").font(.caption).foregroundStyle(.orange) }
                    Button(savedSelections.contains(showReference) ? "Saved to Photos" : (saving ? "Saving…" : (showReference ? "Save best single to Photos" : "Save stack to Photos"))) { save() }
                        .buttonStyle(.borderedProminent).disabled(saving || savedSelections.contains(showReference))
                    ShareLink(item: showReference ? result.referenceURL : result.url) {
                        Label(showReference ? "Share best single" : "Share stack", systemImage: "square.and.arrow.up")
                    }
                    Text(result.originalsSaved ? "The original camera photos and both results are saved in Files → On My iPhone → MacroStack → Stacks." : "Both results are saved in Files → On My iPhone → MacroStack → Stacks.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("After Done, open Projects to inspect source frames, re-stack or create a separate detail-enhanced version.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("Your stack")
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
