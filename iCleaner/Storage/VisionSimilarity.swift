import Foundation
import Photos
import Vision
import UIKit

// Content-based similarity using Vision feature prints. Replaces the old
// size/dimension heuristic (which wrongly grouped any same-resolution photos).
//
// Pipeline:
//   1. Load a small thumbnail (~120pt) per asset — cheap to feature-print.
//   2. Compute VNFeaturePrintObservation for each.
//   3. Cluster by pairwise distance with union-find. To keep it O(n·k) instead
//      of O(n²), we only compare assets whose creationDate is within a sliding
//      time window (similar/duplicate shots are virtually always near each other
//      in time), capped at a max scan count for battery/latency.
//
// Distance thresholds (VNFeaturePrintObservation.computeDistance, lower = more
// alike): duplicates are near-identical, similars are looser.
enum VisionSimilarity {
    enum Mode {
        case similar      // looser — retakes / same scene
        case duplicate    // tight — near-identical frames

        var threshold: Float {
            switch self {
            // Tightened from 0.55 — 0.55 grouped visibly different photos as
            // "similar". 0.38 keeps genuine retakes/near-duplicates together
            // while rejecting unrelated shots.
            case .similar:   return 0.38
            case .duplicate: return 0.20
            }
        }
    }

    /// Max assets to feature-print in one pass — keeps the scan responsive on
    /// large libraries. Oldest beyond this are skipped (logged by caller).
    static let maxScan = 300
    /// How many assets to feature-print concurrently (thumbnail load + Vision).
    static let printConcurrency = 12
    /// Only compare assets created within this window of each other (seconds).
    static let timeWindow: TimeInterval = 60 * 60 * 24  // 1 day

    /// Returns clusters (each ≥2) of assets judged alike for the given mode.
    /// `assets` must be sorted by creationDate ascending.
    static func cluster(_ assets: [PHAsset], mode: Mode) async -> [[PHAsset]] {
        let scan = Array(assets.suffix(maxScan))  // most recent maxScan
        guard scan.count >= 2 else { return [] }

        // 1. Feature print CONCURRENTLY (bounded windows). Sequential printing of up
        // to maxScan assets took 30s–2min on real libraries — this is the fix for
        // "Review Group loads forever". Order is preserved (time-sorted) for the
        // windowed union-find below.
        var printByIndex: [Int: VNFeaturePrintObservation] = [:]
        var start = 0
        while start < scan.count {
            let end = min(start + printConcurrency, scan.count)
            await withTaskGroup(of: (Int, FeaturePrintBox?).self) { group in
                for i in start..<end {
                    let asset = scan[i]
                    group.addTask { (i, (await featurePrint(for: asset)).map(FeaturePrintBox.init)) }
                }
                for await (i, box) in group { if let box { printByIndex[i] = box.fp } }
            }
            start = end
        }
        let prints: [(asset: PHAsset, fp: VNFeaturePrintObservation)] =
            scan.enumerated().compactMap { (i, a) in printByIndex[i].map { (a, $0) } }
        guard prints.count >= 2 else { return [] }

        // 2. Union-find over time-windowed pairs under the distance threshold.
        var parent = Array(0..<prints.count)
        func find(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
            return r
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        let threshold = mode.threshold
        for i in 0..<prints.count {
            let di = prints[i].asset.creationDate ?? .distantPast
            for j in (i + 1)..<prints.count {
                let dj = prints[j].asset.creationDate ?? .distantPast
                // Assets are time-sorted — once out of window, stop scanning forward.
                if abs(dj.timeIntervalSince(di)) > timeWindow { break }
                var distance: Float = .greatestFiniteMagnitude
                try? prints[i].fp.computeDistance(&distance, to: prints[j].fp)
                if distance <= threshold { union(i, j) }
            }
        }

        // 3. Bucket by root; keep clusters with ≥2 members, newest-first inside.
        var groups: [Int: [PHAsset]] = [:]
        for idx in prints.indices {
            groups[find(idx), default: []].append(prints[idx].asset)
        }
        return groups.values
            .filter { $0.count >= 2 }
            .map { $0.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) } }
    }

    // MARK: - Feature print

    // Feature prints cached by localIdentifier — re-opening the same category (or
    // re-running after a delete) reuses them instead of re-decoding + re-printing
    // every asset, so only the FIRST scan pays the cost. NSCache auto-evicts.
    private static let fpCache = NSCache<NSString, VNFeaturePrintObservation>()

    private static func featurePrint(for asset: PHAsset) async -> VNFeaturePrintObservation? {
        let key = asset.localIdentifier as NSString
        if let cached = fpCache.object(forKey: key) { return cached }
        guard let image = await thumbnail(for: asset),
              let cg = image.cgImage else { return nil }
        let fp: VNFeaturePrintObservation? = await withCheckedContinuation { (cont: CheckedContinuation<VNFeaturePrintObservation?, Never>) in
            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                cont.resume(returning: request.results?.first as? VNFeaturePrintObservation)
            } catch {
                cont.resume(returning: nil)
            }
        }
        if let fp { fpCache.setObject(fp, forKey: key) }
        return fp
    }

    private static func thumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false  // feature print works on local only
            // .fastFormat can invoke the handler MORE THAN ONCE — resuming a
            // continuation twice traps. Guard with a one-shot flag (the handler is
            // serialised on PHImageManager's queue, so the flag is safe).
            nonisolated(unsafe) var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 120, height: 120),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: image)
            }
        }
    }
}

// VNFeaturePrintObservation isn't Sendable; box it so the concurrent feature-print
// task group can return it across task boundaries without a data-race warning (the
// observation is immutable and only read afterward).
private final class FeaturePrintBox: @unchecked Sendable {
    let fp: VNFeaturePrintObservation
    init(_ fp: VNFeaturePrintObservation) { self.fp = fp }
}
