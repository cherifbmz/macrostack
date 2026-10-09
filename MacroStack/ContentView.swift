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
                        CameraPreview(session: model.camera.session)
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .background(.black)
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
                            Label("Capture \(model.settings.totalFrames) photos", systemImage: "camera.aperture")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                        .disabled(!model.isReady || model.isAdjusting)
                        if !model.isReady {
                            Button("Retry camera") { Task { await model.start() } }
                        }
                    }
                    Text("Support the phone. Keep your subject still and well lit. Stacking may take tens of seconds.")
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
            focusControl(title: model.settings.mode == .clean ? "Focus position" : "Near endpoint", value: $model.settings.near)
            if model.settings.mode != .clean {
                focusControl(title: "Far endpoint", value: $model.settings.far)
                Stepper("Focus positions: \(model.settings.focusSteps)", value: $model.settings.focusSteps, in: 3...12)
            }
            if model.settings.mode != .focus {
                Stepper("Photos per position: \(model.settings.framesPerPosition)", value: $model.settings.framesPerPosition, in: 2...6)
            }
            Toggle("Full resolution", isOn: $model.settings.fullResolution)
            Text(model.settings.fullResolution
                 ? "Uses the captured photo size up to 4096 px on the long edge. More processing time and memory."
                 : "Standard: up to 2048 px on the long edge. Use this for your first tests.")
                .font(.caption).foregroundStyle(.secondary)
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
                    Text("3. Adjust Near and tap Preview until the closest detail is sharp. Adjust Far and preview the furthest detail you want sharp. Focus numbers are lens positions, not distances.")
                    Text("4. Start with Both, 6 focus positions and 3 photos per position. Let the exposure settle, then capture without moving the phone.")
                    Text("5. Compare the stack against the first photo. Save or share the result when you are happy with it.")
                }
                Section("Modes") {
                    Text("Both averages repeated photos at each focus position, then combines the sharper regions.")
                    Text("Focus captures one photo per position. Noise averages several photos at the single focus position you choose.")
                }
                Section("Prototype limits") {
                    Text("Small horizontal and vertical shifts are corrected. Rotation, focus breathing, moving subjects and complex overlapping edges are not fully corrected. These can cause blur or halos.")
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
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Comparison", selection: $showReference) {
                        Text("Stack").tag(false)
                        Text("First photo").tag(true)
                    }.pickerStyle(.segmented)
                    Image(uiImage: showReference ? result.reference : result.image)
                        .resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("\(result.frames) photos · \(result.positions) focus positions · \(Int(result.image.size.width)) × \(Int(result.image.size.height)) px")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("The first photo is a reference, not necessarily the best single shot. Alignment slightly crops the stack.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(saved ? "Saved to Photos" : (saving ? "Saving…" : "Save stack to Photos")) { save() }
                        .buttonStyle(.borderedProminent).disabled(saving || saved)
                    ShareLink(item: showReference ? result.referenceURL : result.url) {
                        Label(showReference ? "Share first photo" : "Share stack", systemImage: "square.and.arrow.up")
                    }
                    Text("A JPEG copy is also stored in this app's Documents/Stacks folder.")
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
        Task { @MainActor in
            defer { saving = false }
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                errorMessage = "Allow MacroStack to add photos in Settings, or use Share to save a copy to Files."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: result.url)
                }
                saved = true
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
