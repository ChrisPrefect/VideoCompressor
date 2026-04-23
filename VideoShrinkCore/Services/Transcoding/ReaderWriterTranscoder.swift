import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
import os

/// Transcoder auf Basis von AVAssetReader/AVAssetWriter. Bietet feine
/// Kontrolle über Auflösung, fps, Bitrate und Audio. Wird als
/// primärer Pfad für die App verwendet, weil AVAssetExportSession nur grobe
/// Presets zulässt.
///
/// Cancellation: ist über die externe `Cancellation`-Brücke möglich, die
/// mit dem Aufrufer geteilt wird. Wir vermeiden bewusst, einen Actor-State
/// aus den Dispatch-Queues zu lesen, weil das zu Race-Conditions führt.
nonisolated public final class ReaderWriterTranscoder: Sendable {

    public init() {}

    public func transcode(
        sourceAsset: AVURLAsset,
        plan: ExportPlan,
        cancellation: Cancellation = Cancellation(),
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        TempFiles.remove(plan.outputURL)
        Log.transcoding.notice(
            "ReaderWriter begin output=\(plan.outputURL.lastPathComponent, privacy: .public) render=\(plan.renderWidth)x\(plan.renderHeight) encoded=\(plan.encodedWidth)x\(plan.encodedHeight) fps=\(plan.frameRate, privacy: .public) videoBps=\(plan.videoBitsPerSecond, privacy: .public) keepAudio=\(plan.keepAudio, privacy: .public)"
        )

        // --- Reader-Setup ----------------------------------------------
        let reader = try AVAssetReader(asset: sourceAsset)

        let videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw TranscodingError.missingVideoTrack
        }
        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        let audioTrack = audioTracks.first
        Log.transcoding.notice(
            "ReaderWriter tracks output=\(plan.outputURL.lastPathComponent, privacy: .public) videoTracks=\(videoTracks.count, privacy: .public) audioTracks=\(audioTracks.count, privacy: .public)"
        )

        let videoReaderSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            Log.transcoding.error("ReaderWriter cannot add video reader output=\(plan.outputURL.lastPathComponent, privacy: .public)")
            throw TranscodingError.readerSetupFailed
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        if plan.keepAudio, let audioTrack {
            let audioReaderSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioReaderSettings)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
                Log.transcoding.notice("ReaderWriter audio reader enabled output=\(plan.outputURL.lastPathComponent, privacy: .public)")
            } else {
                Log.transcoding.warning("ReaderWriter audio reader could not be added output=\(plan.outputURL.lastPathComponent, privacy: .public)")
            }
        }

        // --- Writer-Setup ----------------------------------------------
        let writer = try AVAssetWriter(outputURL: plan.outputURL, fileType: plan.fileType)
        writer.shouldOptimizeForNetworkUse = true

        let videoCompression: [String: Any] = [
            AVVideoAverageBitRateKey: plan.videoBitsPerSecond,
            AVVideoExpectedSourceFrameRateKey: Int(plan.frameRate.rounded()),
            AVVideoMaxKeyFrameIntervalKey: max(1, Int(plan.frameRate.rounded() * 2))
        ]

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: plan.encodedWidth,
            AVVideoHeightKey: plan.encodedHeight,
            AVVideoCompressionPropertiesKey: videoCompression
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        // Orientierung erhalten; Translation wurde auf die Zielgrösse skaliert.
        videoInput.transform = plan.outputTransform
        guard writer.canAdd(videoInput) else {
            Log.transcoding.error(
                "ReaderWriter cannot add video input output=\(plan.outputURL.lastPathComponent, privacy: .public) encoded=\(plan.encodedWidth)x\(plan.encodedHeight)"
            )
            throw TranscodingError.writerSetupFailed
        }
        writer.add(videoInput)

        let pixelBufferAdaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey as String: plan.encodedWidth,
            kCVPixelBufferHeightKey as String: plan.encodedHeight
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAdaptorAttrs
        )

        var audioInput: AVAssetWriterInput?
        if plan.keepAudio, audioOutput != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: plan.audioBitsPerSecond
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
                Log.transcoding.notice("ReaderWriter audio writer enabled output=\(plan.outputURL.lastPathComponent, privacy: .public)")
            } else {
                Log.transcoding.warning("ReaderWriter audio writer could not be added output=\(plan.outputURL.lastPathComponent, privacy: .public)")
            }
        }

        // --- Start -----------------------------------------------------
        guard reader.startReading() else {
            Log.transcoding.error("ReaderWriter reader start failed output=\(plan.outputURL.lastPathComponent, privacy: .public) error=\(String(describing: reader.error), privacy: .public)")
            throw TranscodingError.readerStartFailed(reader.error)
        }
        guard writer.startWriting() else {
            Log.transcoding.error("ReaderWriter writer start failed output=\(plan.outputURL.lastPathComponent, privacy: .public) error=\(String(describing: writer.error), privacy: .public)")
            throw TranscodingError.writerStartFailed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)
        Log.transcoding.notice("ReaderWriter started output=\(plan.outputURL.lastPathComponent, privacy: .public)")

        let duration = (try? await sourceAsset.load(.duration).seconds) ?? 0
        let totalSeconds = max(0.001, duration)

        // AVFoundation-Typen sind nicht formal Sendable, in Reader/Writer-
        // Pipelines aber dokumentiert thread-safe — wir kapseln in eine
        // Sendable-Box, damit @Sendable-Closures sie verwenden dürfen.
        let videoState = UnsafeSendableBox(VideoPipeline(
            input: videoInput,
            output: videoOutput,
            adaptor: adaptor,
            writer: writer
        ))
        let pixelScaler = PixelScaler()
        let lastFrameSecond = LockedDouble(initial: -1.0 / 240.0)
        let videoCallbackCounter = LockedCounter()
        let videoSampleCounter = LockedCounter()
        let audioCallbackCounter = LockedCounter()
        let audioSampleCounter = LockedCounter()

        // --- Pipelines starten -----------------------------------------
        let videoQueue = DispatchQueue(label: "shrink.video.write", qos: .userInitiated)
        let (videoStream, videoContinuation) = AsyncStream<Result<Void, Error>>.makeStream()

        videoState.value.input.requestMediaDataWhenReady(on: videoQueue) {
            let p = videoState.value
            let callback = videoCallbackCounter.next()
            if callback == 1 || callback.isMultiple(of: 20) {
                Log.transcoding.notice(
                    "ReaderWriter video callback output=\(plan.outputURL.lastPathComponent, privacy: .public) callback=\(callback, privacy: .public) ready=\(p.input.isReadyForMoreMediaData, privacy: .public) availableMB=\(ProcessMemory.availableMegabytes, privacy: .public)"
                )
            }
            if cancellation.isCancelled {
                p.input.markAsFinished()
                videoContinuation.yield(.failure(TranscodingError.cancelled))
                videoContinuation.finish()
                return
            }
            while p.input.isReadyForMoreMediaData {
                let sampleNumber = videoSampleCounter.next()
                let shouldLogSample = sampleNumber == 1 || sampleNumber.isMultiple(of: 30)
                if shouldLogSample {
                    Log.transcoding.notice(
                        "ReaderWriter video copy begin output=\(plan.outputURL.lastPathComponent, privacy: .public) sample=\(sampleNumber, privacy: .public) readerStatus=\(reader.status.rawValue, privacy: .public) writerStatus=\(p.writer.status.rawValue, privacy: .public) availableMB=\(ProcessMemory.availableMegabytes, privacy: .public)"
                    )
                }
                guard let sample = p.output.copyNextSampleBuffer() else {
                    p.input.markAsFinished()
                    Log.transcoding.notice("ReaderWriter video pipeline finished output=\(plan.outputURL.lastPathComponent, privacy: .public)")
                    videoContinuation.yield(.success(()))
                    videoContinuation.finish()
                    return
                }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let secs = pts.seconds
                let minDelta = 1.0 / plan.frameRate - 0.0005
                if secs - lastFrameSecond.value < minDelta {
                    continue
                }
                lastFrameSecond.set(secs)
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let shouldLogSample = sampleNumber == 1 || sampleNumber.isMultiple(of: 30)
                if shouldLogSample {
                    Log.transcoding.notice(
                        "ReaderWriter video sample output=\(plan.outputURL.lastPathComponent, privacy: .public) sample=\(sampleNumber, privacy: .public) pts=\(secs, privacy: .public) src=\(CVPixelBufferGetWidth(imageBuffer))x\(CVPixelBufferGetHeight(imageBuffer)) srcFormat=\(pixelFormatCode(CVPixelBufferGetPixelFormatType(imageBuffer)), privacy: .public) pool=\((p.adaptor.pixelBufferPool != nil), privacy: .public) availableMB=\(ProcessMemory.availableMegabytes, privacy: .public)"
                    )
                }
                guard let scaledBuffer = pixelScaler.scale(
                    imageBuffer,
                    to: CGSize(width: plan.encodedWidth, height: plan.encodedHeight),
                    pool: p.adaptor.pixelBufferPool
                ) else {
                    p.input.markAsFinished()
                    Log.transcoding.error("ReaderWriter pixel buffer creation failed output=\(plan.outputURL.lastPathComponent, privacy: .public)")
                    videoContinuation.yield(.failure(TranscodingError.pixelBufferCreationFailed))
                    videoContinuation.finish()
                    return
                }
                if shouldLogSample {
                    Log.transcoding.notice(
                        "ReaderWriter video scaled output=\(plan.outputURL.lastPathComponent, privacy: .public) sample=\(sampleNumber, privacy: .public) dst=\(CVPixelBufferGetWidth(scaledBuffer))x\(CVPixelBufferGetHeight(scaledBuffer)) dstFormat=\(pixelFormatCode(CVPixelBufferGetPixelFormatType(scaledBuffer)), privacy: .public) availableMB=\(ProcessMemory.availableMegabytes, privacy: .public)"
                    )
                }
                if !p.adaptor.append(scaledBuffer, withPresentationTime: pts) {
                    p.input.markAsFinished()
                    Log.transcoding.error("ReaderWriter video append failed output=\(plan.outputURL.lastPathComponent, privacy: .public) error=\(String(describing: p.writer.error), privacy: .public)")
                    videoContinuation.yield(.failure(
                        TranscodingError.writerAppendFailed(p.writer.error)
                    ))
                    videoContinuation.finish()
                    return
                }
                if shouldLogSample {
                    Log.transcoding.notice(
                        "ReaderWriter video appended output=\(plan.outputURL.lastPathComponent, privacy: .public) sample=\(sampleNumber, privacy: .public) writerStatus=\(p.writer.status.rawValue, privacy: .public) availableMB=\(ProcessMemory.availableMegabytes, privacy: .public)"
                    )
                }
                if secs.isFinite {
                    onProgress?(min(1.0, secs / totalSeconds))
                }
            }
        }

        let audioQueue = DispatchQueue(label: "shrink.audio.write", qos: .userInitiated)
        let (audioStream, audioContinuation) = AsyncStream<Result<Void, Error>>.makeStream()

        if let audioInput, let audioOutput {
            let audioState = UnsafeSendableBox(AudioPipeline(
                input: audioInput,
                output: audioOutput,
                writer: writer
            ))
            audioState.value.input.requestMediaDataWhenReady(on: audioQueue) {
                let p = audioState.value
                let callback = audioCallbackCounter.next()
                if callback == 1 || callback.isMultiple(of: 20) {
                    Log.transcoding.notice(
                        "ReaderWriter audio callback output=\(plan.outputURL.lastPathComponent, privacy: .public) callback=\(callback, privacy: .public) ready=\(p.input.isReadyForMoreMediaData, privacy: .public) availableMB=\(ProcessMemory.availableMegabytes, privacy: .public)"
                    )
                }
                if cancellation.isCancelled {
                    p.input.markAsFinished()
                    audioContinuation.yield(.failure(TranscodingError.cancelled))
                    audioContinuation.finish()
                    return
                }
                while p.input.isReadyForMoreMediaData {
                    let sampleNumber = audioSampleCounter.next()
                    let shouldLogSample = sampleNumber == 1 || sampleNumber.isMultiple(of: 100)
                    if shouldLogSample {
                        Log.transcoding.notice(
                            "ReaderWriter audio copy begin output=\(plan.outputURL.lastPathComponent, privacy: .public) sample=\(sampleNumber, privacy: .public) readerStatus=\(reader.status.rawValue, privacy: .public) writerStatus=\(p.writer.status.rawValue, privacy: .public) availableMB=\(ProcessMemory.availableMegabytes, privacy: .public)"
                        )
                    }
                    guard let sample = p.output.copyNextSampleBuffer() else {
                        p.input.markAsFinished()
                        Log.transcoding.notice("ReaderWriter audio pipeline finished output=\(plan.outputURL.lastPathComponent, privacy: .public)")
                        audioContinuation.yield(.success(()))
                        audioContinuation.finish()
                        return
                    }
                    if shouldLogSample {
                        Log.transcoding.notice(
                            "ReaderWriter audio sample output=\(plan.outputURL.lastPathComponent, privacy: .public) sample=\(sampleNumber, privacy: .public) availableMB=\(ProcessMemory.availableMegabytes, privacy: .public)"
                        )
                    }
                    if !p.input.append(sample) {
                        p.input.markAsFinished()
                        Log.transcoding.error("ReaderWriter audio append failed output=\(plan.outputURL.lastPathComponent, privacy: .public) error=\(String(describing: p.writer.error), privacy: .public)")
                        audioContinuation.yield(.failure(
                            TranscodingError.writerAppendFailed(p.writer.error)
                        ))
                        audioContinuation.finish()
                        return
                    }
                    if shouldLogSample {
                        Log.transcoding.notice(
                            "ReaderWriter audio appended output=\(plan.outputURL.lastPathComponent, privacy: .public) sample=\(sampleNumber, privacy: .public) writerStatus=\(p.writer.status.rawValue, privacy: .public) availableMB=\(ProcessMemory.availableMegabytes, privacy: .public)"
                        )
                    }
                }
            }
        } else {
            audioContinuation.yield(.success(()))
            audioContinuation.finish()
        }

        // --- Auf Pipelines warten --------------------------------------
        let videoResult = await firstResult(from: videoStream)
        let audioResult = await firstResult(from: audioStream)

        let writerBox = UnsafeSendableBox(writer)

        if cancellation.isCancelled {
            reader.cancelReading()
            writerBox.value.cancelWriting()
            TempFiles.remove(plan.outputURL)
            Log.transcoding.warning("ReaderWriter cancelled output=\(plan.outputURL.lastPathComponent, privacy: .public)")
            throw TranscodingError.cancelled
        }
        guard let videoResult else {
            writerBox.value.cancelWriting()
            TempFiles.remove(plan.outputURL)
            Log.transcoding.error("ReaderWriter missing video result output=\(plan.outputURL.lastPathComponent, privacy: .public)")
            throw TranscodingError.pipelineEndedUnexpectedly
        }
        guard let audioResult else {
            writerBox.value.cancelWriting()
            TempFiles.remove(plan.outputURL)
            Log.transcoding.error("ReaderWriter missing audio result output=\(plan.outputURL.lastPathComponent, privacy: .public)")
            throw TranscodingError.pipelineEndedUnexpectedly
        }
        if case let .failure(err) = videoResult {
            writerBox.value.cancelWriting()
            TempFiles.remove(plan.outputURL)
            Log.transcoding.error("ReaderWriter video failed output=\(plan.outputURL.lastPathComponent, privacy: .public) error=\(String(describing: err), privacy: .public)")
            throw err
        }
        if case let .failure(err) = audioResult {
            writerBox.value.cancelWriting()
            TempFiles.remove(plan.outputURL)
            Log.transcoding.error("ReaderWriter audio failed output=\(plan.outputURL.lastPathComponent, privacy: .public) error=\(String(describing: err), privacy: .public)")
            throw err
        }

        await writerBox.value.finishWriting()
        if writerBox.value.status != .completed {
            TempFiles.remove(plan.outputURL)
            Log.transcoding.error("ReaderWriter finish failed output=\(plan.outputURL.lastPathComponent, privacy: .public) status=\(writerBox.value.status.rawValue, privacy: .public) error=\(String(describing: writerBox.value.error), privacy: .public)")
            throw TranscodingError.writerFinishFailed(writerBox.value.error)
        }
        Log.transcoding.notice("ReaderWriter completed output=\(plan.outputURL.lastPathComponent, privacy: .public)")
        onProgress?(1.0)
    }

    private func firstResult<T: Sendable>(from stream: AsyncStream<T>) async -> T? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }
}

/// Bündelt die nicht-Sendable AVFoundation-Typen für die Video-Pipeline,
/// damit sie als ein Wert über @Sendable-Closure-Grenzen wandern können.
nonisolated private struct VideoPipeline {
    let input: AVAssetWriterInput
    let output: AVAssetReaderTrackOutput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let writer: AVAssetWriter
}

nonisolated private struct AudioPipeline {
    let input: AVAssetWriterInput
    let output: AVAssetReaderTrackOutput
    let writer: AVAssetWriter
}

/// Box, die einen beliebigen Wert als Sendable durchreicht. **Nur für
/// Apple-Typen verwenden, deren Thread-Safety dokumentiert ist** — z. B.
/// AVAssetWriter, AVAssetWriterInput, AVAssetReader, AVAsset­Writer­Input­
/// PixelBufferAdaptor, AVAssetReaderTrackOutput in Reader/Writer-Setups.
nonisolated struct UnsafeSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Externe Cancellation-Brücke. Wird vom Aufrufer angelegt und an den
/// Transcoder weitergereicht. Setzen über `cancel()`.
nonisolated public final class Cancellation: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    public init() {}
    public var isCancelled: Bool {
        lock.withLock { $0 }
    }
    public func cancel() {
        lock.withLock { $0 = true }
    }
}

/// Lock-geschützter Double für die fps-Drop-Logik.
nonisolated final class LockedDouble: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<Double>
    init(initial: Double) {
        self.lock = OSAllocatedUnfairLock(initialState: initial)
    }
    var value: Double {
        lock.withLock { $0 }
    }
    func set(_ newValue: Double) {
        lock.withLock { $0 = newValue }
    }
}

/// Thread-sicherer Zähler für Diagnose-Logs aus den AVFoundation-Queues.
nonisolated final class LockedCounter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func next() -> Int {
        lock.withLock {
            $0 += 1
            return $0
        }
    }
}

nonisolated private enum ProcessMemory {
    static var availableMegabytes: Int {
        Int(os_proc_available_memory() / 1_048_576)
    }
}

nonisolated private func pixelFormatCode(_ format: OSType) -> String {
    let bytes = [
        UInt8((format >> 24) & 0xFF),
        UInt8((format >> 16) & 0xFF),
        UInt8((format >> 8) & 0xFF),
        UInt8(format & 0xFF)
    ]
    let scalars = bytes.compactMap(UnicodeScalar.init)
    guard scalars.count == 4, scalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
        return String(format)
    }
    return String(String.UnicodeScalarView(scalars))
}

/// Pixel-Scaling über CIContext. Ein langlebiges Context-Objekt teilt
/// Render-Ressourcen über die Frame-Loop.
nonisolated final class PixelScaler: @unchecked Sendable {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func scale(_ buffer: CVPixelBuffer, to size: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        let srcWidth = CVPixelBufferGetWidth(buffer)
        let srcHeight = CVPixelBufferGetHeight(buffer)
        if srcWidth == Int(size.width) && srcHeight == Int(size.height) {
            return buffer
        }
        guard let pool else { return nil }
        var dst: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &dst)
        guard result == kCVReturnSuccess, let outBuf = dst else { return nil }

        let ci = CIImage(cvPixelBuffer: buffer)
        let scaleX = size.width / CGFloat(srcWidth)
        let scaleY = size.height / CGFloat(srcHeight)
        let transformed = ci.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        context.render(transformed, to: outBuf)
        return outBuf
    }
}

nonisolated public enum TranscodingError: LocalizedError {
    case missingVideoTrack
    case readerSetupFailed
    case writerSetupFailed
    case readerStartFailed(Error?)
    case writerStartFailed(Error?)
    case writerAppendFailed(Error?)
    case writerFinishFailed(Error?)
    case cancelled
    case unsupportedFormat
    case pipelineEndedUnexpectedly
    case pixelBufferCreationFailed

    public var errorDescription: String? {
        switch self {
        case .missingVideoTrack: return "Die Quelle enthält keine Video-Spur."
        case .readerSetupFailed: return "Der AVAssetReader konnte nicht initialisiert werden."
        case .writerSetupFailed: return "Der AVAssetWriter konnte nicht initialisiert werden."
        case .readerStartFailed(let e): return "Lesen fehlgeschlagen: \(e?.localizedDescription ?? "unbekannt")"
        case .writerStartFailed(let e): return "Schreiben fehlgeschlagen: \(e?.localizedDescription ?? "unbekannt")"
        case .writerAppendFailed(let e): return "Frame-Schreiben fehlgeschlagen: \(e?.localizedDescription ?? "unbekannt")"
        case .writerFinishFailed(let e): return "Abschluss fehlgeschlagen: \(e?.localizedDescription ?? "unbekannt")"
        case .cancelled: return "Export abgebrochen."
        case .unsupportedFormat: return "Format wird nicht unterstützt."
        case .pipelineEndedUnexpectedly: return "Der Export wurde unerwartet beendet."
        case .pixelBufferCreationFailed: return "Ein Videoframe konnte nicht für den Export vorbereitet werden."
        }
    }
}
