import Foundation

/// Anwendungsweite, persistente Benutzereinstellungen. Wird im SettingsStore
/// in shared UserDefaults gehalten, damit Haupt-App und Share-Extension
/// dieselben Defaults sehen.
nonisolated public struct AppSettings: Sendable, Codable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case defaultCodec
        case defaultDeleteBehavior
        case libraryMinimumSizeBytes
        case specialFormatWarning
        case specialFormatWarningWasShown
    }

    public enum DefaultDeleteBehavior: String, Codable, Sendable, Hashable, CaseIterable {
        case askEachTime
        case keepOriginals
        case deleteOriginals

        public var displayName: String {
            switch self {
            case .askEachTime: return "Jedes Mal fragen"
            case .keepOriginals: return "Originale immer behalten"
            case .deleteOriginals: return "Originale nach Erfolg löschen"
            }
        }
    }

    public enum SpecialFormatWarning: String, Codable, Sendable, Hashable, CaseIterable {
        case alwaysWarn
        case warnOnce
        case neverWarn

        public var displayName: String {
            switch self {
            case .alwaysWarn: return "Immer warnen"
            case .warnOnce: return "Einmalig warnen"
            case .neverWarn: return "Nie warnen"
            }
        }
    }

    public var defaultCodec: VideoCodecPreference = .hevc
    public var defaultDeleteBehavior: DefaultDeleteBehavior = .askEachTime
    public var libraryMinimumSizeBytes: Int64 = 50 * 1024 * 1024
    public var specialFormatWarning: SpecialFormatWarning = .alwaysWarn
    public var specialFormatWarningWasShown: Bool = false

    public init(
        defaultCodec: VideoCodecPreference = .hevc,
        defaultDeleteBehavior: DefaultDeleteBehavior = .askEachTime,
        libraryMinimumSizeBytes: Int64 = 50 * 1024 * 1024,
        specialFormatWarning: SpecialFormatWarning = .alwaysWarn,
        specialFormatWarningWasShown: Bool = false
    ) {
        self.defaultCodec = defaultCodec
        self.defaultDeleteBehavior = defaultDeleteBehavior
        self.libraryMinimumSizeBytes = libraryMinimumSizeBytes
        self.specialFormatWarning = specialFormatWarning
        self.specialFormatWarningWasShown = specialFormatWarningWasShown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultCodec = try container.decodeIfPresent(VideoCodecPreference.self, forKey: .defaultCodec) ?? .hevc
        self.defaultDeleteBehavior = try container.decodeIfPresent(DefaultDeleteBehavior.self, forKey: .defaultDeleteBehavior) ?? .askEachTime
        self.libraryMinimumSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .libraryMinimumSizeBytes) ?? 50 * 1024 * 1024
        self.specialFormatWarning = try container.decodeIfPresent(SpecialFormatWarning.self, forKey: .specialFormatWarning) ?? .alwaysWarn
        self.specialFormatWarningWasShown = try container.decodeIfPresent(Bool.self, forKey: .specialFormatWarningWasShown) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultCodec, forKey: .defaultCodec)
        try container.encode(defaultDeleteBehavior, forKey: .defaultDeleteBehavior)
        try container.encode(libraryMinimumSizeBytes, forKey: .libraryMinimumSizeBytes)
        try container.encode(specialFormatWarning, forKey: .specialFormatWarning)
        try container.encode(specialFormatWarningWasShown, forKey: .specialFormatWarningWasShown)
    }

    public static let `default` = AppSettings()
}
