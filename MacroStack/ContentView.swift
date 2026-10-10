import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var model = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHelp = false
    private let accent = Color(red: 0.66, green: 0.91, blue: 0.48)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ZStack(alignment: .bottomLeading) {
                        CameraPreview(session: model.camera.session, onFocus: { model.autofocus(at: $0) })
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .background(.black)
                            .overlay {
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
                        Text("ULTRA WIDE · MACRO")
                            .font(.caption2.monospaced().weight(.semibold))
                            .padding(10).background(.black.opacity(0.6), in: Capsule()).padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12)))

                    Text(model.status).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("captureStatus")
                    if model.isBusy {
                        ProgressView(value: model.progress).tint(accent)
                        Button("Cancel capture", role: .cancel) { model.cancel() }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                    } else {
                        controls
                        Button { model.capture() } label: {
                            Label(model.settings.mode == .single ? "Take photo" : "Capture \(model.settings.totalFrames) photos", systemImage: "camera.aperture")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                        .disabled(!model.isReady || model.isAdjusting)
                        if !model.isReady {
                            Button("Retry camera") { Task { await model.start() } }
                        }
                    }
                    Text("For stacks, support the phone and keep your subject still. Use Single for moving subjects. Full-size stacks take longer.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color(white: 0.055))
            .navigationTitle("MacroStack")
            .toolbar { Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("Capture instructions") }
            .task { await model.start() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await model.start() } }
                else if phase == .background { model.suspend() }
            }
            .sheet(isPresented: $showHelp) { help }
            .sheet(item: $model.result) { ResultView(result: $0) }
            .alert("MacroStack", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Stacking", selection: $model.settings.mode) {
                ForEach(StackMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Toggle("Automatic focus setup", isOn: $model.settings.automaticFocus)
            if model.settings.automaticFocus {
                Button { model.autofocus() } label: {
                    Label(model.isAdjusting ? "Focusing…" : "Focus on subject", systemImage: "scope")
                }.buttonStyle(.bordered).disabled(!model.isReady || model.isAdjusting)
                Text("Tap your subject in the preview. Focus is checked again before capture.")
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
                Stepper("Focus positions: \(model.settings.focusSteps)", value: $model.settings.focusSteps, in: 3...12)
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
            Toggle("Save original camera photos", isOn: $model.settings.keepOriginals)
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
                    Text("4. Start with Both, 7 focus positions and 2 photos per position. Full resolution retains the camera's detail. Use the 2-second timer to reduce shutter-tap shake.")
                    Text("5. Pinch or double tap the result to inspect detail. Switch between Stack and Best single without losing your zoom. Save whichever looks better.")
                }
                Section("Modes") {
                    Text("Both averages repeated photos at each focus position, then combines the sharper regions.")
                    Text("Focus captures one photo per position. Noise averages several photos at the single focus position you choose.")
                    Text("Single takes one photo without stacking. Use it for moving subjects or to compare capture quality.")
                }
                Section("Prototype limits") {
                    Text("Perspective alignment corrects small shifts, rotations and focus breathing when enough shared detail is visible. Strong perspective changes, moving subjects and overlapping surfaces can still cause artifacts. Narrow the focus sweep if alignment fails.")
                    Text("Very soft repeated frames are excluded from averaging. Disagreeing pixels receive less averaging to reduce ghosting; this does not make moving subjects safe to stack.")
                    Text("Processing uses normal camera photos, not RAW. A stack is not guaranteed to beat Apple's Camera processing. Compare results on your own subjects.")
                    Text("Photos are processed on this iPhone. No account or internet connection is needed to take and stack photos.")
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
                    Text("Best single is chosen by an overall detail score. Both views use the same aligned crop; compare at the same zoom and save the one you prefer.")
                        .font(.caption).foregroundStyle(.secondary)
                    if result.rejected > 0 { Text("\(result.rejected) softer photos excluded from averaging.").font(.caption) }
                    if result.fallbacks > 0 { Text("\(result.fallbacks) photos used simpler alignment. Check edges carefully.").font(.caption).foregroundStyle(.orange) }
                    Button(savedSelections.contains(showReference) ? "Saved to Photos" : (saving ? "Saving…" : (showReference ? "Save best single to Photos" : "Save stack to Photos"))) { save() }
                        .buttonStyle(.borderedProminent).disabled(saving || savedSelections.contains(showReference))
                    ShareLink(item: showReference ? result.referenceURL : result.url) {
                        Label(showReference ? "Share best single" : "Share stack", systemImage: "square.and.arrow.up")
                    }
                    Text(result.originalsSaved ? "The original camera photos and both results are saved in Files → On My iPhone → MacroStack → Stacks." : "Both results are saved in Files → On My iPhone → MacroStack → Stacks.")
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
