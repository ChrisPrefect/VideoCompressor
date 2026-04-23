import Foundation
import AVFoundation
import Observation
import SwiftUI
import UIKit
import os

@MainActor
@Observable
public final class VideoDetailViewModel {
    public enum PresetChoice: Hashable {
        case compression(CompressionPreset)
        case share(SharePreset)

        var asJobPreset: ExportJob.PresetSelection {
            switch self {
            case .compression(let p): return .compression(p)
            case .share(let p): return .share(p)
            }
        }

        var displayName: String {
            switch self {
            case .compression(let p): return p.name
            case .share(let p): return p.name
            }
        }
    }

    public enum PlaybackSource: String, CaseIterable, Identifiable {
        case original
        case compressed

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .original: return "Original"
            case .compressed: return "Komprimiert"
            }
        }
    }

    /// Welche Konfirmation aktuell aussteht. Wir nutzen dieses einfache
    /// State-Enum als Quelle der Wahrheit für die Detail-View, damit immer
    /// nur ein Dialog gleichzeitig sichtbar ist und der Flow eindeutig
    /// bleibt.
    public enum PendingConfirmation: Equatable {
        case none
        case specialFormat
        case willDeleteOriginal
        case askPostExportDelete(savedAssetIdentifier: String?)
    }

    public private(set) var thumbnail: UIImage?
    public private(set) var status: ExportJobStatus = .pending
    public var presetChoice: PresetChoice = .compression(.balanced)
    public var deleteOriginalAfterSuccess: Bool = false
    public var errorMessage: String?
    public var lastResult: ExportResult?
    public private(set) var analysisWarnings: WarningFlags = []
    public private(set) var preflightAnalysis: VideoAnalysis?
    public var pending: PendingConfirmation = .none
    public private(set) var playerIsReady: Bool = false
    public private(set) var originalPlaybackReady: Bool = false
    public private(set) var compressedPlaybackReady: Bool = false
    public private(set) var currentPlaybackSource: PlaybackSource = .original
    public private(set) var originalIsAvailable: Bool = true
    public private(set) var compressedIsAvailable: Bool = false
    public private(set) var compressedWasDeleted: Bool = false

    @ObservationIgnored public let item: LibraryVideoItem
    @ObservationIgnored public let originalPlayer = AVPlayer()
    @ObservationIgnored public let compressedPlayer = AVPlayer()
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var cancellation = Cancellation()
    @ObservationIgnored private var originalPlayerItem: AVPlayerItem?
    @ObservationIgnored private var compressedPlayerItem: AVPlayerItem?

    public init(item: LibraryVideoItem, environment: AppEnvironment, initialResult: ExportResult? = nil) {
        self.item = item
        self.environment = environment
        self.lastResult = initialResult
        if let preset = environment.presets.preferredCompressionPreset {
            self.presetChoice = .compression(preset)
        } else if let preset = environment.presets.preferredSharePreset {
            self.presetChoice = .share(preset)
        }
        // Toggle nur dann vorbelegen, wenn der Default explizit "löschen"
        // ist. "askEachTime" bleibt offen und triggert nach Export einen
        // Sheet.
        if environment.settings.settings.defaultDeleteBehavior == .deleteOriginals {
            self.deleteOriginalAfterSuccess = true
        }
    }

    public func loadThumbnail() async {
        thumbnail = await environment.library.thumbnail(
            for: item.id,
            targetSize: CGSize(width: 720, height: 720)
        )
    }

    public func loadOriginalPlayback() async {
        guard originalPlayerItem == nil else { return }
        do {
            let asset = try await environment.library.loadAVAsset(for: item.id)
            let playerItem = AVPlayerItem(asset: asset)
            self.originalPlayerItem = playerItem
            originalPlayer.replaceCurrentItem(with: playerItem)
            originalPlayer.isMuted = currentPlaybackSource != .original
            originalPlaybackReady = true
            playerIsReady = true
        } catch {
            Log.app.debug("Original-Playback fehlgeschlagen: \(String(describing: error))")
        }
    }

    public func loadCompressedPlaybackIfAvailable() async {
        if let result = lastResult {
            compressedWasDeleted = false
            if await prepareCompressedPlayback(for: result) {
                await selectPlaybackSource(.compressed)
            }
            return
        }
        guard let record = environment.history.record(forOriginal: item.id) else { return }
        let result = record.exportResult
        if await prepareCompressedPlayback(for: result, preferSavedAsset: true) {
            lastResult = result
            compressedWasDeleted = false
            await selectPlaybackSource(.compressed)
        } else {
            environment.history.removeRecord(forOriginal: item.id)
        }
    }

    public func runPreflight() async {
        guard preflightAnalysis == nil else { return }
        do {
            let avAsset = try await environment.library.loadAVAsset(for: item.id)
            let analysis = try await environment.analyzer.analyze(avAsset)
            self.preflightAnalysis = analysis
            if analysis.isHDR {
                self.analysisWarnings.insert(.hdrConvertedToSDR)
            }
        } catch {
            Log.app.debug("Preflight-Analyse fehlgeschlagen: \(String(describing: error))")
        }
    }

    public func syncPresetChoice() {
        let compressionPresets = environment.presets.allCompression
        let sharePresets = environment.presets.allShare

        switch presetChoice {
        case .compression(let preset) where compressionPresets.contains(preset):
            return
        case .share(let preset) where sharePresets.contains(preset):
            return
        default:
            if let preset = compressionPresets.first {
                presetChoice = .compression(preset)
            } else if let preset = sharePresets.first {
                presetChoice = .share(preset)
            }
        }
    }

    public var hasAnyPreset: Bool {
        !environment.presets.allCompression.isEmpty || !environment.presets.allShare.isEmpty
    }

    public var comparisonAvailable: Bool {
        originalIsAvailable && compressedIsAvailable && originalPlaybackReady && compressedPlaybackReady
    }

    public var willAskBeforeSpecialFormatExport: Bool {
        item.kind.requiresConfirmation && environment.settings.shouldShowSpecialFormatWarning
    }

    public var currentPreview: ExportPreview? {
        preview(for: presetChoice)
    }

    public func preview(for presetChoice: PresetChoice) -> ExportPreview? {
        guard let analysis = preflightAnalysis else { return nil }
        return environment.transcoding.planner.preview(
            for: ExportJob(
                source: .photoLibrary(localIdentifier: item.id),
                preset: presetChoice.asJobPreset
            ),
            analysis: analysis,
            sourceKind: item.kind
        )
    }

    /// Vom Detail-Screen aufgerufen, wenn der User auf "Komprimieren
    /// starten" tippt. Entscheidet, ob vor dem Export erst ein
    /// Confirmation-Dialog aufpoppen muss.
    public func requestStart() {
        Log.app.notice("Detail export requested item=\(self.item.id, privacy: .private) preset=\(self.presetChoice.displayName, privacy: .public) deleteOriginal=\(self.deleteOriginalAfterSuccess, privacy: .public)")
        syncPresetChoice()
        guard hasAnyPreset else {
            errorMessage = "Es gibt kein Preset mehr. Lege unter Einstellungen ein neues Preset an."
            return
        }
        if item.kind.requiresConfirmation,
           environment.settings.shouldShowSpecialFormatWarning {
            environment.settings.markSpecialFormatWarningShown()
            pending = .specialFormat
            return
        }
        if deleteOriginalAfterSuccess {
            pending = .willDeleteOriginal
            return
        }
        Task { await performExport() }
    }

    /// Spezialformat bestätigt — nächster Schritt ist evtl. die
    /// Lösch-Bestätigung, sonst direkter Start.
    public func confirmSpecialFormat() {
        pending = .none
        if deleteOriginalAfterSuccess {
            pending = .willDeleteOriginal
        } else {
            Task { await performExport() }
        }
    }

    public func confirmDeleteAndStart() {
        pending = .none
        Task { await performExport() }
    }

    public func cancelPending() {
        pending = .none
    }

    /// Vom Sheet aufgerufen, wenn der User nach erfolgreichem Export
    /// "ja, löschen" wählt (nur im askEachTime-Modus).
    public func confirmPostExportDelete() async {
        guard case .askPostExportDelete(let savedID) = pending,
              savedID != nil else {
            pending = .none
            return
        }
        do {
            try await environment.library.deleteAsset(localIdentifier: item.id)
            // ExportResult mit gesetztem Flag aktualisieren.
            if var r = lastResult {
                r = ExportResult(
                    outputURL: r.outputURL,
                    originalSizeBytes: r.originalSizeBytes,
                    resultSizeBytes: r.resultSizeBytes,
                    durationSeconds: r.durationSeconds,
                    savedAssetIdentifier: r.savedAssetIdentifier,
                    originalWasDeleted: true,
                    warnings: r.warnings
                )
                lastResult = r
            }
            markOriginalUnavailable()
            if compressedIsAvailable {
                await selectPlaybackSource(.compressed)
            } else {
                playerIsReady = false
            }
        } catch {
            errorMessage = "Original konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
        pending = .none
    }

    public func declinePostExportDelete() {
        pending = .none
    }

    private func performExport() async {
        syncPresetChoice()
        let cancellation = Cancellation()
        self.cancellation = cancellation
        Log.app.notice("Detail export task started item=\(self.item.id, privacy: .private) preset=\(self.presetChoice.displayName, privacy: .public)")
        let job = ExportJob(
            source: .photoLibrary(localIdentifier: item.id),
            preset: presetChoice.asJobPreset,
            postExportAction: deleteOriginalAfterSuccess ? .deleteOriginalAfterSuccess : .keepOriginal
        )
        do {
            let result = try await environment.transcoding.run(
                job: job,
                cancellation: cancellation,
                onStatus: { status in
                    Task { @MainActor [weak self] in
                        self?.status = status
                    }
                }
            )
            self.lastResult = result
            self.compressedWasDeleted = false
            if result.originalWasDeleted {
                markOriginalUnavailable()
            }
            environment.history.record(result, forOriginal: item.id)
            if await prepareCompressedPlayback(for: result) {
                await playPlayback(preferred: .compressed)
            }
            environment.statistics.record(result)
            // askEachTime: Toggle war off, also Sheet aufpoppen.
            if !deleteOriginalAfterSuccess,
               environment.settings.settings.defaultDeleteBehavior == .askEachTime,
               result.savedAssetIdentifier != nil {
                pending = .askPostExportDelete(savedAssetIdentifier: result.savedAssetIdentifier)
            }
        } catch let error as TranscodingServiceError {
            Log.app.error("Detail export failed typed item=\(self.item.id, privacy: .private) error=\(String(describing: error), privacy: .public)")
            switch error {
            case .originalAlreadySmallerThanTarget(let warnings):
                self.analysisWarnings.formUnion(warnings)
                self.errorMessage = error.localizedDescription
            default:
                self.errorMessage = error.localizedDescription
            }
            self.status = .failed(error.localizedDescription)
        } catch {
            Log.app.error("Detail export failed item=\(self.item.id, privacy: .private) error=\(String(describing: error), privacy: .public)")
            self.errorMessage = error.localizedDescription
            self.status = .failed(error.localizedDescription)
        }
    }

    public func cancel() {
        cancellation.cancel()
    }

    public func togglePlaybackSource() async {
        guard comparisonAvailable else { return }
        await selectPlaybackSource(currentPlaybackSource == .compressed ? .original : .compressed)
    }

    public func playPlayback(preferred source: PlaybackSource? = nil) async {
        if let source {
            await selectPlaybackSource(source)
        }
        guard isPlaybackReady(for: currentPlaybackSource) else { return }

        let activePlayer = player(for: currentPlaybackSource)
        syncMuteStates()
        if comparisonAvailable {
            let otherSource: PlaybackSource = currentPlaybackSource == .original ? .compressed : .original
            let otherPlayer = player(for: otherSource)
            await seekPlayer(otherPlayer, to: activePlayer.currentSyncTime)
            otherPlayer.play()
        }
        activePlayer.play()
        playerIsReady = true
    }

    public func pausePlayback() {
        originalPlayer.pause()
        compressedPlayer.pause()
    }

    public func selectPlaybackSource(_ source: PlaybackSource) async {
        guard isPlaybackReady(for: source) else { return }
        guard source != currentPlaybackSource else {
            syncMuteStates()
            return
        }

        let activePlayer = player(for: currentPlaybackSource)
        let targetPlayer = player(for: source)
        let wasPlaying = activePlayer.rate > 0
        await seekPlayer(targetPlayer, to: activePlayer.currentSyncTime)
        currentPlaybackSource = source
        syncMuteStates()
        playerIsReady = true
        if wasPlaying {
            targetPlayer.play()
        } else {
            targetPlayer.pause()
        }
    }

    public func deleteOriginal() async {
        guard originalIsAvailable else { return }
        do {
            try await environment.library.deleteAsset(localIdentifier: item.id)
            if var result = lastResult, !result.originalWasDeleted {
                result = ExportResult(
                    outputURL: result.outputURL,
                    originalSizeBytes: result.originalSizeBytes,
                    resultSizeBytes: result.resultSizeBytes,
                    durationSeconds: result.durationSeconds,
                    savedAssetIdentifier: result.savedAssetIdentifier,
                    originalWasDeleted: true,
                    warnings: result.warnings
                )
                lastResult = result
            }
            markOriginalUnavailable()
            if compressedIsAvailable {
                await selectPlaybackSource(.compressed)
            } else {
                playerIsReady = false
            }
        } catch {
            errorMessage = "Original konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    public func deleteCompressed() async {
        guard compressedIsAvailable, let result = lastResult else { return }
        do {
            if originalIsAvailable {
                await selectPlaybackSource(.original)
            }
            if let savedID = result.savedAssetIdentifier {
                try await environment.library.deleteAsset(localIdentifier: savedID)
                environment.history.removeRecord(compressedAssetIdentifier: savedID)
            } else if FileManager.default.fileExists(atPath: result.outputURL.path) {
                try FileManager.default.removeItem(at: result.outputURL)
            }
            markCompressedUnavailable()
            compressedWasDeleted = true
            if !originalIsAvailable {
                playerIsReady = false
            }
        } catch {
            errorMessage = "Komprimierte Version konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func prepareCompressedPlayback(
        for result: ExportResult,
        preferSavedAsset: Bool = false
    ) async -> Bool {
        do {
            let playerItem: AVPlayerItem
            if preferSavedAsset, let savedID = result.savedAssetIdentifier {
                let asset = try await environment.library.loadAVAsset(for: savedID)
                playerItem = AVPlayerItem(asset: asset)
            } else if FileManager.default.fileExists(atPath: result.outputURL.path) {
                playerItem = AVPlayerItem(url: result.outputURL)
            } else if let savedID = result.savedAssetIdentifier {
                let asset = try await environment.library.loadAVAsset(for: savedID)
                playerItem = AVPlayerItem(asset: asset)
            } else {
                return false
            }
            compressedPlayerItem = playerItem
            compressedPlayer.replaceCurrentItem(with: playerItem)
            compressedPlayer.isMuted = currentPlaybackSource != .compressed
            compressedIsAvailable = true
            compressedPlaybackReady = true
            playerIsReady = true
            return true
        } catch {
            markCompressedUnavailable()
            Log.app.debug("Komprimiertes Playback fehlgeschlagen: \(String(describing: error))")
            return false
        }
    }

    private func player(for source: PlaybackSource) -> AVPlayer {
        switch source {
        case .original: return originalPlayer
        case .compressed: return compressedPlayer
        }
    }

    private func isPlaybackReady(for source: PlaybackSource) -> Bool {
        switch source {
        case .original:
            return originalIsAvailable && originalPlaybackReady && originalPlayerItem != nil
        case .compressed:
            return compressedIsAvailable && compressedPlaybackReady && compressedPlayerItem != nil
        }
    }

    private func syncMuteStates() {
        originalPlayer.isMuted = currentPlaybackSource != .original
        compressedPlayer.isMuted = currentPlaybackSource != .compressed
    }

    private func markOriginalUnavailable() {
        originalIsAvailable = false
        originalPlaybackReady = false
        originalPlayerItem = nil
        originalPlayer.pause()
        originalPlayer.replaceCurrentItem(with: nil)
        if currentPlaybackSource == .original, compressedPlaybackReady {
            currentPlaybackSource = .compressed
        }
        playerIsReady = compressedPlaybackReady
        syncMuteStates()
    }

    private func markCompressedUnavailable() {
        compressedIsAvailable = false
        compressedPlaybackReady = false
        compressedPlayerItem = nil
        compressedPlayer.pause()
        compressedPlayer.replaceCurrentItem(with: nil)
        if currentPlaybackSource == .compressed, originalPlaybackReady {
            currentPlaybackSource = .original
        }
        playerIsReady = originalPlaybackReady
        syncMuteStates()
    }

    private func seekPlayer(_ player: AVPlayer, to time: CMTime) async {
        await withCheckedContinuation { continuation in
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
    }
}

private extension AVPlayer {
    var currentSyncTime: CMTime {
        let seconds = currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else {
            return CMTime(seconds: 0, preferredTimescale: 600)
        }
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }
}
