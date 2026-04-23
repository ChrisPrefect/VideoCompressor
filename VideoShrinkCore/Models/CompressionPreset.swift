import Foundation

/// Komprimierungs-Preset für die Haupt-App. Definiert obere Grenzen, die
/// niemals überschritten werden, aber niemals zu künstlichem Hochskalieren
/// oder höheren fps führen.
nonisolated public struct CompressionPreset: Identifiable, Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case mild
        case balanced
        case aggressive
        case custom
    }

    public let id: UUID
    public var name: String
    public var kind: Kind

    /// Maximaler längerer Kantenwert in Pixel. Wenn das Original kleiner ist,
    /// bleibt es bei der Originalauflösung.
    public var maxLongEdge: Int

    /// Obere fps-Grenze. Wenn das Original niedriger liegt, bleibt es so.
    public var maxFrameRate: Double

    /// Maximale Bitrate pro Sekunde in Bits. Wird auch genutzt, um aus
    /// "MB/min" abzuleiten.
    public var maxVideoBitsPerSecond: Int

    public var keepAudio: Bool
    public var audioBitsPerSecond: Int

    /// Erlaubt, das Halbieren der Originalauflösung zu erzwingen, wie im
    /// Pflichtenheft für Standard-Presets gefordert.
    public var enforceHalfResolution: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        maxLongEdge: Int,
        maxFrameRate: Double,
        maxVideoBitsPerSecond: Int,
        keepAudio: Bool = true,
        audioBitsPerSecond: Int = 96_000,
        enforceHalfResolution: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.maxLongEdge = maxLongEdge
        self.maxFrameRate = maxFrameRate
        self.maxVideoBitsPerSecond = maxVideoBitsPerSecond
        self.keepAudio = keepAudio
        self.audioBitsPerSecond = audioBitsPerSecond
        self.enforceHalfResolution = enforceHalfResolution
    }

    /// Bequeme Konvertierung MB/min ↔ bps, weil der Editor in MB/min denkt.
    public var megabytesPerMinute: Double {
        get { Double(maxVideoBitsPerSecond) * 60.0 / 8.0 / 1_000_000.0 }
        set { maxVideoBitsPerSecond = max(150_000, Int(newValue * 1_000_000.0 / 60.0 * 8.0)) }
    }

    public var isBuiltIn: Bool { kind != .custom }
}

public extension CompressionPreset {
    /// "Mild": leicht reduzieren, hohe Qualität.
    static let mild = CompressionPreset(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "Mild",
        kind: .mild,
        maxLongEdge: 1920,
        maxFrameRate: 30,
        maxVideoBitsPerSecond: 8_000_000,
        keepAudio: true,
        audioBitsPerSecond: 128_000,
        enforceHalfResolution: true
    )

    /// "Balanced": deutliche Reduktion bei guter Qualität.
    static let balanced = CompressionPreset(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "Balanced",
        kind: .balanced,
        maxLongEdge: 1280,
        maxFrameRate: 30,
        maxVideoBitsPerSecond: 4_000_000,
        keepAudio: true,
        audioBitsPerSecond: 96_000,
        enforceHalfResolution: true
    )

    /// "Aggressive": kleinste Datei, sichtbarer Qualitätsverlust ist
    /// akzeptiert.
    static let aggressive = CompressionPreset(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "Aggressive",
        kind: .aggressive,
        maxLongEdge: 854,
        maxFrameRate: 30,
        maxVideoBitsPerSecond: 1_500_000,
        keepAudio: true,
        audioBitsPerSecond: 64_000,
        enforceHalfResolution: true
    )

    static let builtIn: [CompressionPreset] = [.mild, .balanced, .aggressive]
}
