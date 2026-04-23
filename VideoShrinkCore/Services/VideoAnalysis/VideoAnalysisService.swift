import Foundation
import AVFoundation

/// Analysiert ein AVAsset und liefert die Werte, die der Export-Engine als
/// Eingang dienen.
public actor VideoAnalysisService {

    public init() {}

    public func analyze(_ asset: AVURLAsset) async throws -> VideoAnalysis {
        // Wir laden nötige Properties asynchron, damit ältere
        // Block-basierte AVFoundation-APIs nicht den Caller blockieren.
        let (duration, tracksRaw) = try await asset.load(.duration, .tracks)
        let videoTracks = tracksRaw.filter { $0.mediaType == .video }
        let audioTracks = tracksRaw.filter { $0.mediaType == .audio }

        guard let videoTrack = videoTracks.first else {
            throw VideoAnalysisError.noVideoTrack
        }

        let (
            naturalSize,
            transform,
            nominalFrameRate,
            estimatedDataRate,
            formatDescriptionsRaw
        ) = try await videoTrack.load(
            .naturalSize,
            .preferredTransform,
            .nominalFrameRate,
            .estimatedDataRate,
            .formatDescriptions
        )

        let audioChannelCount: Int
        if let audio = audioTracks.first {
            // Channel-Count konservativ schätzen — falls Format-Description
            // keinen klaren Wert liefert, gehen wir von Stereo aus.
            let formats = try await audio.load(.formatDescriptions)
            if let first = formats.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(first)?.pointee {
                audioChannelCount = Int(asbd.mChannelsPerFrame)
            } else {
                audioChannelCount = 2
            }
        } else {
            audioChannelCount = 0
        }

        // Effektive Pixelgrösse (preferredTransform berücksichtigt
        // Hochkant-/Querformat).
        let transformed = naturalSize.applying(transform)
        let pixelWidth = abs(Int(transformed.width.rounded()))
        let pixelHeight = abs(Int(transformed.height.rounded()))
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw VideoAnalysisError.invalidDuration
        }
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw VideoAnalysisError.invalidDimensions
        }

        let fileSizeFromURL = TempFiles.fileSize(of: asset.url) ?? 0
        let bitsPerSecond = Int(estimatedDataRate.rounded())
        // HDR-Charakteristik via async-Property; deckt HDR10/HLG/Dolby
        // Vision ab.
        let mediaCharacteristics = (try? await videoTrack.load(.mediaCharacteristics)) ?? []
        let isHDR = mediaCharacteristics.contains(.containsHDRVideo)

        return VideoAnalysis(
            fileSizeBytes: fileSizeFromURL,
            duration: durationSeconds,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            nominalFrameRate: Double(nominalFrameRate),
            hasAudio: !audioTracks.isEmpty,
            audioChannelCount: audioChannelCount,
            preferredTransform: transform,
            sourceCodec: VideoAnalysis.SourceCodec.from(formatDescriptions: formatDescriptionsRaw),
            bitsPerSecond: bitsPerSecond,
            isHDR: isHDR
        )
    }
}

public enum VideoAnalysisError: LocalizedError {
    case noVideoTrack
    case invalidDuration
    case invalidDimensions
    case loadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "Die Datei enthält keine Video-Spur."
        case .invalidDuration: return "Die Videodauer konnte nicht zuverlässig gelesen werden."
        case .invalidDimensions: return "Die Videoauflösung konnte nicht zuverlässig gelesen werden."
        case .loadFailed(let m): return "Asset-Analyse fehlgeschlagen: \(m)"
        }
    }
}
