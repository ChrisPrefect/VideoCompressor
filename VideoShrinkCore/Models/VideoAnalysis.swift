import Foundation
import AVFoundation

/// Ergebnis der technischen Analyse eines Videos vor dem Export. Enthält die
/// echten Werte aus AVAsset und liefert eine Grundlage für Bitratenbudgets.
nonisolated public struct VideoAnalysis: Sendable, Hashable {
    public var fileSizeBytes: Int64
    public var duration: TimeInterval
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var nominalFrameRate: Double
    public var hasAudio: Bool
    public var audioChannelCount: Int
    public var preferredTransform: CGAffineTransform
    public var sourceCodec: SourceCodec
    public var bitsPerSecond: Int
    /// True, wenn der Video-Track HDR-Charakteristik trägt (HDR10, HLG,
    /// Dolby Vision …).
    public var isHDR: Bool

    public enum SourceCodec: String, Sendable, Hashable {
        case h264, hevc, proRes, other, unknown

        nonisolated public static func from(formatDescriptions: [CMFormatDescription]) -> SourceCodec {
            guard let first = formatDescriptions.first else { return .unknown }
            let mediaSubType = CMFormatDescriptionGetMediaSubType(first)
            switch mediaSubType {
            case kCMVideoCodecType_H264: return .h264
            case kCMVideoCodecType_HEVC: return .hevc
            default:
                // ProRes hat mehrere Subtypen (apch, apcn …) — wir prüfen den
                // FourCC-Anfang.
                let fourCC = String(
                    [
                        UInt8((mediaSubType >> 24) & 0xFF),
                        UInt8((mediaSubType >> 16) & 0xFF),
                        UInt8((mediaSubType >> 8) & 0xFF),
                        UInt8(mediaSubType & 0xFF)
                    ].compactMap { Character(UnicodeScalar($0)) }.map { String($0) }.joined()
                )
                if fourCC.lowercased().hasPrefix("ap") { return .proRes }
                return .other
            }
        }
    }

    /// Längste Kante in Pixel — für Auflösungs-Limits.
    public var longEdge: Int {
        max(pixelWidth, pixelHeight)
    }

    /// Geschätzte Originalgrösse in Bytes basierend auf Bitrate × Dauer
    /// (ohne Container-Overhead). Wird genutzt, wenn `fileSizeBytes` 0 ist.
    public var estimatedFileSize: Int64 {
        guard bitsPerSecond > 0, duration.isFinite, duration > 0 else { return 0 }
        let approx = Double(bitsPerSecond) * duration / 8.0
        return Int64(approx)
    }
}
