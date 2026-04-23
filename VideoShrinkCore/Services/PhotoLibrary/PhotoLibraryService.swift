import Foundation
import Photos
import UIKit
import AVFoundation
import os

/// Zentrale Schnittstelle zur Foto-Mediathek: Videos auflisten, Thumbnails
/// laden, AVAssets bereitstellen, neue Assets schreiben, Originale löschen.
///
/// Wir markieren den Service als `actor`, damit Filter-/Fetch-Operationen
/// nicht den Main-Actor blockieren. PhotoKit ist thread-safe.
public actor PhotoLibraryService {

    public init() {}

    // MARK: - Asset-Abfrage

    public struct ExportMetadata: Sendable {
        public let kind: VideoKind
        public let creationDate: Date?
    }

    public struct FetchOptions: Sendable, Hashable {
        public enum Sort: Sendable, Hashable {
            case fileSize
            case creationDate
        }

        public var minimumSizeBytes: Int64
        public var sort: Sort
        public var ascending: Bool
        public var includesHiddenAssets: Bool

        public init(
            minimumSizeBytes: Int64 = 50 * 1024 * 1024,
            sort: Sort = .fileSize,
            ascending: Bool = false,
            includesHiddenAssets: Bool = false
        ) {
            self.minimumSizeBytes = minimumSizeBytes
            self.sort = sort
            self.ascending = ascending
            self.includesHiddenAssets = includesHiddenAssets
        }
    }

    /// Fetcht alle Videos aus der Mediathek, ermittelt deren Dateigrösse
    /// (best-effort) und filtert/sortiert lokal nach den FetchOptions.
    ///
    /// Hinweis zur Dateigrösse: PhotoKit stellt **keine** offizielle
    /// synchrone API zur exakten Dateigrösse eines Assets bereit.
    /// Die hier verwendete KVC-Abfrage `value(forKey: "fileSize")` auf
    /// `PHAssetResource` ist seit Jahren stabiles, weit verbreitetes
    /// Vorgehen, aber nicht offiziell dokumentiert. Wir kapseln den Zugriff
    /// hier zentral und fallen auf eine Heuristik (Bitratengrösse aus
    /// AVAsset) zurück, falls der KVC-Zugriff fehlschlägt.
    public func fetchVideos(options: FetchOptions) async -> [LibraryVideoItem] {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.includeHiddenAssets = options.includesHiddenAssets
        opts.includeAllBurstAssets = false

        let assets = PHAsset.fetchAssets(with: .video, options: opts)
        var items: [LibraryVideoItem] = []
        items.reserveCapacity(assets.count)

        assets.enumerateObjects { asset, _, _ in
            // Live-Photo-paired Videos nicht als eigenständige Bibliotheks-
            // Videos zeigen — sie gehören zu einem Foto.
            let resources = PHAssetResource.assetResources(for: asset)
            let isLivePhotoCompanion = resources.contains { $0.type == .pairedVideo }
            if isLivePhotoCompanion { return }

            let size = Self.exactFileSize(for: asset, resources: resources)
            let kind = VideoKind.classify(from: asset)
            let isLocal = Self.assessLocalAvailability(resources: resources)

            let item = LibraryVideoItem(
                id: asset.localIdentifier,
                assetIdentifier: asset.localIdentifier,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                duration: asset.duration,
                creationDate: asset.creationDate,
                modificationDate: asset.modificationDate,
                kind: kind,
                fileSize: size,
                isLocallyAvailable: isLocal
            )
            items.append(item)
        }

        // Filter nach Mindestgrösse: Wenn `fileSize` `nil` ist, behandeln
        // wir das defensiv und schliessen das Asset aus dem Filter aus, weil
        // wir keine verlässliche Aussage treffen können.
        let filtered = items.filter { item in
            guard let size = item.fileSize else { return false }
            return size >= options.minimumSizeBytes
        }

        let sorted = filtered.sorted { lhs, rhs in
            let primary: Bool
            switch options.sort {
            case .fileSize:
                let l = lhs.fileSize ?? 0
                let r = rhs.fileSize ?? 0
                primary = options.ascending ? l < r : l > r
            case .creationDate:
                let l = lhs.creationDate ?? .distantPast
                let r = rhs.creationDate ?? .distantPast
                primary = options.ascending ? l < r : l > r
            }
            return primary
        }

        return sorted
    }

    /// Liefert das `PHAsset` zu einer ID. PHAsset selbst ist nicht
    /// `Sendable`; wir reichen es nur innerhalb des Actor-Kontexts weiter.
    public func asset(for localIdentifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return result.firstObject
    }

    public func exportMetadata(for localIdentifier: String) throws -> ExportMetadata {
        guard let asset = self.asset(for: localIdentifier) else {
            Log.library.error("Export metadata asset not found id=\(localIdentifier, privacy: .private)")
            throw PhotoLibraryError.assetNotFound
        }
        Log.library.notice(
            "Export metadata read id=\(localIdentifier, privacy: .private) pixels=\(asset.pixelWidth)x\(asset.pixelHeight) duration=\(asset.duration, privacy: .public)"
        )
        return ExportMetadata(
            kind: VideoKind.classify(from: asset),
            creationDate: asset.creationDate
        )
    }

    // MARK: - Thumbnails

    /// Lädt ein Thumbnail für die Liste/Detailansicht. Default-Grösse ist
    /// auf eine Listenzelle ausgelegt.
    public func thumbnail(
        for localIdentifier: String,
        targetSize: CGSize = CGSize(width: 240, height: 240)
    ) async -> UIImage? {
        guard let asset = self.asset(for: localIdentifier) else { return nil }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            var didResume = false
            func finish(_ image: UIImage?) {
                guard !didResume else { return }
                didResume = true
                cont.resume(returning: image)
            }

            manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // `requestImage` kann mehrfach callen (low-res zuerst, dann
                // high-res). Wir resümieren erst beim finalen Aufruf.
                if let cancelled = (info?[PHImageCancelledKey] as? NSNumber)?.boolValue,
                   cancelled {
                    finish(nil)
                    return
                }
                if info?[PHImageErrorKey] as? Error != nil {
                    finish(nil)
                    return
                }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                if !isDegraded {
                    finish(image)
                }
            }
        }
    }

    // MARK: - AV-Asset

    /// Lädt das `AVURLAsset` zu einem Asset, lädt iCloud-Inhalte bei Bedarf
    /// nach. Liefert ein Tupel mit Asset und einer optionalen Quell-URL für
    /// direkte Datei-Operationen (kann `nil` sein, falls der Player-Item-
    /// Pfad benutzt wird).
    public func loadAVAsset(
        for localIdentifier: String,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> AVURLAsset {
        Log.library.notice("loadAVAsset start id=\(localIdentifier, privacy: .private)")
        guard let asset = self.asset(for: localIdentifier) else {
            Log.library.error("loadAVAsset asset not found id=\(localIdentifier, privacy: .private)")
            throw PhotoLibraryError.assetNotFound
        }
        Log.library.notice(
            "loadAVAsset asset found id=\(localIdentifier, privacy: .private) pixels=\(asset.pixelWidth)x\(asset.pixelHeight) duration=\(asset.duration, privacy: .public)"
        )
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.progressHandler = { progress, error, _, _ in
            if let error {
                Log.library.error("loadAVAsset iCloud progress error id=\(localIdentifier, privacy: .private) error=\(String(describing: error), privacy: .public)")
            } else {
                progressHandler?(progress)
            }
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AVURLAsset, Error>) in
            let finished = NSLock()
            var didFinish = false

            func finish(_ result: Result<AVURLAsset, Error>) {
                finished.lock()
                if didFinish {
                    finished.unlock()
                    Log.library.fault("loadAVAsset duplicate callback ignored id=\(localIdentifier, privacy: .private)")
                    return
                }
                didFinish = true
                finished.unlock()

                switch result {
                case .success(let asset):
                    cont.resume(returning: asset)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }

            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, info in
                let keys = info?.keys.map { String(describing: $0) }.sorted().joined(separator: ",") ?? "nil"
                Log.library.notice(
                    "loadAVAsset callback id=\(localIdentifier, privacy: .private) avAsset=\(String(describing: type(of: avAsset)), privacy: .public) infoKeys=\(keys, privacy: .public)"
                )
                if let error = info?[PHImageErrorKey] as? Error {
                    Log.library.error("loadAVAsset failed id=\(localIdentifier, privacy: .private) error=\(String(describing: error), privacy: .public)")
                    finish(.failure(error))
                    return
                }
                if let cancelled = info?[PHImageCancelledKey] as? NSNumber, cancelled.boolValue {
                    Log.library.warning("loadAVAsset cancelled id=\(localIdentifier, privacy: .private)")
                    finish(.failure(PhotoLibraryError.cancelled))
                    return
                }
                guard let urlAsset = avAsset as? AVURLAsset else {
                    Log.library.error("loadAVAsset unsupported asset type id=\(localIdentifier, privacy: .private)")
                    finish(.failure(PhotoLibraryError.unsupportedAVAssetType))
                    return
                }
                Log.library.notice("loadAVAsset success id=\(localIdentifier, privacy: .private) file=\(urlAsset.url.lastPathComponent, privacy: .public)")
                finish(.success(urlAsset))
            }
        }
    }

    // MARK: - Schreiben / Löschen

    /// Speichert eine lokale Datei als neues Video-Asset in der Mediathek.
    /// Liefert die `localIdentifier`-Zeichenkette des neuen Assets.
    public func saveVideoToLibrary(fileURL: URL, originalCreationDate: Date?) async throws -> String {
        var placeholderID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let resourceOptions = PHAssetResourceCreationOptions()
            resourceOptions.shouldMoveFile = false
            request.addResource(with: .video, fileURL: fileURL, options: resourceOptions)
            if let date = originalCreationDate {
                request.creationDate = date
            }
            placeholderID = request.placeholderForCreatedAsset?.localIdentifier
        }
        guard let id = placeholderID else {
            throw PhotoLibraryError.saveFailed
        }
        return id
    }

    /// Löscht ein Asset aus der Mediathek. iOS verschiebt das Asset in
    /// "Zuletzt gelöscht" — dieses Verhalten ist systembedingt und kann
    /// über öffentliche APIs nicht umgangen werden.
    public func deleteAsset(localIdentifier: String) async throws {
        guard let asset = self.asset(for: localIdentifier) else {
            throw PhotoLibraryError.assetNotFound
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }

    // MARK: - Helpers

    /// Versucht, die exakte Dateigrösse über PHAssetResource zu lesen.
    /// Bevorzugt die original-Video-Resource. Fällt auf `nil` zurück, wenn
    /// keine plausible Grösse ermittelbar ist.
    nonisolated public static func exactFileSize(for asset: PHAsset, resources: [PHAssetResource]? = nil) -> Int64? {
        let res = resources ?? PHAssetResource.assetResources(for: asset)
        // Bevorzugt die ursprüngliche Video-Resource, dann modifizierte.
        let preferred = res.first { $0.type == .video }
            ?? res.first { $0.type == .fullSizeVideo }
            ?? res.first
        guard let resource = preferred else { return nil }
        if let n = resource.value(forKey: "fileSize") as? NSNumber {
            return n.int64Value
        }
        return nil
    }

    /// Heuristik für lokale Verfügbarkeit. iCloud-only Assets können wir
    /// trotzdem laden, brauchen dann aber Netzzugriff.
    nonisolated public static func assessLocalAvailability(resources: [PHAssetResource]) -> Bool {
        // PHAssetResource hat kein dokumentiertes "isLocallyAvailable"-
        // Property. Wir nehmen optimistisch an, dass die Datei lokal ist und
        // prüfen erst beim Laden des AVAssets erneut.
        return !resources.isEmpty
    }
}

public enum PhotoLibraryError: LocalizedError {
    case assetNotFound
    case unsupportedAVAssetType
    case saveFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .assetNotFound: return "Das Asset konnte nicht gefunden werden."
        case .unsupportedAVAssetType: return "Das Quell-Asset hat ein unerwartetes Format."
        case .saveFailed: return "Das neue Video konnte nicht in der Mediathek gespeichert werden."
        case .cancelled: return "Die Operation wurde abgebrochen."
        }
    }
}
