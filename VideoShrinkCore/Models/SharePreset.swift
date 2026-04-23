import Foundation

/// Share-Preset mit harter Zielgrösse. Die Engine versucht, innerhalb dieser
/// Grenze die bestmögliche Qualität zu treffen.
nonisolated public struct SharePreset: Identifiable, Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case whatsapp
        case facebook
        case mail5
        case mail10
        case mail20
        case mail50
        case custom
    }

    public let id: UUID
    public var name: String
    public var kind: Kind

    /// Harte Zielgrösse in Bytes.
    public var maxFileSizeBytes: Int64

    /// Maximaler längerer Kantenwert in Pixel — wird neben der Bitraten­
    /// berechnung als oberes Limit angewendet.
    public var maxLongEdge: Int

    /// Maximale fps. Original-fps werden niemals erhöht.
    public var maxFrameRate: Double

    /// Audio behalten oder entfernen. Beim Entfernen wird das gesamte
    /// Bitratenbudget für Video verwendet.
    public var keepAudio: Bool

    /// Audio-Bitrate in bps, wenn `keepAudio == true`.
    public var audioBitsPerSecond: Int

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        maxFileSizeBytes: Int64,
        maxLongEdge: Int = 1280,
        maxFrameRate: Double = 30,
        keepAudio: Bool = true,
        audioBitsPerSecond: Int = 64_000
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxLongEdge = maxLongEdge
        self.maxFrameRate = maxFrameRate
        self.keepAudio = keepAudio
        self.audioBitsPerSecond = audioBitsPerSecond
    }

    public var isBuiltIn: Bool { kind != .custom }
}

public extension SharePreset {
    /// WhatsApp: heuristisch ~16 MB als sichere Grösse.
    static let whatsapp = SharePreset(
        id: UUID(uuidString: "44444444-0000-0000-0000-000000000001")!,
        name: "WhatsApp",
        kind: .whatsapp,
        maxFileSizeBytes: 16 * 1024 * 1024,
        maxLongEdge: 1280,
        maxFrameRate: 30,
        keepAudio: true,
        audioBitsPerSecond: 64_000
    )

    /// Facebook: heuristisch ~25 MB für Direkt-Upload via Share.
    static let facebook = SharePreset(
        id: UUID(uuidString: "44444444-0000-0000-0000-000000000002")!,
        name: "Facebook",
        kind: .facebook,
        maxFileSizeBytes: 25 * 1024 * 1024,
        maxLongEdge: 1280,
        maxFrameRate: 30,
        keepAudio: true,
        audioBitsPerSecond: 96_000
    )

    static let mail5 = SharePreset(
        id: UUID(uuidString: "44444444-0000-0000-0000-000000000003")!,
        name: "Mail 5 MB",
        kind: .mail5,
        maxFileSizeBytes: 5 * 1024 * 1024,
        maxLongEdge: 854,
        maxFrameRate: 30,
        keepAudio: true,
        audioBitsPerSecond: 48_000
    )

    static let mail10 = SharePreset(
        id: UUID(uuidString: "44444444-0000-0000-0000-000000000004")!,
        name: "Mail 10 MB",
        kind: .mail10,
        maxFileSizeBytes: 10 * 1024 * 1024,
        maxLongEdge: 1024,
        maxFrameRate: 30,
        keepAudio: true,
        audioBitsPerSecond: 64_000
    )

    static let mail20 = SharePreset(
        id: UUID(uuidString: "44444444-0000-0000-0000-000000000005")!,
        name: "Mail 20 MB",
        kind: .mail20,
        maxFileSizeBytes: 20 * 1024 * 1024,
        maxLongEdge: 1280,
        maxFrameRate: 30,
        keepAudio: true,
        audioBitsPerSecond: 96_000
    )

    static let mail50 = SharePreset(
        id: UUID(uuidString: "44444444-0000-0000-0000-000000000006")!,
        name: "Mail 50 MB",
        kind: .mail50,
        maxFileSizeBytes: 50 * 1024 * 1024,
        maxLongEdge: 1920,
        maxFrameRate: 30,
        keepAudio: true,
        audioBitsPerSecond: 128_000
    )

    static let builtIn: [SharePreset] = [.whatsapp, .facebook, .mail5, .mail10, .mail20, .mail50]
}
