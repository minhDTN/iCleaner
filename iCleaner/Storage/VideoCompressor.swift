import Foundation
import AVFoundation
import Photos
import Observation
import LibEarnMoneyIOS

// Wraps AVAssetExportSession for the Compress flow.
//   • 3 quality presets (Best / Balanced★ / Maximum Savings) mapped to
//     Apple's standard export presets.
//   • Daily usage quota for free tier — 2/day, key-rolled at local midnight.
//     Premium users bypass the quota entirely.
//   • Output is written to NSTemporaryDirectory so callers can Replace original
//     (save compressed + delete source asset) or Keep both (save compressed only).
//   • Progress is exposed as @Observable `progress: Double` (0...1) so the
//     SwiftUI ring updates without polling boilerplate.
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
            case .best:     return "Keep source resolution, lighter encode"
            case .balanced: return "1280×720 — recommended for sharing"
            case .savings:  return "960×540 — smallest file"
            }
        }
        var isRecommended: Bool { self == .balanced }

        /// AVFoundation preset id.
        var avPreset: String {
            switch self {
            case .best:     return AVAssetExportPresetHighestQuality
            case .balanced: return AVAssetExportPreset1280x720
            case .savings:  return AVAssetExportPreset960x540
            }
        }
        /// Heuristic compression ratio used for the "Estimated size" badge —
        /// real ratio depends on codec/bitrate, so this is intentionally rough.
        var estimatedRatio: Double {
            switch self {
            case .best:     return 0.70
            case .balanced: return 0.50
            case .savings:  return 0.30
            }
        }
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

    private var currentExport: AVAssetExportSession?
    private var progressTimer: Timer?

    // MARK: - Quota

    var usesUsedToday: Int {
        UserDefaults.standard.integer(forKey: Self.dailyKey())
    }
    var usesRemainingToday: Int { max(0, Self.dailyLimit - usesUsedToday) }
    var canCompressMore: Bool {
        PermissionManager.shared.isPremium || usesRemainingToday > 0
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

    /// Returns the estimated output file size in bytes for a given input + quality.
    /// Used to display "Estimated 120 MB" on the entry screen.
    nonisolated static func estimatedOutputBytes(inputBytes: Int, quality: Quality) -> Int {
        Int(Double(inputBytes) * quality.estimatedRatio)
    }

    // MARK: - Export

    /// Exports `sourceURL` at the selected quality. Increments the daily counter
    /// only after a successful export. Output URL lives in NSTemporaryDirectory.
    @discardableResult
    func compress(sourceURL: URL, quality: Quality) async throws -> URL {
        guard canCompressMore else { throw CompressError.quotaExceeded }

        progress = 0
        isExporting = true
        defer {
            isExporting = false
            stopProgressTimer()
            currentExport = nil
        }

        let asset = AVURLAsset(url: sourceURL)
        guard !(try await asset.load(.tracks).isEmpty) else {
            throw CompressError.noVideoTrack
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: quality.avPreset) else {
            throw CompressError.exportFailed("Couldn't create export session for preset \(quality.avPreset).")
        }

        let outURL = NSURL.fileURL(withPath: NSTemporaryDirectory())
            .appendingPathComponent("iCleaner-compress-\(UUID().uuidString.prefix(8)).mp4")

        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        currentExport = session
        startProgressTimer()

        await session.export()

        switch session.status {
        case .completed:
            incrementUsage()
            lastOutputURL = outURL
            progress = 1
            return outURL
        case .cancelled:
            throw CompressError.cancelled
        case .failed:
            throw CompressError.exportFailed(session.error?.localizedDescription ?? "Unknown error")
        default:
            throw CompressError.exportFailed("Unexpected export status \(session.status.rawValue).")
        }
    }

    func cancel() {
        currentExport?.cancelExport()
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let session = self?.currentExport else { return }
                self?.progress = Double(session.progress)
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
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
