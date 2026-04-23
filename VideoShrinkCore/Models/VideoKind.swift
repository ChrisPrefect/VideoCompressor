import Foundation
import Photos

/// Klassifiziert ein Video nach Spezialform, damit die UI klare Hinweise geben
/// kann und die Export-Engine Sonderfälle korrekt behandelt.
nonisolated public enum VideoKind: String, Codable, Sendable, CaseIterable, Hashable {
    case standard
    case slowMotion
    case timeLapse
    case cinematic
    case spatial
    case screenRecording

    public var displayName: String {
        switch self {
        case .standard: return "Video"
        case .slowMotion: return "Slow-Motion"
        case .timeLapse: return "Time-Lapse"
        case .cinematic: return "Cinematic"
        case .spatial: return "Spatial Video"
        case .screenRecording: return "Bildschirmaufnahme"
        }
    }

    public var systemImage: String {
        switch self {
        case .standard: return "video"
        case .slowMotion: return "slowmo"
        case .timeLapse: return "timelapse"
        case .cinematic: return "camera.aperture"
        case .spatial: return "cube.transparent"
        case .screenRecording: return "rectangle.dashed"
        }
    }

    /// Menschenlesbarer Hinweis für Spezialformate vor dem Export.
    /// Liefert `nil` für Standard-Videos ohne Sonderbehandlung.
    public var conversionWarning: String? {
        switch self {
        case .standard, .screenRecording:
            return nil
        case .slowMotion:
            return "Beim Re-Encode kann der Slow-Motion-Effekt verloren gehen oder als feste Wiedergabegeschwindigkeit eingebrannt werden."
        case .timeLapse:
            return "Time-Lapse-Aufnahmen sind bereits stark verarbeitet. Erneute Komprimierung kann sichtbare Artefakte erzeugen."
        case .cinematic:
            return "Tiefen- und Fokusdaten von Cinematic-Aufnahmen lassen sich mit Standard-Export nicht erhalten und gehen verloren."
        case .spatial:
            return "Spatial Videos werden beim Standard-Export voraussichtlich auf eine konventionelle 2D-Spur reduziert. Räumliche Tiefe geht verloren."
        }
    }

    /// Liefert `true`, wenn vor dem Export aktiv eine Bestätigung eingeholt
    /// werden sollte.
    public var requiresConfirmation: Bool {
        conversionWarning != nil
    }

    /// Heuristische Klassifikation aus PhotoKit-Subtypen.
    public static func classify(from asset: PHAsset) -> VideoKind {
        let subtypes = asset.mediaSubtypes
        if subtypes.contains(.videoTimelapse) { return .timeLapse }
        if subtypes.contains(.videoHighFrameRate) { return .slowMotion }
        if subtypes.contains(.videoCinematic) { return .cinematic }
        if Self.isSpatial(asset) { return .spatial }
        if Self.isScreenRecording(asset) { return .screenRecording }
        return .standard
    }

    /// `PHAssetMediaSubtype.spatialMedia` ist seit iOS 17.2 verfügbar; das
    /// Deployment-Target liegt darüber, daher direkter Zugriff. Wir lassen
    /// einen defensiven Raw-Bit-Fallback drin, falls in Zukunft jemand das
    /// Deployment-Target absenkt.
    private static func isSpatial(_ asset: PHAsset) -> Bool {
        if #available(iOS 17.2, *) {
            return asset.mediaSubtypes.contains(.spatialMedia)
        }
        let spatialBit: UInt = 1 << 21
        return asset.mediaSubtypes.rawValue & spatialBit != 0
    }

    /// PHAsset stellt keine offizielle Subtype-Markierung für Bildschirm-
    /// aufnahmen bereit. Heuristik: Original-Filename beginnt mit
    /// "RPReplay" (ReplayKit) oder enthält "ScreenRecording" / "Bildschirm-".
    /// Liefert false, wenn die Resource nicht ladbar ist.
    private static func isScreenRecording(_ asset: PHAsset) -> Bool {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .video }) ?? resources.first else {
            return false
        }
        let name = resource.originalFilename.lowercased()
        return name.hasPrefix("rpreplay")
            || name.contains("screenrecording")
            || name.contains("screen recording")
            || name.contains("bildschirmaufnahme")
    }
}
