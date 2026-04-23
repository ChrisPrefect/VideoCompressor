import Foundation

/// Sammlung statischer Formatierer. Wir vermeiden je-Aufruf-Allokation, indem
/// wir Formatter zwischenspeichern. Formatter-Typen sind in modernen
/// Foundation-Versionen Sendable, daher reicht `nonisolated`.
nonisolated public enum Formatting {

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        f.includesUnit = true
        f.isAdaptive = true
        return f
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .positional
        f.zeroFormattingBehavior = [.pad]
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    public static func bytes(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return byteFormatter.string(fromByteCount: bytes)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 60 {
            // < 1 min: 0:23 statt 23
            return durationFormatter.string(from: max(seconds, 1)) ?? "—"
        }
        return durationFormatter.string(from: seconds) ?? "—"
    }

    public static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateFormatter.string(from: date)
    }

    public static func percentage(_ fraction: Double, fractionDigits: Int = 0) -> String {
        let n = NumberFormatter()
        n.numberStyle = .percent
        n.minimumFractionDigits = fractionDigits
        n.maximumFractionDigits = fractionDigits
        return n.string(from: NSNumber(value: fraction)) ?? "—"
    }
}
