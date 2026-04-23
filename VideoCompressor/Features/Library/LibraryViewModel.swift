import Foundation
import Observation
import SwiftUI
import Photos

@MainActor
@Observable
public final class LibraryViewModel {

    public enum SortField: String, CaseIterable, Identifiable, Hashable {
        case size, date
        public var id: String { rawValue }
        public var displayName: String { self == .size ? "Grösse" : "Datum" }
    }

    // UI-Zustand
    public private(set) var items: [LibraryVideoItem] = []
    public private(set) var isLoading: Bool = false
    public var sortField: SortField = .size
    public var ascending: Bool = false
    public var minimumSizeBytes: Int64
    public var selectedIDs: Set<String> = []
    public var errorMessage: String?

    @ObservationIgnored private let library: PhotoLibraryService
    @ObservationIgnored private let authorization: PhotoLibraryAuthorization
    @ObservationIgnored private let planner = ExportPlanner()
    @ObservationIgnored public let statistics: SessionStatisticsService
    @ObservationIgnored public let settings: SettingsStore
    @ObservationIgnored public let presets: PresetStore

    public init(
        library: PhotoLibraryService,
        authorization: PhotoLibraryAuthorization,
        statistics: SessionStatisticsService,
        settings: SettingsStore,
        presets: PresetStore
    ) {
        self.library = library
        self.authorization = authorization
        self.statistics = statistics
        self.settings = settings
        self.presets = presets
        self.minimumSizeBytes = settings.settings.libraryMinimumSizeBytes
    }

    public func onAppear() async {
        if !authorization.state.hasReadAccess {
            await authorization.requestAccess()
        }
        await refresh()
    }

    public func refresh() async {
        guard authorization.state.hasReadAccess else { return }
        isLoading = true
        defer { isLoading = false }
        let opts = PhotoLibraryService.FetchOptions(
            minimumSizeBytes: minimumSizeBytes,
            sort: sortField == .size ? .fileSize : .creationDate,
            ascending: ascending
        )
        let result = await library.fetchVideos(options: opts)
        items = result
    }

    public func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    public func clearSelection() {
        selectedIDs.removeAll()
    }

    public var selectedItems: [LibraryVideoItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    public var selectedTotalBytes: Int64 {
        selectedItems.reduce(0) { $0 + ($1.fileSize ?? 0) }
    }

    public func estimatedSavings(for preset: CompressionPreset) -> Int64 {
        selectedItems.reduce(0) { partial, item in
            partial + planner.approximateSavedBytes(for: item, preset: preset)
        }
    }

    public var hasCompressionPresets: Bool {
        !presets.allCompression.isEmpty
    }

    public func applyMinimumSizeFromSettings() {
        if minimumSizeBytes != settings.settings.libraryMinimumSizeBytes {
            minimumSizeBytes = settings.settings.libraryMinimumSizeBytes
        }
    }
}
