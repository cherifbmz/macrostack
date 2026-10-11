import SwiftUI

struct CaptureSettingsView: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(model.selectedCamera?.subtitle ?? "No camera connected", systemImage: "camera")
                    if let camera = model.selectedCamera, !camera.supportsFocusStack {
                        Text("This lens cannot sweep focus. Use Photo, Noise or supported Moving capture.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Capture") {
                    Picker("Timer", selection: $model.settings.timerSeconds) {
                        Text("Off").tag(0); Text("2 seconds").tag(2); Text("5 seconds").tag(5)
                    }
                    if model.settings.mode.sweepsFocus {
                        Picker("Subject depth", selection: $model.settings.focusSpan) {
                            Text("Shallow").tag(Float(0.06)); Text("Medium").tag(Float(0.12)); Text("Deep").tag(Float(0.24))
                        }.disabled(!model.settings.automaticFocus)
                        Stepper("Focus positions: \(model.settings.focusSteps)", value: $model.settings.focusSteps, in: 3...20)
                        Text("Start shallow. More positions take longer and need a still subject.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.settings.mode == .burst {
                        Stepper("Burst photos: \(model.settings.burstCount)", value: $model.settings.burstCount, in: 3...8)
                        Picker("Shutter", selection: $model.settings.shutterDenominator) {
                            Text("1/250 s").tag(250); Text("1/500 s").tag(500); Text("1/1000 s").tag(1000)
                        }
                        Text("Faster shutters need more light. Review the originals to choose your best photo.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Priority", selection: $model.settings.captureQuality) {
                            ForEach(CaptureQuality.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    Toggle("Full resolution", isOn: $model.settings.fullResolution)
                    Toggle("Grid", isOn: $model.settings.showGrid)
                }
                Section("Light & exposure") {
                    Toggle("Flashlight", isOn: Binding(get: { model.torchLevel > 0 }, set: {
                        model.setLight($0 ? model.lightStrength : 0)
                    })).disabled(!model.isReady || model.controlsLocked || (!model.torchAvailable && model.torchLevel == 0))
                    Picker("Light strength", selection: $model.lightStrength) {
                        Text("Low").tag(Float(0.25)); Text("Medium").tag(Float(0.5)); Text("High").tag(Float(1))
                    }
                    .disabled(!model.torchAvailable || model.controlsLocked)
                    .onChange(of: model.lightStrength) { value in
                        if model.torchLevel > 0 { model.setLight(value) }
                    }
                    Text(model.selectedCamera?.hasTorch == true
                         ? "Continuous light for preview and capture. Turns off after capture, when switching cameras, or when leaving the camera."
                         : "This camera has no flashlight.")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        HStack { Text("Brightness"); Spacer(); Text(String(format: "%+.1f", model.settings.exposureBias)).monospacedDigit() }
                        Slider(value: $model.settings.exposureBias, in: -2...2, step: 0.1, onEditingChanged: { editing in
                            if !editing { model.updateExposure() }
                        }).accessibilityLabel("Exposure compensation")
                    }
                }
                Section {
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        Picker("Processing", selection: $model.settings.mode) {
                            ForEach(StackMode.allCases.filter { model.selectedCamera?.supports($0) ?? ($0 == .single) }) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        if model.canStackFocus {
                            Toggle("Automatic focus range", isOn: $model.settings.automaticFocus)
                            if !model.settings.automaticFocus {
                                focusSlider("Near", value: $model.settings.near)
                                if model.settings.mode.sweepsFocus { focusSlider("Far", value: $model.settings.far) }
                            }
                        }
                        if model.settings.mode.sweepsFocus {
                            Picker("Spacing", selection: $model.settings.focusSpacing) {
                                ForEach(FocusSpacing.allCases) { Text($0.rawValue).tag($0) }
                            }
                        }
                        if model.settings.mode == .both || model.settings.mode == .clean {
                            Stepper("Repeats: \(model.settings.framesPerPosition)", value: $model.settings.framesPerPosition, in: 2...6)
                        }
                        Toggle("Keep original photos", isOn: Binding(get: { model.settings.keepOriginals || model.settings.mode == .burst }, set: {
                            model.settings.keepOriginals = $0
                        })).disabled(model.settings.mode == .burst)
                        Text("Keep originals to re-stack later in Projects. Both reduces noise before focus stacking; Noise averages at one focus position.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("advancedSettings")
                }
                Section("Quick guide") {
                    Label("Still: support the phone, tap the insect, then capture.", systemImage: "camera.macro")
                    Label("Moving: use bright light and choose the sharpest original.", systemImage: "hare")
                    Label("Photo: take one image with any available camera.", systemImage: "camera")
                    Text("0.5× is the macro lens on iPhone 13 Pro Max. Main and Tele need more distance. Focus range on the camera screen guides you through Near and Far. Projects holds saved captures and editing tools.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Capture settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settingsDone") } }
        }
    }

    private func focusSlider(_ title: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Slider(value: value, in: 0...1, onEditingChanged: { editing in
                if !editing { model.previewFocus(value.wrappedValue) }
            }).accessibilityLabel(title + " focus position")
        }
    }
}
