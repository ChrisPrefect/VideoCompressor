import SwiftUI

public struct ShareExtensionMainView: View {
    @State var viewModel: ShareExtensionViewModel
    @State private var showsDiscardConfirm = false

    public init(viewModel: ShareExtensionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("VideoCompressor")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") {
                            if case .done = viewModel.stage {
                                showsDiscardConfirm = true
                            } else {
                                viewModel.cancel()
                            }
                        }
                    }
                }
                .task { await viewModel.load() }
                .confirmationDialog(
                    "Komprimierte Version verwerfen?",
                    isPresented: $showsDiscardConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Verwerfen", role: .destructive) { viewModel.cancel() }
                    Button("Doch teilen / sichern") {
                        if case .done(let result, _) = viewModel.stage {
                            viewModel.finishAndShare(result: result)
                        }
                    }
                    Button("Zurück", role: .cancel) {}
                } message: {
                    Text("Die komprimierte Datei wurde noch nicht weitergegeben. Beim Schliessen geht sie verloren.")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.stage {
        case .loadingInput:
            ProgressView("Video wird geladen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            readyView
        case .exporting(let p):
            exportingView(progress: p)
        case .done(let result, _):
            doneView(result: result)
        case .failed(let msg):
            failedView(msg)
        }
    }

    private var readyView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let thumb = viewModel.inputThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    Text(Formatting.bytes(viewModel.inputSizeBytes))
                        .font(.headline)
                    Spacer()
                    Text(Formatting.duration(viewModel.inputDuration))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                presetPicker
                optionsBox

                Button {
                    Task { await viewModel.startExport() }
                } label: {
                    Label("Komprimieren", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.white)
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private var presetPicker: some View {
        @Bindable var bindable = viewModel
        VStack(alignment: .leading, spacing: 6) {
            Text("Zielgrösse")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal)
            Picker("Preset", selection: $bindable.selectedPreset) {
                ForEach(viewModel.availablePresets) { preset in
                    Text("\(preset.name) — \(Formatting.bytes(preset.maxFileSizeBytes))")
                        .tag(preset)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var optionsBox: some View {
        @Bindable var bindable = viewModel
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Tonspur behalten", isOn: $bindable.keepAudio)
            VStack(alignment: .leading, spacing: 4) {
                Picker("Codec", selection: $bindable.codec) {
                    ForEach(VideoCodecPreference.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.segmented)
                Text(codecHelp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var codecHelp: String {
        switch viewModel.codec {
        case .h264: return "H.264 — maximale Kompatibilität, etwas grösser. Empfohlen für direktes Versenden."
        case .hevc: return "HEVC — kleinere Datei, aber nicht überall abspielbar."
        case .auto: return "Automatisch — HEVC wenn das Gerät es kann, sonst H.264."
        }
    }

    private func exportingView(progress: Double) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .padding(.horizontal)
            Text("\(Int(progress * 100)) % …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneView(result: ExportResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Fertig")
                .font(.title2.bold())
            VStack(spacing: 4) {
                Text("\(Formatting.bytes(result.originalSizeBytes)) → \(Formatting.bytes(result.resultSizeBytes))")
                Text("Gespart: \(Formatting.bytes(result.savedBytes)) (\(Formatting.percentage(result.savedFraction)))")
                    .foregroundStyle(.green)
            }
            .font(.subheadline)

            Text("Die komprimierte Version liegt jetzt bereit. Wähle, wie sie weitergehen soll:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 10) {
                Button {
                    viewModel.finishAndShare(result: result)
                } label: {
                    Label("Teilen oder sichern …", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                Button {
                    showsDiscardConfirm = true
                } label: {
                    Label("Verwerfen", systemImage: "trash")
                        .font(.subheadline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Fehler")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Schliessen") { viewModel.completeWithoutSharing() }
                .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
