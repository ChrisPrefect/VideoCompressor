import Foundation
import Observation

/// Persistenter Store für Anwendungs-Settings. Wie der PresetStore liegen
/// die Daten in shared UserDefaults, damit Haupt-App und Share-Extension
/// dieselben Defaults sehen.
@MainActor
@Observable
public final class SettingsStore {

    private enum Keys {
        static let settings = "settings.app.v1"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    public var settings: AppSettings {
        didSet { persist() }
    }

    public init(defaults: UserDefaults = AppGroup.sharedDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.settings),
           let parsed = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = parsed
        } else {
            self.settings = .default
        }
    }

    private func persist() {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Keys.settings)
    }

    public var shouldShowSpecialFormatWarning: Bool {
        switch settings.specialFormatWarning {
        case .alwaysWarn:
            return true
        case .warnOnce:
            return !settings.specialFormatWarningWasShown
        case .neverWarn:
            return false
        }
    }

    public func markSpecialFormatWarningShown() {
        guard settings.specialFormatWarning == .warnOnce else { return }
        settings.specialFormatWarningWasShown = true
    }
}
