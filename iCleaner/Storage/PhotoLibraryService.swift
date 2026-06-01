import Photos
import UIKit
import Observation

// Wraps PHPhotoLibrary access for the Similar flow.
// MVP detector: cluster image assets by creation-time within a 60s window
// (most "similar" photos are bursts taken seconds apart). Real Vision feature
// print comparison can layer on top in Phase 3 Part B.2.
//
// Threading: PHPhotoLibrary observers fire on a background queue, so
// `authStatus` mutations are wrapped in `await MainActor.run`. The detector
// itself runs on the calling actor — the consumer should call it from a
// detached task to keep the main thread free during the enumerate.
@MainActor
@Observable
final class PhotoLibraryService {
    enum AuthorizationStatus: Equatable {
        case notDetermined, denied, restricted, authorized, limited

        init(_ raw: PHAuthorizationStatus) {
            switch raw {
            case .notDetermined: self = .notDetermined
            case .restricted:    self = .restricted
            case .denied:        self = .denied
            case .authorized:    self = .authorized
            case .limited:       self = .limited
            @unknown default:    self = .denied
            }
        }

        var canRead: Bool { self == .authorized || self == .limited }
    }

    private(set) var authStatus: AuthorizationStatus

    init() {
        self.authStatus = AuthorizationStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    @discardableResult
    func requestAuthorization() async -> AuthorizationStatus {
        let raw = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let new = AuthorizationStatus(raw)
        self.authStatus = new
        return new
    }

    // Per-category detection rules so each Home card surfaces the right assets
    // (not every card showing the same pool). See CleanKind for the mapping.
    struct DetectionConfig {
        var mediaType: PHAssetMediaType = .image
        var screenshotsOnly: Bool = false   // only PHAssetMediaSubtype.photoScreenshot
        var excludeScreenshots: Bool = false // skip screenshots (for "Similar" photos)
        var exactDuplicates: Bool = false    // group identical (same dims + ~size), not time-window
        var groupNoun: String = "Similar"    // group title noun, e.g. "4 Similar" / "3 Duplicates"
    }

    // `sinceDays`: only include assets created within the last N days (nil = all).
    // `largestFirst`: sort the resulting groups by total byte size desc/asc.
    func detectSimilarGroups(
        config: DetectionConfig = DetectionConfig(),
        clusteringWindow: TimeInterval = 60,
        sinceDays: Int? = nil,
        largestFirst: Bool = true
    ) async -> [PHAssetGroup] {
        guard authStatus.canRead else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            var predicates = [NSPredicate(format: "mediaType = %d", config.mediaType.rawValue)]
            if config.screenshotsOnly {
                predicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0",
                                              PHAssetMediaSubtype.photoScreenshot.rawValue))
            }
            if let sinceDays, let cutoff = Calendar.current.date(byAdding: .day, value: -sinceDays, to: Date()) {
                predicates.append(NSPredicate(format: "creationDate >= %@", cutoff as NSDate))
            }
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            let fetch = PHAsset.fetchAssets(with: options)

            var assets: [PHAsset] = []
            fetch.enumerateObjects { asset, _, _ in
                // For "Similar" photos, screenshots would pollute clusters — drop them.
                if config.excludeScreenshots,
                   asset.mediaSubtypes.contains(.photoScreenshot) { return }
                assets.append(asset)
            }

            let clusters: [[PHAsset]] = config.exactDuplicates
                ? Self.exactDuplicateClusters(assets)
                : Self.timeWindowClusters(assets, window: clusteringWindow)

            // Sort groups by estimated total size per the filter.
            let sized = clusters.map { cluster -> (cluster: [PHAsset], bytes: Int) in
                (cluster, cluster.reduce(0) { $0 + Int($1.estimatedSizeKB) })
            }
            let ordered = sized.sorted { largestFirst ? $0.bytes > $1.bytes : $0.bytes < $1.bytes }

            return ordered.map { item in
                PHAssetGroup(
                    title: "\(item.cluster.count) \(config.groupNoun)",
                    assets: item.cluster,
                    bestMatchIndex: 0  // first asset (oldest) wins as MVP
                )
            }
        }.value
    }

    // Groups consecutive assets shot within `window` seconds at the same
    // orientation — bursts / retakes of the same scene.
    nonisolated private static func timeWindowClusters(_ assets: [PHAsset], window: TimeInterval) -> [[PHAsset]] {
        var clusters: [[PHAsset]] = []
        var current: [PHAsset] = []
        var lastDate: Date?
        var lastOrientation: (Int, Int)?

        for asset in assets {
            let orientation = (asset.pixelWidth, asset.pixelHeight)
            let date = asset.creationDate ?? .distantPast
            let fits: Bool = {
                guard let lastDate, let lastOrientation else { return true }
                return abs(date.timeIntervalSince(lastDate)) <= window && lastOrientation == orientation
            }()
            if fits { current.append(asset) }
            else { if current.count >= 2 { clusters.append(current) }; current = [asset] }
            lastDate = date
            lastOrientation = orientation
        }
        if current.count >= 2 { clusters.append(current) }
        return clusters
    }

    // Groups assets that are likely exact duplicates: identical pixel dimensions
    // AND near-identical estimated size (within a small tolerance bucket).
    nonisolated private static func exactDuplicateClusters(_ assets: [PHAsset]) -> [[PHAsset]] {
        var buckets: [String: [PHAsset]] = [:]
        for asset in assets {
            // Round size to nearest 64 KB so re-encodes of the same shot still match.
            let sizeBucket = Int(asset.estimatedSizeKB) / 64
            let key = "\(asset.pixelWidth)x\(asset.pixelHeight)_\(sizeBucket)"
            buckets[key, default: []].append(asset)
        }
        return buckets.values.filter { $0.count >= 2 }
    }

    // Async wrapper around PHPhotoLibrary.shared().performChanges.
    // Throws on user-cancelled delete (`PHPhotosError.userCancelled`) — the
    // confirm sheet that iOS shows for trash bin can be dismissed by the user.
    func delete(assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    func opensSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Fetches the most-recent N image asset localIdentifiers — used by the Home
    /// category cards to show real thumbnails instead of placeholder gradients.
    /// Returns [] when not authorized so callers fall back to the placeholder.
    func recentImageIDs(limit: Int = 24) async -> [String] {
        guard authStatus.canRead else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            options.fetchLimit = limit
            let fetch = PHAsset.fetchAssets(with: options)
            var ids: [String] = []
            fetch.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
            return ids
        }.value
    }
}

struct PHAssetGroup: Identifiable {
    let id = UUID()
    let title: String
    let assets: [PHAsset]
    let bestMatchIndex: Int
}
