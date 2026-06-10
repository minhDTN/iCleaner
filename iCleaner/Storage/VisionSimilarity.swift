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
    static let maxScan = 600
    /// Only compare assets created within this window of each other (seconds).
    static let timeWindow: TimeInterval = 60 * 60 * 24  // 1 day

    /// Returns clusters (each ≥2) of assets judged alike for the given mode.
    /// `assets` must be sorted by creationDate ascending.
    static func cluster(_ assets: [PHAsset], mode: Mode) async -> [[PHAsset]] {
        let scan = Array(assets.suffix(maxScan))  // most recent maxScan
        guard scan.count >= 2 else { return [] }

        // 1. Feature print each asset (skip ones that fail to load/print).
        var prints: [(asset: PHAsset, fp: VNFeaturePrintObservation)] = []
        prints.reserveCapacity(scan.count)
        for asset in scan {
            if let fp = await featurePrint(for: asset) {
                prints.append((asset, fp))
            }
        }
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

    private static func featurePrint(for asset: PHAsset) async -> VNFeaturePrintObservation? {
        guard let image = await thumbnail(for: asset),
              let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<VNFeaturePrintObservation?, Never>) in
            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                cont.resume(returning: request.results?.first as? VNFeaturePrintObservation)
            } catch {
                cont.resume(returning: nil)
            }
        }
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
