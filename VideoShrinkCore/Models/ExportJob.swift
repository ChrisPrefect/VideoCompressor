import Foundation

/// Beschreibt den Wunsch, ein Video gemäss Preset-Logik zu exportieren.
/// `preset` ist entweder ein Komprimierungs- oder Share-Preset, intern
/// vereinheitlicht zur konkreten `ExportPlan`-Konfiguration.
nonisolated public struct ExportJob: Identifiable, Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// Foto-Mediathek-Asset, identifiziert über den PHAsset.localIdentifier.
        case photoLibrary(localIdentifier: String)
        /// Bereits lokale Datei (z. B. aus Share-Extension Item-Provider).
        case fileURL(URL)
    }

    public enum PresetSelection: Sendable, Hashable {
        case compression(CompressionPreset)
        case share(SharePreset)
    }

    public enum PostExportAction: String, Sendable, Hashable, Codable {
        case keepOriginal
        case deleteOriginalAfterSuccess
    }

    public let id: UUID
    public let source: Source
    public let preset: PresetSelection
    public var postExportAction: PostExportAction

    public init(
        id: UUID = UUID(),
        source: Source,
        preset: PresetSelection,
        postExportAction: PostExportAction = .keepOriginal
    ) {
        self.id = id
        self.source = source
        self.preset = preset
        self.postExportAction = postExportAction
    }

    public var displayName: String {
        switch preset {
        case .compression(let p): return p.name
        case .share(let p): return p.name
        }
    }
}

/// Status eines laufenden Jobs für UI-Fortschrittsanzeigen.
nonisolated public enum ExportJobStatus: Sendable, Hashable {
    case pending
    case preparing
    case exporting(progress: Double)
    case writingToLibrary
    case finalizing
    case finished(ExportResult)
    case failed(String)
    case cancelled

    public var progressFraction: Double {
        switch self {
        case .pending: return 0
        case .preparing: return 0.05
        case .exporting(let p): return 0.1 + p * 0.8
        case .writingToLibrary: return 0.92
        case .finalizing: return 0.97
        case .finished: return 1
        case .failed, .cancelled: return 0
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .finished, .failed, .cancelled: return true
        default: return false
        }
    }

    public var localizedLabel: String {
        switch self {
        case .pending: return "Wartet"
        case .preparing: return "Vorbereitung"
        case .exporting: return "Komprimierung läuft"
        case .writingToLibrary: return "In Mediathek speichern"
        case .finalizing: return "Abschluss"
        case .finished: return "Fertig"
        case .failed(let msg): return "Fehler: \(msg)"
        case .cancelled: return "Abgebrochen"
        }
    }
}
