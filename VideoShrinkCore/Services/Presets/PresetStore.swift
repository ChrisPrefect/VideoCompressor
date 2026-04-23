import Foundation
import Observation

/// Persistenter Store für eingebaute und benutzerdefinierte Presets. Die
/// Daten liegen im geteilten App-Group-UserDefaults, damit Haupt-App und
/// Share-Extension dieselben Presets sehen.
@MainActor
@Observable
public final class PresetStore {

    private enum Keys {
        static let compression = "presets.compression.all.v2"
        static let share = "presets.share.all.v2"
        static let legacyCustomCompression = "presets.compression.custom.v1"
        static let legacyCustomShare = "presets.share.custom.v1"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    public private(set) var compressionPresets: [CompressionPreset] = []
    public private(set) var sharePresets: [SharePreset] = []

    public var allCompression: [CompressionPreset] {
        compressionPresets
    }

    public var allShare: [SharePreset] {
        sharePresets
    }

    public init(defaults: UserDefaults = AppGroup.sharedDefaults) {
        self.defaults = defaults
        load()
    }

    public func reload() {
        load()
    }

    private func load() {
        if let data = defaults.data(forKey: Keys.compression),
           let arr = try? decoder.decode([CompressionPreset].self, from: data) {
            compressionPresets = arr
        } else {
            compressionPresets = migratedCompressionPresets()
            persistCompression()
        }
        if let data = defaults.data(forKey: Keys.share),
           let arr = try? decoder.decode([SharePreset].self, from: data) {
            sharePresets = arr
        } else {
            sharePresets = migratedSharePresets()
            persistShare()
        }
    }

    private func persistCompression() {
        guard let data = try? encoder.encode(compressionPresets) else { return }
        defaults.set(data, forKey: Keys.compression)
    }

    private func persistShare() {
        guard let data = try? encoder.encode(sharePresets) else { return }
        defaults.set(data, forKey: Keys.share)
    }

    public func upsert(_ preset: CompressionPreset) {
        if let idx = compressionPresets.firstIndex(where: { $0.id == preset.id }) {
            compressionPresets[idx] = preset
        } else {
            compressionPresets.append(preset)
        }
        persistCompression()
    }

    public func deleteCompression(at offsets: IndexSet) {
        compressionPresets = compressionPresets.enumerated()
            .compactMap { offsets.contains($0.offset) ? nil : $0.element }
        persistCompression()
    }

    public func deleteCompression(id: UUID) {
        compressionPresets.removeAll { $0.id == id }
        persistCompression()
    }

    public func upsert(_ preset: SharePreset) {
        if let idx = sharePresets.firstIndex(where: { $0.id == preset.id }) {
            sharePresets[idx] = preset
        } else {
            sharePresets.append(preset)
        }
        persistShare()
    }

    public func deleteShare(at offsets: IndexSet) {
        sharePresets = sharePresets.enumerated()
            .compactMap { offsets.contains($0.offset) ? nil : $0.element }
        persistShare()
    }

    public func deleteShare(id: UUID) {
        sharePresets.removeAll { $0.id == id }
        persistShare()
    }

    public var preferredCompressionPreset: CompressionPreset? {
        compressionPresets.first
    }

    public var preferredSharePreset: SharePreset? {
        sharePresets.first
    }

    private func migratedCompressionPresets() -> [CompressionPreset] {
        guard let data = defaults.data(forKey: Keys.legacyCustomCompression),
              let legacy = try? decoder.decode([CompressionPreset].self, from: data) else {
            return CompressionPreset.builtIn
        }
        return CompressionPreset.builtIn + legacy
    }

    private func migratedSharePresets() -> [SharePreset] {
        guard let data = defaults.data(forKey: Keys.legacyCustomShare),
              let legacy = try? decoder.decode([SharePreset].self, from: data) else {
            return SharePreset.builtIn
        }
        return SharePreset.builtIn + legacy
    }
}
