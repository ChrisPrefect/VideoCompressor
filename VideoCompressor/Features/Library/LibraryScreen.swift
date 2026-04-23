import SwiftUI
import UIKit

public struct LibraryScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: LibraryViewModel
    @State private var presetSelection: CompressionPreset?
    @State private var navigateToBatch: Bool = false
    @State private var navigateToDetail: LibraryVideoItem?

    public init(viewModel: LibraryViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("VideoCompressor")
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom) {
                    if !viewModel.selectedIDs.isEmpty {
                        SelectionFooter(
                            viewModel: viewModel,
                            presetSelection: $presetSelection,
                            navigateToBatch: $navigateToBatch
                        )
                    }
                }
                .navigationDestination(isPresented: $navigateToBatch) {
                    if !viewModel.selectedItems.isEmpty,
                       let presetSelection {
                        BatchScreen(
                            items: viewModel.selectedItems,
                            initialPreset: presetSelection,
                            onFinish: {
                                viewModel.clearSelection()
                                Task { await viewModel.refresh() }
                            }
                        )
                    }
                }
                .navigationDestination(item: $navigateToDetail) { item in
                    VideoDetailScreen(item: item, onFinished: {
                        Task { await viewModel.refresh() }
                    })
                }
                .task {
                    syncPresetSelection()
                    await viewModel.onAppear()
                    syncPresetSelection()
                }
                .refreshable { await viewModel.refresh() }
                .onChange(of: environment.settings.settings.libraryMinimumSizeBytes) { _, new in
                    viewModel.minimumSizeBytes = new
                    Task { await viewModel.refresh() }
                }
                .onChange(of: environment.presets.allCompression) { _, _ in
                    syncPresetSelection()
                }
                .alert("Hinweis", isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )) {
                    Button("OK") { viewModel.errorMessage = nil }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !environment.authorization.state.hasReadAccess {
            permissionView
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if viewModel.statistics.statistics.convertedCount > 0 ||
                        viewModel.statistics.lifetimeStatistics.convertedCount > 0 {
                        SessionStatisticsHeader(
                            session: viewModel.statistics.statistics,
                            lifetime: viewModel.statistics.lifetimeStatistics
                        )
                        .padding(.horizontal)
                    }

                    if environment.authorization.state == .limited {
                        LimitedAccessHint()
                            .padding(.horizontal)
                    }

                    SortControls(viewModel: viewModel)
                        .padding(.horizontal)

                    if viewModel.isLoading && viewModel.items.isEmpty {
                        ProgressView("Mediathek wird gelesen …")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if viewModel.items.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.items) { item in
                                VideoRowView(
                                    item: item,
                                    isSelected: viewModel.selectedIDs.contains(item.id),
                                    onTap: { navigateToDetail = item },
                                    onToggleSelection: { viewModel.toggleSelection(item.id) },
                                    thumbnailLoader: { id in
                                        await environment.library.thumbnail(for: id)
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Keine Videos ab \(Formatting.bytes(viewModel.minimumSizeBytes)) gefunden.")
                .font(.headline)
            Text("Senke das Mindestgrösse-Filter in den Einstellungen, um mehr Videos zu sehen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(environment.authorization.state.displayMessage)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Zugriff erlauben") {
                Task {
                    await environment.authorization.requestAccess()
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
            if environment.authorization.state == .denied {
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(destination: SettingsScreen()) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Einstellungen")
        }
    }

    private func syncPresetSelection() {
        let available = environment.presets.allCompression
        guard let current = presetSelection else {
            presetSelection = available.first
            return
        }
        if !available.contains(current) {
            presetSelection = available.first
        }
    }
}

private struct SortControls: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        HStack(spacing: 12) {
            Picker("Sortierung", selection: $viewModel.sortField) {
                ForEach(LibraryViewModel.SortField.allCases) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.sortField) { _, _ in
                Task { await viewModel.refresh() }
            }

            Button {
                viewModel.ascending.toggle()
                Task { await viewModel.refresh() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.ascending ? "arrow.up" : "arrow.down")
                    Text(viewModel.ascending ? "Aufst." : "Abst.")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel(viewModel.ascending ? "Sortierung aufsteigend, tippen zum Umkehren" : "Sortierung absteigend, tippen zum Umkehren")
        }
    }
}

private struct SelectionFooter: View {
    @Bindable var viewModel: LibraryViewModel
    @Binding var presetSelection: CompressionPreset?
    @Binding var navigateToBatch: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let presetSelection {
                HStack {
                    Text("\(viewModel.selectedIDs.count) ausgewählt")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("≈ \(Formatting.bytes(viewModel.estimatedSavings(for: presetSelection))) Ersparnis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Menu {
                        ForEach(viewModel.presets.allCompression) { p in
                            Button {
                                self.presetSelection = p
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(p.name)
                                    Text("Spart ca. \(Formatting.bytes(viewModel.estimatedSavings(for: p))) · ≤ \(p.maxLongEdge)px · \(p.codec.displayName)")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            VStack(alignment: .leading, spacing: 0) {
                                Text(presetSelection.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("Spart ca. \(Formatting.bytes(viewModel.estimatedSavings(for: presetSelection)))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                    }
                    Spacer()
                    Button {
                        navigateToBatch = true
                    } label: {
                        Label("Komprimieren", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kein Komprimierungs-Preset vorhanden")
                            .font(.subheadline.weight(.semibold))
                        Text("Lege unter Einstellungen zuerst ein Preset an.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink(destination: SettingsScreen()) {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}

private struct SessionStatisticsHeader: View {
    let session: SessionStatistics
    let lifetime: SessionStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.convertedCount > 0 {
                statisticsRow(
                    title: "Diese Sitzung",
                    bytes: session.savedBytes,
                    count: session.convertedCount
                )
            }
            if lifetime.convertedCount > 0 {
                statisticsRow(
                    title: "Insgesamt",
                    bytes: lifetime.savedBytes,
                    count: lifetime.convertedCount
                )
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statisticsRow(title: String, bytes: Int64, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(Formatting.bytes(bytes))
                    .font(.title2.bold())
                Spacer()
                Text("\(count) Dateien")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LimitedAccessHint: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Eingeschränkter Mediathek-Zugriff")
                    .font(.subheadline.weight(.semibold))
                Text("Du siehst nur Videos, die du explizit freigegeben hast.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Weitere Videos auswählen") {
                        presentLimitedPicker()
                    }
                    .font(.caption.weight(.semibold))
                    Button("Einstellungen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController?.topPresentedViewController else {
            return
        }
        environment.authorization.presentLimitedLibraryPicker(from: root)
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: { $0.isKeyWindow }) ?? windows.first
    }
}

private extension UIViewController {
    var topPresentedViewController: UIViewController {
        var controller: UIViewController = self
        while let next = controller.presentedViewController { controller = next }
        return controller
    }
}
