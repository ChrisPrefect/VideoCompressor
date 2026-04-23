import Foundation
import Observation
import SwiftUI

/// Container für app-weite Services und Stores. Wird einmalig erzeugt und
/// via `@Environment(AppEnvironment.self)` an Views vererbt.
@MainActor
@Observable
public final class AppEnvironment {

    public let library: PhotoLibraryService
    public let analyzer: VideoAnalysisService
    public let transcoding: TranscodingService
    public let authorization: PhotoLibraryAuthorization
    public let statistics: SessionStatisticsService
    public let presets: PresetStore
    public let settings: SettingsStore
    public let history: CompressionHistoryStore

    public static let shared: AppEnvironment = AppEnvironment()

    private init() {
        let library = PhotoLibraryService()
        let analyzer = VideoAnalysisService()
        self.library = library
        self.analyzer = analyzer
        self.transcoding = TranscodingService(library: library, analyzer: analyzer)
        self.authorization = PhotoLibraryAuthorization()
        self.statistics = SessionStatisticsService()
        self.presets = PresetStore()
        self.settings = SettingsStore()
        self.history = CompressionHistoryStore()
    }
}
