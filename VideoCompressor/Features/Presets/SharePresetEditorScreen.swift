import SwiftUI

public struct SharePresetEditorScreen: View {
    @State private var draft: SharePreset
    @State private var sizeMB: Double
    let onSave: (SharePreset) -> Void
    let onCancel: () -> Void

    public init(preset: SharePreset, onSave: @escaping (SharePreset) -> Void, onCancel: @escaping () -> Void) {
        let draft = preset
        self._draft = State(initialValue: draft)
        self._sizeMB = State(initialValue: Double(draft.maxFileSizeBytes) / (1024.0 * 1024.0))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                Picker("Codec", selection: $draft.codec) {
                    ForEach(VideoCodecPreference.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                Text("Teilen-Presets priorisieren die Zielgrösse. HEVC spart zusätzlich Platz, H.264 bleibt die sichere Wahl für alte Empfänger oder heikle Uploads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Allgemein")
            }
            Section("Zielgrösse") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Maximale Dateigrösse: \(Int(sizeMB)) MB")
                    Slider(value: $sizeMB, in: 1...200, step: 1)
                        .onChange(of: sizeMB) { _, new in
                            draft.maxFileSizeBytes = Int64(new * 1024.0 * 1024.0)
                        }
                    Text("Bitrate wird automatisch aus Zielgrösse, Dauer und Audio-Anteil berechnet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            }
            Section("Audio") {
                Toggle("Tonspur behalten", isOn: $draft.keepAudio)
                if draft.keepAudio {
                    Stepper("Audio-Bitrate: \(draft.audioBitsPerSecond / 1000) kbps",
                            value: Binding(
                                get: { draft.audioBitsPerSecond / 1000 },
                                set: { draft.audioBitsPerSecond = $0 * 1000 }
                            ),
                            in: 16...192,
                            step: 16)
                }
            }
            Section {
                Text("Wenn die Zielgrösse für das gewählte Video nicht erreichbar ist, zeigt VideoCompressor einen Hinweis und bietet den bestmöglichen Export an.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Teilen-Preset")
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
