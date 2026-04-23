import Foundation
import Observation

nonisolated public struct CompressionHistoryRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { originalAssetIdentifier }

    public let originalAssetIdentifier: String
    public let compressedAssetIdentifier: String
    public let outputURL: URL
    public let originalSizeBytes: Int64
    public let resultSizeBytes: Int64
    public let durationSeconds: TimeInterval
    public let originalWasDeleted: Bool
    public let warnings: WarningFlags
    public let createdAt: Date

    public var exportResult: ExportResult {
        ExportResult(
            outputURL: outputURL,
            originalSizeBytes: originalSizeBytes,
            resultSizeBytes: resultSizeBytes,
            durationSeconds: durationSeconds,
            savedAssetIdentifier: compressedAssetIdentifier,
            originalWasDeleted: originalWasDeleted,
            warnings: warnings
        )
    }
}

@MainActor
@Observable
public final class CompressionHistoryStore {
    private enum Keys {
        static let records = "compression.history.records.v1"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    public private(set) var recordsByOriginalID: [String: CompressionHistoryRecord]

    public init(defaults: UserDefaults = AppGroup.sharedDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.records),
           let parsed = try? decoder.decode([String: CompressionHistoryRecord].self, from: data) {
            self.recordsByOriginalID = parsed
        } else {
            self.recordsByOriginalID = [:]
        }
    }

    public func record(_ result: ExportResult, forOriginal originalAssetIdentifier: String) {
        guard let compressedAssetIdentifier = result.savedAssetIdentifier else { return }
        recordsByOriginalID[originalAssetIdentifier] = CompressionHistoryRecord(
            originalAssetIdentifier: originalAssetIdentifier,
            compressedAssetIdentifier: compressedAssetIdentifier,
            outputURL: result.outputURL,
            originalSizeBytes: result.originalSizeBytes,
            resultSizeBytes: result.resultSizeBytes,
            durationSeconds: result.durationSeconds,
            originalWasDeleted: result.originalWasDeleted,
            warnings: result.warnings,
            createdAt: Date()
        )
        persist()
    }

    public func record(forOriginal originalAssetIdentifier: String) -> CompressionHistoryRecord? {
        recordsByOriginalID[originalAssetIdentifier]
    }

    public func removeRecord(forOriginal originalAssetIdentifier: String) {
        recordsByOriginalID.removeValue(forKey: originalAssetIdentifier)
        persist()
    }

    public func removeRecord(compressedAssetIdentifier: String) {
        guard let originalID = recordsByOriginalID.first(where: {
            $0.value.compressedAssetIdentifier == compressedAssetIdentifier
        })?.key else { return }
        recordsByOriginalID.removeValue(forKey: originalID)
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(recordsByOriginalID) else { return }
        defaults.set(data, forKey: Keys.records)
    }
}
