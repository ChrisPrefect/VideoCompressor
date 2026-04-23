import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers
import AVFoundation

/// ViewModel für die Share-Extension-UI. Akzeptiert Video-Items aus dem
/// Share-Sheet, erlaubt Preset-Auswahl und führt den Export lokal aus.
@MainActor
@Observable
public final class ShareExtensionViewModel {

    public enum Stage: Hashable {
        case loadingInput
        case ready
        case exporting(progress: Double)
        case done(result: ExportResult, sourceURL: URL)
        case failed(message: String)
    }

    public private(set) var stage: Stage = .loadingInput
    public private(set) var inputURL: URL?
    public private(set) var inputThumbnail: UIImage?
    public private(set) var inputDuration: TimeInterval = 0
    public private(set) var inputSizeBytes: Int64 = 0

    public var selectedPreset: SharePreset
    public var keepAudio: Bool = true

    @ObservationIgnored private weak var extensionContext: NSExtensionContext?
    @ObservationIgnored private let inputItems: [NSExtensionItem]
    @ObservationIgnored private let presetStore = PresetStore()
    @ObservationIgnored private let transcoding = TranscodingService(
        library: PhotoLibraryService(),
        analyzer: VideoAnalysisService()
    )
    @ObservationIgnored private var cancellation = Cancellation()

    public var availablePresets: [SharePreset] {
        presetStore.allShare
    }

    public init(extensionContext: NSExtensionContext?, inputItems: [NSExtensionItem]) {
        self.extensionContext = extensionContext
        self.inputItems = inputItems
        self.selectedPreset = PresetStore().preferredSharePreset ?? .whatsapp
    }

    public func load() async {
        do {
            let url = try await Self.firstVideoURL(in: inputItems)
            self.inputURL = url
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            self.inputDuration = duration
            self.inputSizeBytes = TempFiles.fileSize(of: url) ?? 0
            self.inputThumbnail = await Self.makeThumbnail(asset)
            self.stage = .ready
        } catch {
            self.stage = .failed(message: error.localizedDescription)
        }
    }

    public func startExport() async {
        guard case .ready = stage, let inputURL else { return }
        cancellation = Cancellation()
        let job = ExportJob(
            source: .fileURL(inputURL),
            preset: .share(applyOverrides(to: selectedPreset))
        )

        do {
            self.stage = .exporting(progress: 0)
            let result = try await transcoding.run(
                job: job,
                cancellation: cancellation,
                onStatus: { status in
                    if case .exporting(let progress) = status {
                        Task { @MainActor [weak self] in
                            self?.stage = .exporting(progress: progress)
                        }
                    }
                }
            )
            self.stage = .done(result: result, sourceURL: result.outputURL)
        } catch let error as TranscodingServiceError {
            self.stage = .failed(message: Self.userMessage(for: error))
        } catch {
            self.stage = .failed(message: error.localizedDescription)
        }
    }

    public func cancel() {
        cancellation.cancel()
        extensionContext?.cancelRequest(withError: NSError(domain: "VideoShrinkShare", code: -1))
    }

    public func completeWithoutSharing() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Reicht das Ergebnis-File zurück an iOS, damit der Nutzer es weiter
    /// teilen oder speichern kann.
    public func finishAndShare(result: ExportResult) {
        let attachment = NSItemProvider(contentsOf: result.outputURL)
        let item = NSExtensionItem()
        if let attachment {
            item.attachments = [attachment]
        }
        extensionContext?.completeRequest(returningItems: [item])
    }

    private func applyOverrides(to base: SharePreset) -> SharePreset {
        SharePreset(
            id: base.id,
            name: base.name,
            kind: base.kind,
            maxFileSizeBytes: base.maxFileSizeBytes,
            maxLongEdge: base.maxLongEdge,
            maxFrameRate: base.maxFrameRate,
            keepAudio: keepAudio,
            audioBitsPerSecond: base.audioBitsPerSecond
        )
    }

    private static func userMessage(for error: TranscodingServiceError) -> String {
        switch error {
        case .originalAlreadySmallerThanTarget:
            return "Dieses Video ist bereits kleiner als die gewählte Zielgrösse. Wähle ein kleineres Teilen-Preset oder teile das Original direkt."
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Item-Provider Helpers

    private static func firstVideoURL(in items: [NSExtensionItem]) async throws -> URL {
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    return try await loadFileURL(provider, type: UTType.movie)
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.video.identifier) {
                    return try await loadFileURL(provider, type: UTType.video)
                }
            }
        }
        throw ShareExtensionError.noVideoFound
    }

    private static func loadFileURL(_ provider: NSItemProvider, type: UTType) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let url else {
                    cont.resume(throwing: ShareExtensionError.noVideoFound)
                    return
                }
                // `loadFileRepresentation` liefert eine temporäre Datei, die
                // nach Rückkehr aus dem Closure verschwindet. Wir kopieren
                // sie in unseren Container.
                let dest = TempFiles.makeURL(suffix: url.pathExtension.isEmpty ? "mov" : url.pathExtension, inSharedContainer: true)
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: dest)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func makeThumbnail(_ asset: AVURLAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        do {
            let cg = try await generator.image(at: .zero).image
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }
}

public enum ShareExtensionError: LocalizedError {
    case noVideoFound

    public var errorDescription: String? {
        switch self {
        case .noVideoFound: return "Im geteilten Inhalt wurde kein Video gefunden."
        }
    }
}
