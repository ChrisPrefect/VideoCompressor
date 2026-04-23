import SwiftUI

public struct PresetsScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var editingCompression: CompressionPreset?
    @State private var editingShare: SharePreset?

    public init() {}

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Komprimieren")
                        .font(.subheadline.weight(.semibold))
                    Text("Für Speicher sparen in deiner Mediathek. Diese Presets zielen auf die effektiv kleinste Datei bei brauchbarer Qualität.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                ForEach(environment.presets.allCompression) { preset in
                    Button {
                        editingCompression = preset
                    } label: {
                        PresetCell(name: preset.name, detail: compressionDetail(preset))
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    environment.presets.deleteCompression(at: offsets)
                }
                Button {
                    editingCompression = newCompression()
                } label: {
                    Label("Neues Komprimierungs-Preset", systemImage: "plus.circle.fill")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Teilen")
                        .font(.subheadline.weight(.semibold))
                    Text("Für feste Zielgrössen bei Upload, Chat oder Mail. Diese Presets rechnen auf ein Grössenlimit hin, nicht auf maximale Ersparnis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                ForEach(environment.presets.allShare) { preset in
                    Button {
                        editingShare = preset
                    } label: {
                        PresetCell(name: preset.name, detail: shareDetail(preset))
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    environment.presets.deleteShare(at: offsets)
                }
                Button {
                    editingShare = newShare()
                } label: {
                    Label("Neues Teilen-Preset", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Presets")
        .sheet(item: $editingCompression) { preset in
            NavigationStack {
                CompressionPresetEditorScreen(preset: preset) { updated in
                    environment.presets.upsert(updated)
                    editingCompression = nil
                } onCancel: {
                    editingCompression = nil
                }
            }
        }
        .sheet(item: $editingShare) { preset in
            NavigationStack {
                SharePresetEditorScreen(preset: preset) { updated in
                    environment.presets.upsert(updated)
                    editingShare = nil
                } onCancel: {
                    editingShare = nil
                }
            }
        }
    }

    private func compressionDetail(_ p: CompressionPreset) -> String {
        let mb = (Double(p.maxVideoBitsPerSecond) * 60.0 / 8.0) / 1_000_000.0
        let mbStr = String(format: "%.1f", mb)
        return "≤ \(p.maxLongEdge)px · ≤ \(Int(p.maxFrameRate)) fps · ≤ \(mbStr) MB/min"
    }

    private func shareDetail(_ p: SharePreset) -> String {
        "Ziel ≤ \(Formatting.bytes(p.maxFileSizeBytes))\(p.keepAudio ? "" : " · ohne Ton")"
    }

    private func newCompression() -> CompressionPreset {
        CompressionPreset(
            name: "Eigenes Preset",
            kind: .custom,
            maxLongEdge: 1280,
            maxFrameRate: 30,
            maxVideoBitsPerSecond: 4_000_000,
            keepAudio: true,
            audioBitsPerSecond: 96_000,
            enforceHalfResolution: false
        )
    }

    private func newShare() -> SharePreset {
        SharePreset(
            name: "Eigenes Teilen-Preset",
            kind: .custom,
            maxFileSizeBytes: 15 * 1024 * 1024,
            maxLongEdge: 1280,
            maxFrameRate: 30,
            keepAudio: true,
            audioBitsPerSecond: 64_000
        )
    }
}

private struct PresetCell: View {
    let name: String
    let detail: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}
