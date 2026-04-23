import Foundation
import Photos

/// Repräsentiert ein Video aus der Foto-Mediathek mit den Metadaten, die wir
/// in der Library-Liste anzeigen. Die exakte Dateigrösse wird einmalig pro
/// Asset asynchron ermittelt; hier liegt das Ergebnis als Wert vor.
nonisolated public struct LibraryVideoItem: Identifiable, Hashable, Sendable {
    /// PHAsset.localIdentifier
    public let id: String

    /// Ursprünglich erfasstes PHAsset. Wir halten eine Referenz, weil wir
    /// für Thumbnails und Export erneut darauf zugreifen.
    public let assetIdentifier: String

    public let pixelWidth: Int
    public let pixelHeight: Int
    public let duration: TimeInterval
    public let creationDate: Date?
    public let modificationDate: Date?
    public let kind: VideoKind

    /// Dateigrösse in Bytes. `nil` bedeutet, dass die Grösse noch nicht
    /// ermittelt werden konnte (selten, z. B. iCloud-only Assets ohne
    /// resource).
    public let fileSize: Int64?

    /// Hinweis, ob das Asset vollständig auf dem Gerät vorliegt. iCloud-Only
    /// Assets erfordern vor dem Export einen Download.
    public let isLocallyAvailable: Bool

    public var resolutionString: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    public var aspectRatio: CGFloat {
        guard pixelHeight > 0 else { return 16.0 / 9.0 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }
}
