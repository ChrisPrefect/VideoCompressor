import Foundation
import Observation
import SwiftUI
import os

@MainActor
@Observable
public final class BatchViewModel {

    public struct ItemState: Identifiable, Hashable {
        public let id: String
        public var item: LibraryVideoItem
        public var status: ExportJobStatus
        public var resultBytes: Int64?
    }

    public enum PendingConfirmation: Equatable {
        case none
        case specialFormat(count: Int)
        case willDeleteOriginals(count: Int)
        case askPostExportDelete(savedIDs: [String])
    }

    public private(set) var states: [ItemState]
    public var presetChoice: VideoDetailViewModel.PresetChoice
    public var deleteOriginalAfterSuccess: Bool
    public private(set) var isRunning: Bool = false
    public private(set) var totalSavedBytes: Int64 = 0
    public var pending: PendingConfirmation = .none
    public var errorMessage: String?

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var cancellation = Cancellation()
    @ObservationIgnored private let planner = ExportPlanner()

    public init(items: [LibraryVideoItem], initialPreset: CompressionPreset, environment: AppEnvironment) {
        self.environment = environment
        self.states = items.map { ItemState(id: $0.id, item: $0, status: .pending, resultBytes: nil) }
        self.presetChoice = .compression(initialPreset)
        switch environment.settings.settings.defaultDeleteBehavior {
        case .deleteOriginals: self.deleteOriginalAfterSuccess = true
        default: self.deleteOriginalAfterSuccess = false
        }
    }

    public func cancel() {
        cancellation.cancel()
    }

    public func cancelPending() {
        pending = .none
    }

    public var specialFormatCount: Int {
        states.filter { $0.item.kind.requiresConfirmation }.count
    }

    public var willAskBeforeSpecialFormatExport: Bool {
        specialFormatCount > 0 && environment.settings.shouldShowSpecialFormatWarning
    }

    public var totalOriginalBytes: Int64 {
        states.reduce(0) { $0 + ($1.item.fileSize ?? 0) }
    }

    /// Vom Screen aufgerufen, wenn der User auf "Starten" tippt. Routing
    /// durch ggf. nötige Confirms (Spezialformate → Löschen → Run).
    public func requestStart() {
        let special = specialFormatCount
        if special > 0, environment.settings.shouldShowSpecialFormatWarning {
            environment.settings.markSpecialFormatWarningShown()
            pending = .specialFormat(count: special)
            return
        }
        if deleteOriginalAfterSuccess {
            pending = .willDeleteOriginals(count: states.count)
            return
        }
        Task { await run() }
    }

    public func confirmSpecialFormat() {
        pending = .none
        if deleteOriginalAfterSuccess {
            pending = .willDeleteOriginals(count: states.count)
        } else {
            Task { await run() }
        }
    }

    public func confirmDeleteAndRun() {
        pending = .none
        Task { await run() }
    }

    public func confirmPostExportDelete() async {
        guard case .askPostExportDelete(let ids) = pending else {
            pending = .none
            return
        }
        let library = environment.library
        // Ein einzelner performChanges-Block für alle Löschungen wäre noch
        // schöner; PhotoLibraryService.deleteAsset arbeitet aber per-asset.
        // Pragma: für Batch-Sicherheit reicht es; bei Fehlern brechen wir
        // nicht ab, sondern zählen Fehlschläge.
        var failures = 0
        for id in ids {
            do {
                try await library.deleteAsset(localIdentifier: id)
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            errorMessage = "\(failures) Original(e) konnten nicht gelöscht werden."
        }
        pending = .none
    }

    public func declinePostExportDelete() {
        pending = .none
    }

    private func run() async {
        guard !isRunning else { return }
        cancellation = Cancellation()
        isRunning = true
        Log.app.notice("Batch export started count=\(self.states.count, privacy: .public) preset=\(self.presetChoice.displayName, privacy: .public) deleteOriginal=\(self.deleteOriginalAfterSuccess, privacy: .public)")
        defer { isRunning = false }

        // IDs der Originale, die nach Erfolg gelöscht werden sollen — erst
        // sammeln, ggf. nach Schleife im askEachTime-Modus per Sheet
        // anbieten.
        var successfulOriginalIDs: [String] = []

        for index in states.indices {
            if cancellation.isCancelled {
                states[index].status = .cancelled
                continue
            }
            states[index].status = .preparing
            let originalID = states[index].item.id
            Log.app.notice("Batch export item started index=\(index, privacy: .public) id=\(originalID, privacy: .private)")
            let job = ExportJob(
                source: .photoLibrary(localIdentifier: originalID),
                preset: presetChoice.asJobPreset,
                postExportAction: deleteOriginalAfterSuccess ? .deleteOriginalAfterSuccess : .keepOriginal
            )
            do {
                let result = try await environment.transcoding.run(
                    job: job,
                    cancellation: cancellation,
                    onStatus: { status in
                        Task { @MainActor [weak self] in
                            self?.states[index].status = status
                            if case .finished(let r) = status {
                                self?.states[index].resultBytes = r.resultSizeBytes
                            }
                        }
                    }
                )
                environment.statistics.record(result)
                totalSavedBytes += result.savedBytes
                if result.savedAssetIdentifier != nil {
                    successfulOriginalIDs.append(originalID)
                }
            } catch let error as TranscodingServiceError {
                Log.app.error("Batch export item failed typed index=\(index, privacy: .public) id=\(originalID, privacy: .private) error=\(String(describing: error), privacy: .public)")
                states[index].status = .failed(error.localizedDescription)
            } catch {
                Log.app.error("Batch export item failed index=\(index, privacy: .public) id=\(originalID, privacy: .private) error=\(String(describing: error), privacy: .public)")
                states[index].status = .failed(error.localizedDescription)
            }
        }

        // Nach Abschluss: askEachTime-Modus → Sheet "Originale jetzt
        // löschen?" anbieten, wenn Toggle off war und Defaults so gesetzt
        // sind.
        if !deleteOriginalAfterSuccess,
           environment.settings.settings.defaultDeleteBehavior == .askEachTime,
           !successfulOriginalIDs.isEmpty {
            pending = .askPostExportDelete(savedIDs: successfulOriginalIDs)
        }
    }

    public var completedCount: Int {
        states.filter { if case .finished = $0.status { return true } else { return false } }.count
    }

    public var failedCount: Int {
        states.filter { if case .failed = $0.status { return true } else { return false } }.count
    }

    public func estimatedSavings(for preset: CompressionPreset) -> Int64 {
        states.reduce(0) { partial, state in
            partial + planner.approximateSavedBytes(for: state.item, preset: preset)
        }
    }
}
