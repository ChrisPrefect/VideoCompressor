import Foundation

/// Mitlaufende Statistik der aktuellen Bearbeitungssession. Wird im
/// Library-Header angezeigt und nach jedem erfolgreichen Export aktualisiert.
nonisolated public struct SessionStatistics: Sendable, Hashable, Codable {
    public var convertedCount: Int = 0
    public var totalOriginalBytes: Int64 = 0
    public var totalResultBytes: Int64 = 0

    public var savedBytes: Int64 {
        max(0, totalOriginalBytes - totalResultBytes)
    }

    public var savedFraction: Double {
        guard totalOriginalBytes > 0 else { return 0 }
        return Double(savedBytes) / Double(totalOriginalBytes)
    }

    public mutating func record(_ result: ExportResult) {
        convertedCount += 1
        totalOriginalBytes += result.originalSizeBytes
        totalResultBytes += result.resultSizeBytes
    }

    public static let empty = SessionStatistics()
}
