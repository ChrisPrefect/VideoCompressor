import Foundation
import AVFoundation
import CoreGraphics

/// Konkrete, vollständig aufgelöste Konfiguration eines Exports. Wird aus
/// `ExportJob` + `VideoAnalysis` errechnet und ist die alleinige Quelle der
/// Wahrheit für die Engine.
nonisolated public struct ExportPlan: Sendable {
    public var outputURL: URL
    /// Sichtbare Zielgrösse nach Anwendung des Track-Transforms.
    public var renderSize: CGSize
    /// Tatsächliche Pixelgrösse, die der Writer kodiert.
    public var encodedSize: CGSize
    /// Track-Transform für die skalierte Ausgabedatei.
    public var outputTransform: CGAffineTransform
    public var frameRate: Double
    public var videoBitsPerSecond: Int
    public var keepAudio: Bool
    public var audioBitsPerSecond: Int
    public var fileType: AVFileType
    public var warnings: WarningFlags
    public var skipExportBecauseOriginalSmaller: Bool

    public var renderWidth: Int { abs(Int(renderSize.width.rounded())) }
    public var renderHeight: Int { abs(Int(renderSize.height.rounded())) }
    public var encodedWidth: Int { abs(Int(encodedSize.width.rounded())) }
    public var encodedHeight: Int { abs(Int(encodedSize.height.rounded())) }
}

nonisolated public struct ExportPreview: Sendable, Hashable {
    public let resultSizeBytes: Int64
    public let originalSizeBytes: Int64
    public let savedBytes: Int64
    public let savedFraction: Double
    public let renderSize: CGSize
    public let frameRate: Double
    public let keepAudio: Bool
    public let warnings: WarningFlags
    public let skipExportBecauseOriginalSmaller: Bool
}

/// Berechnet einen `ExportPlan` aus Quell-Analyse, Preset und Geräte-
/// Fähigkeiten. Die Logik hält drei Versprechen konsequent ein:
///
/// 1. Niemals hochskalieren (weder Auflösung noch fps).
/// 2. Niemals stillschweigend grösser ausgeben als das Original.
nonisolated public struct ExportPlanner: Sendable {

    public init() {}

    /// Hauptfunktion: erzeugt einen Plan für einen `ExportJob`.
    public func plan(
        for job: ExportJob,
        analysis: VideoAnalysis,
        sourceKind: VideoKind,
        outputURL: URL
    ) -> ExportPlan {
        var warnings: WarningFlags = []

        // --- Auflösung -------------------------------------------------
        let sourceLong = max(analysis.pixelWidth, analysis.pixelHeight)
        let sourceShort = min(analysis.pixelWidth, analysis.pixelHeight)
        let isPortrait = analysis.pixelHeight > analysis.pixelWidth

        let presetMaxLong: Int
        let presetMaxFPS: Double
        let keepAudio: Bool
        let audioBPS: Int

        switch job.preset {
        case .compression(let p):
            // Maximal 50 % Originalauflösung, falls erzwungen.
            let halfCap = p.enforceHalfResolution ? sourceLong / 2 : sourceLong
            presetMaxLong = min(p.maxLongEdge, max(halfCap, 240))
            presetMaxFPS = p.maxFrameRate
            keepAudio = p.keepAudio
            audioBPS = p.audioBitsPerSecond
        case .share(let p):
            presetMaxLong = p.maxLongEdge
            presetMaxFPS = p.maxFrameRate
            keepAudio = p.keepAudio
            audioBPS = p.audioBitsPerSecond
        }

        // Niemals hochskalieren: kleinerer Wert von Quelle und Preset-Grenze.
        let targetLong = min(sourceLong, max(presetMaxLong, 1))
        if presetMaxLong > sourceLong {
            warnings.insert(.presetUpscalesResolution)
        }

        // Seitenverhältnis erhalten, ungerade Werte vermeiden.
        let ratio = sourceLong > 0 ? Double(sourceShort) / Double(sourceLong) : 1
        let targetShort = max(2, Int((Double(targetLong) * ratio).rounded()))
        let evenLong = max(2, targetLong - (targetLong % 2))
        let evenShort = max(2, targetShort - (targetShort % 2))
        let renderSize: CGSize
        if isPortrait {
            renderSize = CGSize(width: evenShort, height: evenLong)
        } else {
            renderSize = CGSize(width: evenLong, height: evenShort)
        }

        // --- fps -------------------------------------------------------
        let sourceFPS = analysis.nominalFrameRate.isFinite && analysis.nominalFrameRate > 0
            ? analysis.nominalFrameRate
            : 30
        let maxFPS = presetMaxFPS.isFinite && presetMaxFPS > 0 ? presetMaxFPS : sourceFPS
        let targetFPS = max(1, min(sourceFPS, maxFPS))

        // --- Bitrate ---------------------------------------------------
        var videoBPS: Int
        switch job.preset {
        case .compression(let p):
            // Nicht über Originalbitrate gehen.
            let sourceBPS = analysis.bitsPerSecond > 0 ? analysis.bitsPerSecond : p.maxVideoBitsPerSecond
            videoBPS = min(p.maxVideoBitsPerSecond, sourceBPS)
            // Auflösungs- und fps-Skalierung berücksichtigen.
            let pixelScale = max(0.05, Double(renderSize.width * renderSize.height) /
                Double(max(1, analysis.pixelWidth * analysis.pixelHeight)))
            let fpsScale = sourceFPS > 0 ? min(1.0, targetFPS / sourceFPS) : 1.0
            videoBPS = min(videoBPS, max(150_000, Int(Double(sourceBPS) * pixelScale * fpsScale)))
        case .share(let p):
            videoBPS = computeShareBitrate(
                targetBytes: p.maxFileSizeBytes,
                durationSeconds: analysis.duration,
                keepAudio: p.keepAudio,
                audioBPS: p.audioBitsPerSecond
            )
            if videoBPS < 200_000 {
                warnings.insert(.targetSizeNotReachable)
                videoBPS = max(videoBPS, 200_000)
            }
        }

        // --- Skip-Logik: Original schon kleiner als Ziel? --------------
        var skip = false
        if analysis.fileSizeBytes > 0,
           case .share(let p) = job.preset,
           analysis.fileSizeBytes <= p.maxFileSizeBytes {
            warnings.insert(.originalSmallerThanTarget)
            skip = true
        }

        // Compression-Pfad: erwartete Ausgabe grösser als Original?
        if case .compression = job.preset, analysis.fileSizeBytes > 0 {
            let mediaBytes = Int64(Double(videoBPS + (keepAudio ? audioBPS : 0)) * analysis.duration / 8.0)
            let estimated = mediaBytes + containerOverhead(for: mediaBytes)
            if estimated >= analysis.fileSizeBytes {
                warnings.insert(.originalSmallerThanTarget)
                skip = true
            }
        }

        if !keepAudio, analysis.hasAudio {
            warnings.insert(.audioWillBeRemoved)
        }

        // HDR → SDR: Standard-Pipeline schreibt ohne explizite HDR-Settings,
        // d. h. ein HDR-Quellvideo wird in der Praxis als SDR ausgegeben.
        if analysis.isHDR {
            warnings.insert(.hdrConvertedToSDR)
        }

        let encodedSize = encodedRenderSize(
            displaySize: renderSize,
            sourceTransform: analysis.preferredTransform
        )
        let scaleX = renderSize.width / CGFloat(max(analysis.pixelWidth, 1))
        let scaleY = renderSize.height / CGFloat(max(analysis.pixelHeight, 1))
        let transformScale = min(scaleX, scaleY)
        let outputTransform = scaledTranslation(
            of: analysis.preferredTransform,
            by: transformScale
        )

        return ExportPlan(
            outputURL: outputURL,
            renderSize: renderSize,
            encodedSize: encodedSize,
            outputTransform: outputTransform,
            frameRate: targetFPS,
            videoBitsPerSecond: videoBPS,
            keepAudio: keepAudio && analysis.hasAudio,
            audioBitsPerSecond: audioBPS,
            fileType: .mp4,
            warnings: warnings.union(specialKindWarnings(for: sourceKind)),
            skipExportBecauseOriginalSmaller: skip
        )
    }

    public func preview(
        for job: ExportJob,
        analysis: VideoAnalysis,
        sourceKind: VideoKind
    ) -> ExportPreview {
        let plan = plan(
            for: job,
            analysis: analysis,
            sourceKind: sourceKind,
            outputURL: URL(fileURLWithPath: "/dev/null")
        )
        let originalBytes = max(analysis.fileSizeBytes, analysis.estimatedFileSize)
        let mediaBytes = Int64(Double(plan.videoBitsPerSecond + (plan.keepAudio ? plan.audioBitsPerSecond : 0)) * analysis.duration / 8.0)
        let containerOverhead = containerOverhead(for: mediaBytes)
        let estimatedResultBytes = plan.skipExportBecauseOriginalSmaller
            ? originalBytes
            : max(1, mediaBytes + containerOverhead)
        let savedBytes = max(0, originalBytes - estimatedResultBytes)
        let savedFraction = originalBytes > 0 ? Double(savedBytes) / Double(originalBytes) : 0

        return ExportPreview(
            resultSizeBytes: estimatedResultBytes,
            originalSizeBytes: originalBytes,
            savedBytes: savedBytes,
            savedFraction: savedFraction,
            renderSize: plan.renderSize,
            frameRate: plan.frameRate,
            keepAudio: plan.keepAudio,
            warnings: plan.warnings,
            skipExportBecauseOriginalSmaller: plan.skipExportBecauseOriginalSmaller
        )
    }

    public func approximateSavedBytes(
        for item: LibraryVideoItem,
        preset: CompressionPreset
    ) -> Int64 {
        guard let originalBytes = item.fileSize,
              item.duration > 0,
              item.pixelWidth > 0,
              item.pixelHeight > 0 else {
            return 0
        }

        let sourceLong = max(item.pixelWidth, item.pixelHeight)
        let sourceShort = min(item.pixelWidth, item.pixelHeight)
        let halfCap = preset.enforceHalfResolution ? sourceLong / 2 : sourceLong
        let presetLong = min(preset.maxLongEdge, max(halfCap, 240))
        let targetLong = min(sourceLong, max(presetLong, 1))
        let ratio = Double(sourceShort) / Double(max(sourceLong, 1))
        let targetShort = max(2, Int((Double(targetLong) * ratio).rounded()))
        let evenLong = max(2, targetLong - (targetLong % 2))
        let evenShort = max(2, targetShort - (targetShort % 2))
        let pixelScale = max(
            0.05,
            Double(evenLong * evenShort) / Double(max(1, item.pixelWidth * item.pixelHeight))
        )
        let videoBitsPerSecond = max(150_000, Int(Double(preset.maxVideoBitsPerSecond) * pixelScale))
        let audioBitsPerSecond = preset.keepAudio ? preset.audioBitsPerSecond : 0
        let mediaBytes = Int64(Double(videoBitsPerSecond + audioBitsPerSecond) * item.duration / 8.0)
        let containerOverhead = containerOverhead(for: mediaBytes)
        let estimatedResultBytes = max(1, mediaBytes + containerOverhead)

        return max(0, originalBytes - min(originalBytes, estimatedResultBytes))
    }

    /// Bitratenberechnung für Share-Presets:
    /// `targetBytes - audioBudget - containerOverhead → videoBPS`.
    /// Container-Overhead: konservativ 3 % der Zielgrösse, aber min 64 kB.
    public func computeShareBitrate(
        targetBytes: Int64,
        durationSeconds: TimeInterval,
        keepAudio: Bool,
        audioBPS: Int
    ) -> Int {
        guard durationSeconds > 0 else { return 1_500_000 }
        let containerOverhead = max(64_000, Int64(Double(targetBytes) * 0.03))
        let audioBudget: Int64 = keepAudio ? Int64(Double(audioBPS) / 8.0 * durationSeconds) : 0
        let videoBudgetBytes = targetBytes - containerOverhead - audioBudget
        let videoBudgetBits = Double(videoBudgetBytes) * 8.0
        let bps = videoBudgetBits / durationSeconds
        return max(0, Int(bps))
    }

    private func containerOverhead(for mediaBytes: Int64) -> Int64 {
        max(64_000, Int64(Double(max(mediaBytes, 1)) * 0.03))
    }

    private func encodedRenderSize(
        displaySize: CGSize,
        sourceTransform: CGAffineTransform
    ) -> CGSize {
        let swapsAxes = abs(sourceTransform.b) > abs(sourceTransform.a)
            && abs(sourceTransform.c) > abs(sourceTransform.d)
        if swapsAxes {
            return CGSize(width: displaySize.height, height: displaySize.width)
        }
        return displaySize
    }

    private func scaledTranslation(
        of transform: CGAffineTransform,
        by scale: CGFloat
    ) -> CGAffineTransform {
        CGAffineTransform(
            a: transform.a,
            b: transform.b,
            c: transform.c,
            d: transform.d,
            tx: transform.tx * scale,
            ty: transform.ty * scale
        )
    }

    private func specialKindWarnings(for kind: VideoKind) -> WarningFlags {
        switch kind {
        case .spatial: return [.losesSpatialData]
        case .cinematic: return [.losesDepthData]
        case .slowMotion: return [.losesSlowMotionRamp]
        case .timeLapse: return [.mayProduceArtifacts]
        case .standard, .screenRecording: return []
        }
    }
}
