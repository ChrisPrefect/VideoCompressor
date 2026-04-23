import SwiftUI

public struct CompressionPresetEditorScreen: View {
    @State private var draft: CompressionPreset
    let onSave: (CompressionPreset) -> Void
    let onCancel: () -> Void

    public init(preset: CompressionPreset, onSave: @escaping (CompressionPreset) -> Void, onCancel: @escaping () -> Void) {
        self._draft = State(initialValue: preset)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
            } header: {
                Text("Allgemein")
            }
            Section("Auflösung & fps") {
                Stepper("Max. lange Kante: \(draft.maxLongEdge) px",
                        value: $draft.maxLongEdge,
                        in: 240...3840,
                        step: 80)
                Stepper("Max. fps: \(Int(draft.maxFrameRate))",
                        value: Binding(
                            get: { Int(draft.maxFrameRate) },
                            set: { draft.maxFrameRate = Double($0) }
                        ),
                        in: 15...60,
                        step: 5)
                Toggle("Höchstens halbe Originalauflösung erzwingen",
                       isOn: $draft.enforceHalfResolution)
            }
            Section("Bitrate") {
                let mb = draft.megabytesPerMinute
                VStack(alignment: .leading, spacing: 6) {
                    Text("Video-Bitrate: \(String(format: "%.1f", mb)) MB / Minute")
                    Slider(value: Binding(
                        get: { draft.megabytesPerMinute },
                        set: { draft.megabytesPerMinute = $0 }
                    ), in: 1...60, step: 0.5)
                    Text("Entspricht \(Formatting.bytes(Int64(Double(draft.maxVideoBitsPerSecond) / 8))) pro Sekunde Video.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Audio") {
                Toggle("Tonspur behalten", isOn: $draft.keepAudio)
                if draft.keepAudio {
                    Stepper("Audio-Bitrate: \(draft.audioBitsPerSecond / 1000) kbps",
                            value: Binding(
                                get: { draft.audioBitsPerSecond / 1000 },
                                set: { draft.audioBitsPerSecond = $0 * 1000 }
                            ),
                            in: 32...320,
                            step: 16)
                }
            }
            Section {
                Text("Komprimierung erhöht niemals Auflösung, fps oder Dateigrösse über das Original hinaus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Komprimierungs-Preset")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { onSave(draft) }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
