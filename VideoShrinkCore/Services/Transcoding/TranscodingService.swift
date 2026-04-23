import Foundation
import AVFoundation
import Photos
import os

/// Orchestriert den End-to-End-Export eines Jobs:
/// Quell-Asset laden → Analysieren → Plan berechnen → Transcoden →
/// Validieren → in Mediathek speichern → optional Original löschen.
///
/// Die Engine ist `Sendable` und kann von ViewModels parallel genutzt
/// werden, solange jeder Aufruf seine eigene `Cancellation` mitbringt.
nonisolated public final class TranscodingService: Sendable {

    public let library: PhotoLibraryService
    public let analyzer: VideoAnalysisService
    public let transcoder: ReaderWriterTranscoder
    public let planner: ExportPlanner

    public init(
        library: PhotoLibraryService,
        analyzer: VideoAnalysisService,
        transcoder: ReaderWriterTranscoder = ReaderWriterTranscoder(),
        planner: ExportPlanner = ExportPlanner()
    ) {
        self.library = library
        self.analyzer = analyzer
        self.transcoder = transcoder
        self.planner = planner
    }

    /// Führt einen Job aus. Liefert ein `ExportResult`. Während des Laufs
    /// werden Status-Updates über `onStatus` gemeldet.
    public func run(
        job: ExportJob,
        cancellation: Cancellation = Cancellation(),
        onStatus: (@Sendable (ExportJobStatus) -> Void)? = nil
    ) async throws -> ExportResult {
        onStatus?(.preparing)

        // Quelle in AVURLAsset wandeln.
        let (sourceAsset, sourceKind, originalCreationDate) = try await loadSource(for: job)

        let analysis = try await analyzer.analyze(sourceAsset)

        // ZielURL.
        let isShareContext = job.source.isExternalFileSource
        let outputURL = TempFiles.makeURL(
            suffix: "mp4",
            inSharedContainer: isShareContext
        )

        let plan = planner.plan(
            for: job,
            analysis: analysis,
            sourceKind: sourceKind,
            outputURL: outputURL
        )

        // Wenn der Plan signalisiert, dass das Original kleiner als das
        // Ziel ist, brechen wir mit klarer Meldung ab — kein leiser
        // No-Op.
        if plan.skipExportBecauseOriginalSmaller {
            throw TranscodingServiceError.originalAlreadySmallerThanTarget(
                warnings: plan.warnings
            )
        }

        onStatus?(.exporting(progress: 0))
        try await transcoder.transcode(
            sourceAsset: sourceAsset,
            plan: plan,
            cancellation: cancellation,
            onProgress: { p in onStatus?(.exporting(progress: p)) }
        )

        if cancellation.isCancelled {
            TempFiles.remove(outputURL)
            onStatus?(.cancelled)
            throw TranscodingError.cancelled
        }

        // Validierung der Ausgabe: Datei muss existieren, abspielbar sein
        // und mindestens eine Video-Spur enthalten.
        let resultBytes = try await validateOutput(
            at: outputURL,
            originalAnalysis: analysis
        )

        var resultWarnings = plan.warnings
        if case .share(let preset) = job.preset,
           resultBytes > preset.maxFileSizeBytes {
            resultWarnings.insert(.targetSizeNotReachable)
        }

        if case .compression = job.preset {
            let originalBytes = max(analysis.fileSizeBytes, analysis.estimatedFileSize)
            if originalBytes > 0, resultBytes >= originalBytes {
                TempFiles.remove(outputURL)
                throw TranscodingServiceError.resultNotSmallerThanOriginal
            }
        }

        guard resultBytes > 0 else {
            TempFiles.remove(outputURL)
            throw TranscodingServiceError.outputValidationFailed
        }

        // Optional in Photos schreiben (nur Library-Fluss; Share-Extension
        // nutzt den Pfad nicht zwingend).
        var savedID: String? = nil
        var deletedOriginal = false

        if case .photoLibrary(let identifier) = job.source {
            onStatus?(.writingToLibrary)
            do {
                savedID = try await library.saveVideoToLibrary(
                    fileURL: outputURL,
                    originalCreationDate: originalCreationDate
                )
            } catch {
                TempFiles.remove(outputURL)
                throw error
            }

            if job.postExportAction == .deleteOriginalAfterSuccess, savedID != nil {
                onStatus?(.finalizing)
                do {
                    try await library.deleteAsset(localIdentifier: identifier)
                    deletedOriginal = true
                } catch {
                    // Wir scheitern hier nicht hart — das neue Asset ist
                    // bereits gespeichert. Der Aufrufer sieht in
                    // `originalWasDeleted == false`, dass die Löschung
                    // nicht erfolgt ist.
                    Log.transcoding.warning("Original-Löschung fehlgeschlagen: \(String(describing: error))")
                }
            }
        }

        let result = ExportResult(
            outputURL: outputURL,
            originalSizeBytes: max(analysis.fileSizeBytes, analysis.estimatedFileSize),
            resultSizeBytes: resultBytes,
            durationSeconds: analysis.duration,
            savedAssetIdentifier: savedID,
            originalWasDeleted: deletedOriginal,
            warnings: resultWarnings
        )
        onStatus?(.finished(result))
        return result
    }

    private func loadSource(for job: ExportJob) async throws -> (AVURLAsset, VideoKind, Date?) {
        switch job.source {
        case .photoLibrary(let id):
            let avAsset = try await library.loadAVAsset(for: id)
            let phAsset = await library.asset(for: id)
            let kind = phAsset.map(VideoKind.classify(from:)) ?? .standard
            return (avAsset, kind, phAsset?.creationDate)
        case .fileURL(let url):
            let avAsset = AVURLAsset(url: url)
            return (avAsset, .standard, nil)
        }
    }

    private func validateOutput(
        at outputURL: URL,
        originalAnalysis: VideoAnalysis
    ) async throws -> Int64 {
        guard let resultBytes = TempFiles.fileSize(of: outputURL), resultBytes > 0 else {
            TempFiles.remove(outputURL)
            throw TranscodingServiceError.outputValidationFailed
        }

        let resultAsset = AVURLAsset(url: outputURL)
        let (duration, isPlayable, tracks) = try await resultAsset.load(.duration, .isPlayable, .tracks)
        let seconds = duration.seconds
        guard isPlayable,
              seconds.isFinite,
              seconds > 0,
              tracks.contains(where: { $0.mediaType == .video }) else {
            TempFiles.remove(outputURL)
            throw TranscodingServiceError.outputNotPlayable
        }

        if originalAnalysis.duration.isFinite,
           originalAnalysis.duration > 0,
           seconds < min(0.5, originalAnalysis.duration * 0.1) {
            TempFiles.remove(outputURL)
            throw TranscodingServiceError.outputNotPlayable
        }

        return resultBytes
    }
}

public enum TranscodingServiceError: LocalizedError {
    case outputValidationFailed
    case outputNotPlayable
    case originalAlreadySmallerThanTarget(warnings: WarningFlags)
    case resultNotSmallerThanOriginal

    public var errorDescription: String? {
        switch self {
        case .outputValidationFailed:
            return "Die Ausgabedatei konnte nicht erfolgreich erstellt werden."
        case .outputNotPlayable:
            return "Die Ausgabedatei wurde erstellt, ist aber nicht abspielbar. Das Original wurde nicht verändert."
        case .originalAlreadySmallerThanTarget:
            return "Das Original ist bereits kleiner als das gewählte Ziel — kein Export ausgeführt."
        case .resultNotSmallerThanOriginal:
            return "Der Export wäre nicht kleiner als das Original. Die neue Datei wurde verworfen und das Original bleibt unverändert."
        }
    }
}

nonisolated private extension ExportJob.Source {
    var isExternalFileSource: Bool {
        if case .fileURL = self { return true }
        return false
    }
}
