import Foundation

/// Zentrale Konstante für den App-Group-Identifier, mit dem Haupt-App und
/// Share-Extension Daten austauschen.
///
/// Die App-Group muss in beiden Targets als Capability eingetragen sein. In
/// Xcode: Signing & Capabilities → + Capability → App Groups → Identifier.
nonisolated public enum AppGroup {
    public static let identifier = "group.iteconomy.ch.VideoCompressor"

    /// Geteilte UserDefaults für Presets und Settings, die in beiden
    /// Prozessen verfügbar sein müssen. Falls die App-Group-Konfiguration
    /// fehlt (z. B. im Simulator vor manueller Einrichtung), fällt dies auf
    /// Standard-UserDefaults zurück, damit die App nicht abstürzt.
    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Container-URL für temporäre Exporte, die zwischen Extension und App
    /// geteilt werden sollen. `nil`, wenn die App-Group nicht eingerichtet
    /// ist.
    public static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
