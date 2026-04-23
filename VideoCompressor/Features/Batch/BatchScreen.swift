import SwiftUI

public struct BatchScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: BatchViewModel
    let onFinish: () -> Void

    public init(items: [LibraryVideoItem], initialPreset: CompressionPreset, onFinish: @escaping () -> Void) {
        _viewModel = State(initialValue: BatchViewModel(
            items: items,
            initialPreset: initialPreset,
            environment: AppEnvironment.shared
        ))
        self.onFinish = onFinish
    }

    public var body: some View {
        @Bindable var bindable = viewModel
        return ScrollView {
            VStack(spacing: 12) {
                summaryCard
                presetCard
                Toggle(isOn: $bindable.deleteOriginalAfterSuccess) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Originale nach Erfolg löschen")
                            .font(.subheadline.weight(.semibold))
                        Text("VideoCompressor fragt vor dem Start nochmal nach. Originale landen in „Zuletzt gelöscht“.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(viewModel.isRunning)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.states) { state in
                        BatchRow(state: state)
                    }
                }

                actionRow
            }
            .padding()
        }
        .navigationTitle("Batch")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Hinweis", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            "Spezialformate in der Auswahl",
            isPresented: Binding(
                get: { if case .specialFormat = viewModel.pending { return true } else { return false } },
                set: { if !$0 { viewModel.cancelPending() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Trotzdem komprimieren", role: .destructive) {
                viewModel.confirmSpecialFormat()
            }
            Button("Abbrechen", role: .cancel) { viewModel.cancelPending() }
        } message: {
            if case .specialFormat(let count) = viewModel.pending {
                Text("\(count) Asset(s) sind Spatial-, Cinematic- oder Slow-Motion-Aufnahmen. Beim Re-Encode können Tiefen-, Räumlichkeits- oder Wiedergabe-Metadaten verloren gehen.")
            } else {
                Text("")
            }
        }
        .confirmationDialog(
            "Originale aus Mediathek löschen?",
            isPresented: Binding(
                get: { if case .willDeleteOriginals = viewModel.pending { return true } else { return false } },
                set: { if !$0 { viewModel.cancelPending() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Komprimieren & alle Originale löschen", role: .destructive) {
                viewModel.confirmDeleteAndRun()
            }
            Button("Komprimieren ohne Löschen") {
                viewModel.deleteOriginalAfterSuccess = false
                viewModel.confirmDeleteAndRun()
            }
            Button("Abbrechen", role: .cancel) { viewModel.cancelPending() }
        } message: {
            if case .willDeleteOriginals(let count) = viewModel.pending {
                Text("Nach erfolgreicher Komprimierung werden \(count) Original(e) (zusammen \(Formatting.bytes(viewModel.totalOriginalBytes))) in „Zuletzt gelöscht“ verschoben. iOS gibt den Speicher erst nach Ablauf des Album-Zeitraums oder manueller Leerung frei.")
            } else { Text("") }
        }
        .confirmationDialog(
            "Originale jetzt löschen?",
            isPresented: Binding(
                get: { if case .askPostExportDelete = viewModel.pending { return true } else { return false } },
                set: { if !$0 { viewModel.declinePostExportDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Alle Originale löschen", role: .destructive) {
                Task { await viewModel.confirmPostExportDelete() }
            }
            Button("Behalten", role: .cancel) { viewModel.declinePostExportDelete() }
        } message: {
            if case .askPostExportDelete(let ids) = viewModel.pending {
                Text("Es wurden \(ids.count) komprimierte Versionen erstellt. Sollen die Originale aus der Mediathek entfernt werden? (Sie werden in „Zuletzt gelöscht“ verschoben.)")
            } else { Text("") }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(viewModel.states.count) Videos in Warteschlange")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.completedCount) erledigt · \(viewModel.failedCount) Fehler")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Original-Gesamtgrösse: \(Formatting.bytes(viewModel.totalOriginalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Eingespart: \(Formatting.bytes(viewModel.totalSavedBytes))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if viewModel.specialFormatCount > 0 {
                Label(specialFormatSummary, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var specialFormatSummary: String {
        if viewModel.willAskBeforeSpecialFormatExport {
            return "\(viewModel.specialFormatCount) Spezialformat(e) in der Auswahl — VideoCompressor fragt vor dem Start nach."
        }
        return "\(viewModel.specialFormatCount) Spezialformat(e) in der Auswahl — Warnbestätigung wird dieses Mal nicht angezeigt."
    }

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preset")
                .font(.subheadline.weight(.semibold))
            Text("Komprimieren maximiert die echte Speicherersparnis. Teilen zielt auf eine feste Dateigrösse.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                Section("Komprimieren") {
                    ForEach(environment.presets.allCompression) { p in
                        Button {
                            viewModel.presetChoice = .compression(p)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text("Spart ca. \(Formatting.bytes(viewModel.estimatedSavings(for: p)))")
                            }
                        }
                    }
                }
                Section("Teilen") {
                    ForEach(environment.presets.allShare) { p in
                        Button {
                            viewModel.presetChoice = .share(p)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text("Ziel: \(Formatting.bytes(p.maxFileSizeBytes))")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text(viewModel.presetChoice.displayName)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            .disabled(viewModel.isRunning)
        }
    }

    private var actionRow: some View {
        HStack {
            if viewModel.isRunning {
                Button(role: .destructive) {
                    viewModel.cancel()
                } label: {
                    Label("Abbrechen", systemImage: "xmark.circle.fill")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.red)
                }
            } else {
                if viewModel.completedCount + viewModel.failedCount == viewModel.states.count,
                   viewModel.states.count > 0 {
                    Button {
                        onFinish()
                    } label: {
                        Label("Fertig", systemImage: "checkmark.circle.fill")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                } else {
                    Button {
                        viewModel.requestStart()
                    } label: {
                        Label("Starten", systemImage: "play.fill")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

private struct BatchRow: View {
    let state: BatchViewModel.ItemState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Formatting.bytes(state.item.fileSize))
                        .font(.subheadline.weight(.semibold))
                    if state.item.kind != .standard {
                        VideoKindBadge(kind: state.item.kind)
                    }
                }
                Text("\(state.item.resolutionString) · \(Formatting.duration(state.item.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.status.localizedLabel)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            statusIndicator
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch state.status {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .preparing, .exporting, .writingToLibrary, .finalizing:
            ProgressView(value: state.status.progressFraction)
                .frame(width: 80)
        case .finished:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill").foregroundStyle(.gray)
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .finished: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        default: return .secondary
        }
    }
}
