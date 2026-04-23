import AVKit
import SwiftUI

public struct VideoDetailScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: VideoDetailViewModel
    @State private var presetTab: PresetTab = .compression
    let onFinished: () -> Void

    enum PresetTab: String, CaseIterable, Identifiable {
        case compression, share
        var id: String { rawValue }
        var title: String { self == .compression ? "Komprimieren" : "Teilen" }
    }

    public init(item: LibraryVideoItem, onFinished: @escaping () -> Void) {
        _viewModel = State(initialValue: VideoDetailViewModel(
            item: item,
            environment: AppEnvironment.shared
        ))
        self.onFinished = onFinished
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mediaHeader
                metadataSection
                previewSection
                if viewModel.item.kind != .standard,
                   let warning = viewModel.item.kind.conversionWarning {
                    warningBox(warning)
                }
                if !viewModel.analysisWarnings.localizedDescriptions.isEmpty {
                    preflightWarningsBox
                }
                presetSection
                ExportControls(viewModel: viewModel)
                statusView
                postExportActions
            }
            .padding()
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.syncPresetChoice()
            await viewModel.loadThumbnail()
            await viewModel.loadOriginalPlayback()
        }
        .task { await viewModel.runPreflight() }
        .onChange(of: environment.presets.allCompression) { _, _ in
            viewModel.syncPresetChoice()
        }
        .onChange(of: environment.presets.allShare) { _, _ in
            viewModel.syncPresetChoice()
        }
        .alert("Fehler", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            "Spezialformat: \(viewModel.item.kind.displayName)",
            isPresented: Binding(
                get: { viewModel.pending == .specialFormat },
                set: { if !$0 { viewModel.cancelPending() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Trotzdem komprimieren", role: .destructive) {
                viewModel.confirmSpecialFormat()
            }
            Button("Abbrechen", role: .cancel) { viewModel.cancelPending() }
        } message: {
            Text(viewModel.item.kind.conversionWarning ?? "Diese Aufnahme hat besondere Eigenschaften, die beim Re-Encode verloren gehen können.")
        }
        .confirmationDialog(
            "Original aus Mediathek löschen?",
            isPresented: Binding(
                get: { viewModel.pending == .willDeleteOriginal },
                set: { if !$0 { viewModel.cancelPending() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Komprimieren & Original löschen", role: .destructive) {
                viewModel.confirmDeleteAndStart()
            }
            Button("Komprimieren ohne Löschen") {
                viewModel.deleteOriginalAfterSuccess = false
                viewModel.confirmDeleteAndStart()
            }
            Button("Abbrechen", role: .cancel) { viewModel.cancelPending() }
        } message: {
            Text("Nach erfolgreichem Speichern wird das Original in „Zuletzt gelöscht“ verschoben. iOS gibt den Speicherplatz erst nach Ablauf des Album-Zeitraums (max. 30 Tage) oder manueller Leerung frei.")
        }
        .confirmationDialog(
            "Original jetzt löschen?",
            isPresented: Binding(
                get: { if case .askPostExportDelete = viewModel.pending { return true } else { return false } },
                set: { if !$0 { viewModel.declinePostExportDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Original löschen", role: .destructive) {
                Task { await viewModel.confirmPostExportDelete() }
            }
            Button("Behalten", role: .cancel) { viewModel.declinePostExportDelete() }
        } message: {
            Text("Die komprimierte Version wurde gespeichert. Soll das Original aus der Mediathek entfernt werden? (Es wird in „Zuletzt gelöscht“ verschoben.)")
        }
        .onChange(of: viewModel.lastResult) { _, new in
            if new != nil { onFinished() }
        }
        .onDisappear {
            viewModel.player.pause()
        }
    }

    private var mediaHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                if viewModel.playerIsReady {
                    VideoPlayer(player: viewModel.player)
                        .aspectRatio(viewModel.item.aspectRatio, contentMode: .fit)
                } else if let thumb = viewModel.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(viewModel.item.aspectRatio, contentMode: .fit)
                        .overlay(ProgressView())
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if viewModel.comparisonAvailable {
                playbackSwitch
            } else if viewModel.compressedIsAvailable {
                HStack {
                    Label("Komprimierte Version zum Abspielen bereit", systemImage: "play.rectangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatting.bytes(viewModel.lastResult?.resultSizeBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var playbackSwitch: some View {
        HStack(spacing: 10) {
            playbackButton(for: .original, size: viewModel.item.fileSize, available: viewModel.originalIsAvailable)
            playbackButton(for: .compressed, size: viewModel.lastResult?.resultSizeBytes, available: viewModel.compressedIsAvailable)
        }
    }

    private func playbackButton(
        for source: VideoDetailViewModel.PlaybackSource,
        size: Int64?,
        available: Bool
    ) -> some View {
        Button {
            Task { await viewModel.selectPlaybackSource(source) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.subheadline.weight(.semibold))
                Text(Formatting.bytes(size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                viewModel.currentPlaybackSource == source
                    ? Color.accentColor.opacity(0.10)
                    : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Formatting.bytes(viewModel.item.fileSize))
                    .font(.title2.bold())
                if viewModel.item.kind != .standard {
                    VideoKindBadge(kind: viewModel.item.kind)
                }
                if viewModel.preflightAnalysis?.isHDR == true {
                    HDRBadge()
                }
                Spacer()
                Text(Formatting.duration(viewModel.item.duration))
                    .foregroundStyle(.secondary)
            }
            Text("\(viewModel.item.resolutionString) · \(Formatting.date(viewModel.item.creationDate))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview = viewModel.currentPreview {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Vorschau mit \(viewModel.presetChoice.displayName)")
                        .font(.headline)
                    Spacer()
                }
                HStack {
                    previewStat(title: "Vorher", value: Formatting.bytes(preview.originalSizeBytes))
                    Divider().frame(height: 32)
                    previewStat(title: "Geschätzt", value: Formatting.bytes(preview.resultSizeBytes))
                    Divider().frame(height: 32)
                    previewStat(
                        title: "Ersparnis",
                        value: "\(Formatting.bytes(preview.savedBytes))\n\(Formatting.percentage(preview.savedFraction))",
                        tint: .green
                    )
                }
                Text("\(Int(preview.renderSize.width)) × \(Int(preview.renderSize.height)) · \(Int(preview.frameRate.rounded())) fps\(preview.keepAudio ? " · mit Ton" : " · ohne Ton")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if preview.skipExportBecauseOriginalSmaller {
                    Text("Dieses Preset bringt bei diesem Video voraussichtlich keine echte Verkleinerung.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        } else if !viewModel.hasAnyPreset {
            VStack(alignment: .leading, spacing: 6) {
                Text("Keine Presets vorhanden")
                    .font(.headline)
                Text("Unter Einstellungen kannst du neue Komprimieren- oder Teilen-Presets anlegen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func warningBox(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Spezialformat: \(viewModel.item.kind.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                Text(viewModel.willAskBeforeSpecialFormatExport
                     ? "VideoCompressor fragt vor dem Export nochmal nach."
                     : "Die Warnbestätigung wird dieses Mal nicht angezeigt.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var preflightWarningsBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Hinweis vor dem Export", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(viewModel.analysisWarnings.localizedDescriptions, id: \.self) { msg in
                Text("• \(msg)").font(.footnote)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preset").font(.headline)
                Spacer()
                Picker("", selection: $presetTab) {
                    ForEach(PresetTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            if !viewModel.hasAnyPreset {
                Text("Keine Presets vorhanden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                switch presetTab {
                case .compression:
                    Text("Komprimieren reduziert für maximale echte Einsparung in deiner Mediathek.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(environment.presets.allCompression) { preset in
                        presetRow(
                            title: preset.name,
                            detail: compressionDetail(preset),
                            isSelected: viewModel.presetChoice == .compression(preset),
                            action: { viewModel.presetChoice = .compression(preset) }
                        )
                    }
                case .share:
                    Text("Teilen zielt auf eine feste Dateigrösse für Versand, Upload oder Mail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(environment.presets.allShare) { preset in
                        presetRow(
                            title: preset.name,
                            detail: shareDetail(preset),
                            isSelected: viewModel.presetChoice == .share(preset),
                            action: { viewModel.presetChoice = .share(preset) }
                        )
                    }
                }
            }
        }
    }

    private func compressionDetail(_ preset: CompressionPreset) -> String {
        if let preview = viewModel.preview(for: .compression(preset)) {
            return "Spart ca. \(Formatting.bytes(preview.savedBytes)) · geschätzt \(Formatting.bytes(preview.resultSizeBytes))"
        }
        let mb = (Double(preset.maxVideoBitsPerSecond) * 60.0 / 8.0) / 1_000_000.0
        return "≤ \(preset.maxLongEdge)px · ≤ \(Int(preset.maxFrameRate)) fps · ≤ \(String(format: "%.1f", mb)) MB/min"
    }

    private func shareDetail(_ preset: SharePreset) -> String {
        if let preview = viewModel.preview(for: .share(preset)) {
            return "Ca. \(Formatting.bytes(preview.resultSizeBytes)) · Ziel ≤ \(Formatting.bytes(preset.maxFileSizeBytes))"
        }
        return "Ziel: \(Formatting.bytes(preset.maxFileSizeBytes))"
    }

    private func presetRow(title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.status {
        case .pending:
            EmptyView()
        case .preparing, .exporting, .writingToLibrary, .finalizing:
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.status.localizedLabel)
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: viewModel.status.progressFraction)
                    .progressViewStyle(.linear)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        case .finished(let r):
            ResultCard(result: r)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 4) {
                Label("Export fehlgeschlagen", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline.weight(.semibold))
                Text(msg).font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        case .cancelled:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Abgebrochen").font(.subheadline.weight(.semibold))
                    Text("Die Teildatei wurde sauber entfernt. Das Original wurde nicht angetastet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var postExportActions: some View {
        if viewModel.lastResult != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Versionen verwalten")
                    .font(.headline)
                Text("Zum Vergleichen oben zwischen Original und komprimierter Version wechseln. Die Wiedergabeposition bleibt erhalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.originalIsAvailable {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteOriginal()
                            onFinished()
                        }
                    } label: {
                        HStack {
                            Label("Original löschen", systemImage: "trash")
                            Spacer()
                            Text(Formatting.bytes(viewModel.item.fileSize))
                        }
                    }
                }

                if viewModel.compressedIsAvailable,
                   let result = viewModel.lastResult {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteCompressed()
                            onFinished()
                        }
                    } label: {
                        HStack {
                            Label("Komprimierte Version löschen", systemImage: "trash.fill")
                            Spacer()
                            Text(Formatting.bytes(result.resultSizeBytes))
                        }
                    }
                } else if viewModel.compressedWasDeleted {
                    Text("Die komprimierte Version wurde bereits gelöscht.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func previewStat(title: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct ExportControls: View {
    @Bindable var viewModel: VideoDetailViewModel

    var body: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $viewModel.deleteOriginalAfterSuccess) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Original aus Mediathek löschen")
                        .font(.subheadline.weight(.semibold))
                    Text("Verschiebt das Original nach erfolgreichem Speichern in „Zuletzt gelöscht“. VideoCompressor fragt vor dem Start nochmal nach.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            .disabled(!viewModel.hasAnyPreset)

            switch viewModel.status {
            case .pending, .failed, .cancelled, .finished:
                Button {
                    viewModel.requestStart()
                } label: {
                    Label(startButtonTitle, systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.white)
                }
                .disabled(!viewModel.hasAnyPreset)
            case .preparing, .exporting, .writingToLibrary, .finalizing:
                Button(role: .destructive) {
                    viewModel.cancel()
                } label: {
                    Label("Abbrechen", systemImage: "xmark.circle.fill")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.red)
                }
            }
        }
    }

    private var startButtonTitle: String {
        if case .finished = viewModel.status {
            return "Erneut komprimieren"
        }
        return "Komprimieren starten"
    }
}

struct ResultCard: View {
    let result: ExportResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Fertig").font(.headline)
                Spacer()
            }
            HStack {
                statBlock(title: "Vorher", value: Formatting.bytes(result.originalSizeBytes))
                Divider().frame(height: 32)
                statBlock(title: "Nachher", value: Formatting.bytes(result.resultSizeBytes))
                Divider().frame(height: 32)
                statBlock(
                    title: "Gespart",
                    value: "\(Formatting.bytes(result.savedBytes))\n\(Formatting.percentage(result.savedFraction))",
                    tint: .green
                )
            }
            if !result.warnings.isEmpty {
                ForEach(result.warnings.localizedDescriptions, id: \.self) { msg in
                    Label(msg, systemImage: "exclamationmark.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if result.originalWasDeleted {
                Text("Original wurde aus der Mediathek entfernt (jetzt in „Zuletzt gelöscht“).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statBlock(title: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
