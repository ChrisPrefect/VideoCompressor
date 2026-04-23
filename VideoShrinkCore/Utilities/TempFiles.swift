import Foundation

/// Verwaltet temporäre Export-Dateien und sorgt für sauberes Cleanup.
nonisolated public enum TempFiles {

    /// Liefert eine eindeutige URL im temporären Verzeichnis. Optional kann
    /// ein App-Group-Container genutzt werden, damit die Extension Dateien
    /// für die Haupt-App ablegen kann.
    public static func makeURL(suffix: String = "mp4", inSharedContainer: Bool = false) -> URL {
        let baseURL: URL
        if inSharedContainer, let shared = AppGroup.sharedContainerURL {
            baseURL = shared.appendingPathComponent("Exports", isDirectory: true)
            try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        } else {
            baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
        let name = "VideoShrink-\(UUID().uuidString).\(suffix)"
        return baseURL.appendingPathComponent(name)
    }

    public static func remove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Räumt ältere Export-Dateien (älter als `maxAge` Sekunden) im
    /// gemeinsamen Container auf. Soll beim App-Start aufgerufen werden.
    public static func purgeStaleSharedExports(maxAge: TimeInterval = 60 * 60) {
        guard let shared = AppGroup.sharedContainerURL else { return }
        let dir = shared.appendingPathComponent("Exports", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for url in urls {
            if let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mod < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Liefert die Dateigrösse einer URL in Bytes oder `nil`, falls nicht
    /// ermittelbar.
    public static func fileSize(of url: URL) -> Int64? {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? NSNumber else { return nil }
        return size.int64Value
    }
}
