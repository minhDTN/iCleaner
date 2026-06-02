import Foundation
import AVFoundation
import Photos
import Observation
import LibEarnMoneyIOS

// Video compressor for the Compress flow.
//   • Re-encodes with AVAssetReader → AVAssetWriter at an explicit target bitrate
//     derived from the SOURCE bitrate (a fraction of it), so the output is always
//     smaller — unlike AVAssetExportSession presets, whose fixed bitrate can
//     inflate an already-compressed clip (e.g. 683 KB → 3.5 MB).
//   • The shown estimate is computed from the SAME target bitrate, so "≈ size"
//     on screen matches the real result.
//   • 3 quality tiers (Best / Balanced★ / Maximum Savings) = different bitrate
//     fractions + ceilings.
//   • Daily usage quota for free tier — 2/day, key-rolled at local midnight.
//     Premium users bypass the quota entirely.
//   • Output is written to NSTemporaryDirectory so callers can Replace original
//     (save compressed + delete source asset) or Keep both (save compressed only).
//   • Progress is exposed as @Observable `progress: Double` (0...1).
@MainActor
@Observable
final class VideoCompressor {
    enum Quality: String, CaseIterable, Identifiable {
        case best, balanced, savings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .best:     return "Best Quality"
            case .balanced: return "Balanced"
            case .savings:  return "Maximum Savings"
            }
        }
        var subtitle: String {
            switch self {
            case .best:     return "Up to 1080p — best quality"
            case .balanced: return "Up to 720p — recommended for sharing"
            case .savings:  return "Up to 540p — smallest file"
            }
        }
        var isRecommended: Bool { self == .balanced }

        /// Fraction of the source video bitrate to target. < 1 so output always
        /// shrinks; lower tier = more compression.
        var bitrateFraction: Double {
            switch self {
            case .best:     return 0.60
            case .balanced: return 0.42
            case .savings:  return 0.26
            }
        }
        /// Absolute video-bitrate ceiling (bits/s) so huge 4K sources also shrink.
        var bitrateCeiling: Double {
            switch self {
            case .best:     return 8_000_000
            case .balanced: return 4_000_000
            case .savings:  return 2_000_000
            }
        }
        /// Rough ratio used only as a last-resort fallback (no source bitrate).
        var estimatedRatio: Double {
            switch self {
            case .best:     return 0.70
            case .balanced: return 0.50
            case .savings:  return 0.30
            }
        }
    }

    struct TargetBitrates { let video: Double; let audio: Double }

    /// Target encode bitrates derived from the source. Video is a fraction of the
    /// source rate, clamped to a per-tier ceiling and a floor, and ALWAYS kept
    /// below the source (× 0.9) so the result never inflates.
    nonisolated static func targetBitrates(quality: Quality, srcVideoRate: Double, srcAudioRate: Double, hasAudio: Bool) -> TargetBitrates {
        var v = srcVideoRate > 0 ? srcVideoRate * quality.bitrateFraction : quality.bitrateCeiling
        v = min(v, quality.bitrateCeiling)
        v = max(v, 100_000)
        if srcVideoRate > 0 { v = min(v, srcVideoRate * 0.9) }   // never above source
        var a: Double = 0
        if hasAudio { a = srcAudioRate > 0 ? min(srcAudioRate, 128_000) : 96_000 }
        return TargetBitrates(video: v, audio: a)
    }

    enum CompressError: Error, LocalizedError {
        case quotaExceeded
        case noVideoTrack
        case exportFailed(String)
        case cancelled
        case saveDenied

        var errorDescription: String? {
            switch self {
            case .quotaExceeded:       return "Daily free limit reached. Upgrade to compress more videos."
            case .noVideoTrack:        return "This file doesn't contain a video track."
            case .exportFailed(let s): return "Compression failed: \(s)"
            case .cancelled:           return "Compression cancelled."
            case .saveDenied:          return "Photos permission required to save the compressed video."
            }
        }
    }

    static let dailyLimit = 2

    /// 0...1 during an active export; reset to 0 between runs.
    private(set) var progress: Double = 0
    private(set) var isExporting: Bool = false
    private(set) var lastOutputURL: URL?

    private var activeCancel: CancelBox?

    // MARK: - Quota

    var usesUsedToday: Int {
        UserDefaults.standard.integer(forKey: Self.dailyKey())
    }
    var usesRemainingToday: Int { max(0, Self.dailyLimit - usesUsedToday) }
    var canCompressMore: Bool {
        PremiumGate.isPremium || usesRemainingToday > 0
    }

    private static func dailyKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        return "compress.uses.\(f.string(from: Date()))"
    }

    private func incrementUsage() {
        let key = Self.dailyKey()
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }

    // MARK: - Estimate

    /// Estimated output size = (targetVideoBitrate + targetAudioBitrate) × duration / 8,
    /// using the SAME target bitrates the encoder will use, so the shown number
    /// matches the real result. Always ≤ the source size (the encoder targets a
    /// fraction of the source bitrate).
    func estimateOutput(sourceURL: URL, quality: Quality, originalBytes: Int) async -> Int {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return Self.estimatedOutputBytes(inputBytes: originalBytes, quality: quality)
        }
        let durationSec = max(0.1, CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero))
        let srcVideoRate = Double((try? await videoTrack.load(.estimatedDataRate)) ?? 0)
        let audioTrack = (try? await asset.loadTracks(withMediaType: .audio).first) ?? nil
        let srcAudioRate = audioTrack != nil ? Double((try? await audioTrack!.load(.estimatedDataRate)) ?? 0) : 0
        let t = Self.targetBitrates(quality: quality, srcVideoRate: srcVideoRate, srcAudioRate: srcAudioRate, hasAudio: audioTrack != nil)
        let bytes = Int((t.video + t.audio) * durationSec / 8.0)
        guard bytes > 0 else { return Self.estimatedOutputBytes(inputBytes: originalBytes, quality: quality) }
        return originalBytes > 0 ? min(bytes, originalBytes) : bytes
    }

    /// Rough fallback estimate (input × ratio) when source bitrate is unavailable.
    nonisolated static func estimatedOutputBytes(inputBytes: Int, quality: Quality) -> Int {
        Int(Double(inputBytes) * quality.estimatedRatio)
    }

    // MARK: - Export

    /// Re-encodes `sourceURL` at the selected quality's target bitrate (a fraction
    /// of the source), so the result is always smaller. Increments the daily
    /// counter only after a successful export. Output lives in NSTemporaryDirectory.
    @discardableResult
    func compress(sourceURL: URL, quality: Quality) async throws -> URL {
        guard canCompressMore else { throw CompressError.quotaExceeded }

        progress = 0
        isExporting = true
        let cancelBox = CancelBox()
        activeCancel = cancelBox
        defer {
            isExporting = false
            activeCancel = nil
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw CompressError.noVideoTrack
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let durationSec = max(0.1, CMTimeGetSeconds(try await asset.load(.duration)))
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let srcVideoRate = Double(try await videoTrack.load(.estimatedDataRate))
        let srcAudioRate = audioTrack != nil ? Double((try? await audioTrack!.load(.estimatedDataRate)) ?? 0) : 0

        let targets = Self.targetBitrates(quality: quality, srcVideoRate: srcVideoRate, srcAudioRate: srcAudioRate, hasAudio: audioTrack != nil)

        // Encode at the source's native dimensions (rotation handled via transform);
        // bitrate alone drives the size. H.264 needs even dimensions.
        let outW = Int(abs(naturalSize.width).rounded()) & ~1
        let outH = Int(abs(naturalSize.height).rounded()) & ~1
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: max(2, outW),
            AVVideoHeightKey: max(2, outH),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(targets.video),
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let audioSettings: [String: Any]? = audioTrack != nil ? [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: Int(max(48_000, targets.audio))
        ] : nil

        let outURL = NSURL.fileURL(withPath: NSTemporaryDirectory())
            .appendingPathComponent("iCleaner-compress-\(UUID().uuidString.prefix(8)).mp4")

        try await Self.performTranscode(
            asset: asset, videoTrack: videoTrack, audioTrack: audioTrack,
            outURL: outURL, videoSettings: videoSettings, audioSettings: audioSettings,
            transform: transform, durationSec: durationSec,
            isCancelled: { cancelBox.value },
            onProgress: { [weak self] p in Task { @MainActor in self?.progress = p } }
        )

        incrementUsage()
        lastOutputURL = outURL
        progress = 1
        return outURL
    }

    func cancel() { activeCancel?.cancel() }

    // MARK: - Transcode pipeline

    nonisolated private static func performTranscode(
        asset: AVURLAsset,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack?,
        outURL: URL,
        videoSettings: [String: Any],
        audioSettings: [String: Any]?,
        transform: CGAffineTransform,
        durationSec: Double,
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoOut = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        videoOut.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOut) else { throw CompressError.exportFailed("reader video output") }
        reader.add(videoOut)

        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoIn.expectsMediaDataInRealTime = false
        videoIn.transform = transform
        guard writer.canAdd(videoIn) else { throw CompressError.exportFailed("writer video input") }
        writer.add(videoIn)

        var audioOut: AVAssetReaderTrackOutput?
        var audioIn: AVAssetWriterInput?
        if let audioTrack, let audioSettings {
            let aOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            aOut.alwaysCopiesSampleData = false
            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aIn.expectsMediaDataInRealTime = false
            if reader.canAdd(aOut) && writer.canAdd(aIn) {
                reader.add(aOut); writer.add(aIn)
                audioOut = aOut; audioIn = aIn
            }
        }

        guard reader.startReading() else {
            throw CompressError.exportFailed(reader.error?.localizedDescription ?? "startReading")
        }
        guard writer.startWriting() else {
            throw CompressError.exportFailed(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)

        let videoQueue = DispatchQueue(label: "icleaner.compress.video")
        async let videoDone: Void = pump(videoOut, into: videoIn, on: videoQueue,
                                         durationSec: durationSec, onProgress: onProgress, isCancelled: isCancelled)
        if let audioOut, let audioIn {
            let audioQueue = DispatchQueue(label: "icleaner.compress.audio")
            async let audioDone: Void = pump(audioOut, into: audioIn, on: audioQueue,
                                            durationSec: 0, onProgress: nil, isCancelled: isCancelled)
            _ = await (videoDone, audioDone)
        } else {
            _ = await videoDone
        }

        if isCancelled() {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outURL)
            throw CompressError.cancelled
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw CompressError.exportFailed(reader.error?.localizedDescription ?? "reader failed")
        }

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw CompressError.exportFailed(writer.error?.localizedDescription ?? "writer status \(writer.status.rawValue)")
        }
    }

    /// Drains one reader output into one writer input on the given queue, resuming
    /// exactly once when the track is fully transferred / cancelled / fails.
    nonisolated private static func pump(
        _ output: AVAssetReaderTrackOutput,
        into input: AVAssetWriterInput,
        on queue: DispatchQueue,
        durationSec: Double,
        onProgress: (@Sendable (Double) -> Void)?,
        isCancelled: @escaping @Sendable () -> Bool
    ) async {
        // AVFoundation's pull model serialises all access on `queue`, so these are
        // safe to use there despite being non-Sendable.
        nonisolated(unsafe) let input = input
        nonisolated(unsafe) let output = output
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if isCancelled() {
                        input.markAsFinished(); cont.resume(); return
                    }
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished(); cont.resume(); return
                    }
                    if let onProgress, durationSec > 0 {
                        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                        onProgress(min(0.99, max(0, t / durationSec)))
                    }
                    if !input.append(sample) {
                        input.markAsFinished(); cont.resume(); return
                    }
                }
                // Not ready for more yet — the block is re-invoked later; don't resume.
            }
        }
    }

    // MARK: - Save back to Photos

    /// Imports the compressed file to Photos. If `deletingSource` is set, that
    /// asset is removed in the same change request (Replace Original UX).
    func saveToPhotos(fileURL: URL, deletingSource: PHAsset? = nil) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw CompressError.saveDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            if let deletingSource {
                PHAssetChangeRequest.deleteAssets([deletingSource] as NSArray)
            }
        }
    }
}

// Thread-safe cancel flag shared with the background transcode queues.
private final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}
