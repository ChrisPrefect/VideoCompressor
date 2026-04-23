import Foundation

/// Ergebnis eines abgeschlossenen Exports.
nonisolated public struct ExportResult: Sendable, Hashable {
    /// URL der erzeugten Datei. Wenn das Ergebnis bereits in die Mediathek
    /// gespeichert wurde, kann die temporäre Datei optional schon gelöscht
    /// sein — UI-Code sollte sich darauf nicht verlassen, sondern die
    /// `savedAssetIdentifier`-Information nutzen.
    public let outputURL: URL

    public let originalSizeBytes: Int64
    public let resultSizeBytes: Int64
    public let durationSeconds: TimeInterval

    /// PHAsset.localIdentifier des neu erzeugten Assets in der Mediathek,
    /// falls gespeichert.
    public let savedAssetIdentifier: String?

    /// Wenn das Original gelöscht wurde (nur Haupt-App-Pfad).
    public let originalWasDeleted: Bool

    /// Warnungen, die während Vorbereitung/Export aufgetreten sind und in
    /// der Resultat-Anzeige erwähnt werden sollten.
    public let warnings: WarningFlags

    public var savedBytes: Int64 {
        max(0, originalSizeBytes - resultSizeBytes)
    }

    public var savedFraction: Double {
        guard originalSizeBytes > 0 else { return 0 }
        return Double(savedBytes) / Double(originalSizeBytes)
    }
}
