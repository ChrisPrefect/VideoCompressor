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
        let jobID = job.id.uuidString
        var step = "preparing"
        Log.transcoding.notice(
            "Export start job=\(jobID, privacy: .public) source=\(job.source.logLabel, privacy: .public) preset=\(job.preset.logLabel, privacy: .public) postAction=\(job.postExportAction.rawValue, privacy: .public)"
        )
        do {
        onStatus?(.preparing)

        // Quelle in AVURLAsset wandeln.
        step = "loadSource"
        let (sourceAsset, sourceKind, originalCreationDate) = try await loadSource(for: job)
        Log.transcoding.notice(
            "Export source loaded job=\(jobID, privacy: .public) file=\(sourceAsset.url.lastPathComponent, privacy: .public) kind=\(sourceKind.rawValue, privacy: .public) hasCreationDate=\((originalCreationDate != nil), privacy: .public)"
        )

        step = "analysis"
        let analysis = try await analyzer.analyze(sourceAsset)
        Log.transcoding.notice(
            "Export analysis done job=\(jobID, privacy: .public) pixels=\(analysis.pixelWidth)x\(analysis.pixelHeight) duration=\(analysis.duration, privacy: .public) fps=\(analysis.nominalFrameRate, privacy: .public) hasAudio=\(analysis.hasAudio, privacy: .public) bytes=\(analysis.fileSizeBytes, privacy: .public)"
        )

        // ZielURL.
        let isShareContext = job.source.isExternalFileSource
        let outputURL = TempFiles.makeURL(
            suffix: "mp4",
            inSharedContainer: isShareContext
        )

        step = "plan"
        let plan = planner.plan(
            for: job,
            analysis: analysis,
            sourceKind: sourceKind,
            outputURL: outputURL
        )
        Log.transcoding.notice(
            "Export plan job=\(jobID, privacy: .public) render=\(plan.renderWidth)x\(plan.renderHeight) encoded=\(plan.encodedWidth)x\(plan.encodedHeight) fps=\(plan.frameRate, privacy: .public) videoBps=\(plan.videoBitsPerSecond, privacy: .public) keepAudio=\(plan.keepAudio, privacy: .public) skip=\(plan.skipExportBecauseOriginalSmaller, privacy: .public)"
        )

        // Wenn der Plan signalisiert, dass das Original kleiner als das
        // Ziel ist, brechen wir mit klarer Meldung ab — kein leiser
        // No-Op.
        if plan.skipExportBecauseOriginalSmaller {
            Log.transcoding.warning("Export skipped job=\(jobID, privacy: .public) reason=originalAlreadySmallerThanTarget")
            throw TranscodingServiceError.originalAlreadySmallerThanTarget(
                warnings: plan.warnings
            )
        }

        onStatus?(.exporting(progress: 0))
        step = "transcode"
        try await transcoder.transcode(
            sourceAsset: sourceAsset,
            plan: plan,
            cancellation: cancellation,
            onProgress: { p in onStatus?(.exporting(progress: p)) }
        )
        Log.transcoding.notice("Export transcode done job=\(jobID, privacy: .public) output=\(outputURL.lastPathComponent, privacy: .public)")

        if cancellation.isCancelled {
            TempFiles.remove(outputURL)
            onStatus?(.cancelled)
            throw TranscodingError.cancelled
        }

        // Validierung der Ausgabe: Datei muss existieren, abspielbar sein
        // und mindestens eine Video-Spur enthalten.
        step = "validateOutput"
        let resultBytes = try await validateOutput(
            at: outputURL,
            originalAnalysis: analysis
        )
        Log.transcoding.notice("Export output validated job=\(jobID, privacy: .public) bytes=\(resultBytes, privacy: .public)")

        var resultWarnings = plan.warnings
        if case .share(let preset) = job.preset,
           resultBytes > preset.maxFileSizeBytes {
            resultWarnings.insert(.targetSizeNotReachable)
        }

        if case .compression = job.preset {
            let originalBytes = max(analysis.fileSizeBytes, analysis.estimatedFileSize)
            if originalBytes > 0, resultBytes >= originalBytes {
                Log.transcoding.warning(
                    "Export result rejected job=\(jobID, privacy: .public) resultBytes=\(resultBytes, privacy: .public) originalBytes=\(originalBytes, privacy: .public)"
                )
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
            step = "saveVideoToLibrary"
            Log.transcoding.notice("Export save to library start job=\(jobID, privacy: .public) output=\(outputURL.lastPathComponent, privacy: .public)")
            do {
                savedID = try await library.saveVideoToLibrary(
                    fileURL: outputURL,
                    originalCreationDate: originalCreationDate
                )
                Log.transcoding.notice("Export save to library done job=\(jobID, privacy: .public) savedID=\(String(describing: savedID), privacy: .private)")
            } catch {
                Log.transcoding.error("Export save to library failed job=\(jobID, privacy: .public) error=\(String(describing: error), privacy: .public)")
                TempFiles.remove(outputURL)
                throw error
            }

            if job.postExportAction == .deleteOriginalAfterSuccess, savedID != nil {
                onStatus?(.finalizing)
                step = "deleteOriginal"
                Log.transcoding.notice("Export delete original start job=\(jobID, privacy: .public) id=\(identifier, privacy: .private)")
                do {
                    try await library.deleteAsset(localIdentifier: identifier)
                    deletedOriginal = true
                    Log.transcoding.notice("Export delete original done job=\(jobID, privacy: .public)")
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
        Log.transcoding.notice(
            "Export finished job=\(jobID, privacy: .public) originalBytes=\(result.originalSizeBytes, privacy: .public) resultBytes=\(result.resultSizeBytes, privacy: .public) deletedOriginal=\(result.originalWasDeleted, privacy: .public)"
        )
        return result
        } catch {
            Log.transcoding.error(
                "Export failed job=\(jobID, privacy: .public) step=\(step, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    private func loadSource(for job: ExportJob) async throws -> (AVURLAsset, VideoKind, Date?) {
        switch job.source {
        case .photoLibrary(let id):
            Log.transcoding.notice("loadSource photoLibrary begin id=\(id, privacy: .private)")
            let avAsset = try await library.loadAVAsset(for: id)
            let metadata = try await library.exportMetadata(for: id)
            Log.transcoding.notice(
                "loadSource photoLibrary done id=\(id, privacy: .private) file=\(avAsset.url.lastPathComponent, privacy: .public) kind=\(metadata.kind.rawValue, privacy: .public)"
            )
            return (avAsset, metadata.kind, metadata.creationDate)
        case .fileURL(let url):
            Log.transcoding.notice("loadSource fileURL url=\(url.lastPathComponent, privacy: .public)")
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

    var logLabel: String {
        switch self {
        case .photoLibrary: return "photoLibrary"
        case .fileURL: return "fileURL"
        }
    }
}

nonisolated private extension ExportJob.PresetSelection {
    var logLabel: String {
        switch self {
        case .compression(let preset): return "compression:\(preset.name)"
        case .share(let preset): return "share:\(preset.name)"
        }
    }
}
