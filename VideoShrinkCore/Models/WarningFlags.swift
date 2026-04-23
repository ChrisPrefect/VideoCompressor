import Foundation

/// Bündelt Warnungen, die sich aus der Analyse eines Videos und dem gewählten
/// Preset ergeben. Wird von ViewModels in der UI ausgewertet.
nonisolated public struct WarningFlags: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let losesSpatialData       = WarningFlags(rawValue: 1 << 0)
    public static let losesDepthData         = WarningFlags(rawValue: 1 << 1)
    public static let losesSlowMotionRamp    = WarningFlags(rawValue: 1 << 2)
    public static let mayProduceArtifacts    = WarningFlags(rawValue: 1 << 3)
    public static let originalSmallerThanTarget = WarningFlags(rawValue: 1 << 4)
    public static let presetUpscalesResolution  = WarningFlags(rawValue: 1 << 5)
    public static let targetSizeNotReachable    = WarningFlags(rawValue: 1 << 6)
    public static let audioWillBeRemoved        = WarningFlags(rawValue: 1 << 7)
    public static let codecNotSupportedFallback = WarningFlags(rawValue: 1 << 8)
    public static let hdrConvertedToSDR         = WarningFlags(rawValue: 1 << 9)

    public var localizedDescriptions: [String] {
        var out: [String] = []
        if contains(.losesSpatialData) {
            out.append("Räumliche Bilddaten gehen verloren.")
        }
        if contains(.losesDepthData) {
            out.append("Tiefen- und Cinematic-Metadaten gehen verloren.")
        }
        if contains(.losesSlowMotionRamp) {
            out.append("Slow-Motion-Effekt kann verändert werden.")
        }
        if contains(.mayProduceArtifacts) {
            out.append("Erneute Komprimierung kann sichtbare Artefakte erzeugen.")
        }
        if contains(.originalSmallerThanTarget) {
            out.append("Original ist bereits kleiner als das Ziel — kein Export.")
        }
        if contains(.presetUpscalesResolution) {
            out.append("Preset-Auflösung wäre höher als Original — bleibt bei Original-Auflösung.")
        }
        if contains(.targetSizeNotReachable) {
            out.append("Zielgrösse mit gewählten Grenzen vermutlich nicht erreichbar.")
        }
        if contains(.audioWillBeRemoved) {
            out.append("Tonspur wird entfernt.")
        }
        if contains(.codecNotSupportedFallback) {
            out.append("Bevorzugter Codec wird auf diesem Gerät nicht unterstützt — Fallback wird verwendet.")
        }
        if contains(.hdrConvertedToSDR) {
            out.append("HDR-/Dolby-Vision-Charakteristik wird beim Standard-Export voraussichtlich auf SDR reduziert.")
        }
        return out
    }
}
