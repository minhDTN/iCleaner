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
        var albumNames: [String]? = nil      // restrict to user albums matching these names (e.g. chat apps)
        var groupNoun: String = "Similar"    // group title noun, e.g. "4 Similar" / "3 Duplicates"
        // Only Similar/Duplicate-style categories cluster into packs and carry a
        // "Best Match" keeper. Browse buckets (Other, Other Screenshots, Chat,
        // Videos Organizer) are ONE flat list the user deletes by hand.
        var grouped: Bool = true             // false → single flat list of all matches, no clustering
        var hasBestMatch: Bool = true        // false → no Best Match pill / no auto-selection

        // Vision content-clustering (Similar / Similar Screenshots) is the only
        // expensive path — it streams the whole gallery in chunks. Duplicates
        // (cheap signature), videos (time-window) and flat lists do not.
        var usesVisionClustering: Bool { grouped && mediaType == .image && !exactDuplicates }
    }

    // Single source of truth for "which assets belong to this category" — used by
    // BOTH the Home card preview and the detail scan, so the photos shown outside a
    // card and inside its detail come from the same pool. `recentFirst`/`limit` let
    // the preview grab just the newest few cheaply (no clustering).
    nonisolated static func matchingAssets(config: DetectionConfig, sinceDays: Int?, recentFirst: Bool, limit: Int?) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: !recentFirst)]
        var predicates = [NSPredicate(format: "mediaType = %d", config.mediaType.rawValue)]
        if config.screenshotsOnly {
            predicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0",
                                          PHAssetMediaSubtype.photoScreenshot.rawValue))
        }
        if let sinceDays, let cutoff = Calendar.current.date(byAdding: .day, value: -sinceDays, to: Date()) {
            predicates.append(NSPredicate(format: "creationDate >= %@", cutoff as NSDate))
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        func keep(_ asset: PHAsset) -> Bool {
            !(config.excludeScreenshots && asset.mediaSubtypes.contains(.photoScreenshot))
        }

        if let albumNames = config.albumNames {
            // Only assets inside user albums whose name matches (WhatsApp, Telegram…).
            let colls = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            var collected: [PHAsset] = []
            var seen = Set<String>()
            colls.enumerateObjects { coll, _, _ in
                guard let title = coll.localizedTitle,
                      albumNames.contains(where: { title.localizedCaseInsensitiveContains($0) }) else { return }
                PHAsset.fetchAssets(in: coll, options: options).enumerateObjects { asset, _, _ in
                    if keep(asset), seen.insert(asset.localIdentifier).inserted { collected.append(asset) }
                }
            }
            collected.sort {
                let a = $0.creationDate ?? .distantPast, b = $1.creationDate ?? .distantPast
                return recentFirst ? a > b : a < b
            }
            return limit.map { Array(collected.prefix($0)) } ?? collected
        }

        var result: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, stop in
            guard keep(asset) else { return }
            result.append(asset)
            if let limit, result.count >= limit { stop.pointee = true }
        }
        return result
    }

    /// Recent localIdentifiers matching a category's config — what its Home card
    /// previews. Same pool the detail scans, so outside and inside stay consistent.
    func previewAssetIDs(config: DetectionConfig, limit: Int = 3) async -> [String] {
        guard authStatus.canRead else { return [] }
        return await Task.detached(priority: .userInitiated) {
            Self.matchingAssets(config: config, sinceDays: nil, recentFirst: true, limit: limit)
                .map(\.localIdentifier)
        }.value
    }

    /// One scan per Home card: the 3 preview IDs + the REAL count and total byte
    /// size of the whole category pool — so the card stops showing hardcoded mock
    /// numbers and reflects the actual library (off main).
    func categoryScan(config: DetectionConfig, previewLimit: Int = 3) async -> (previewIDs: [String], count: Int, totalKB: Int) {
        guard authStatus.canRead else { return ([], 0, 0) }
        return await Task.detached(priority: .utility) {
            let assets = Self.matchingAssets(config: config, sinceDays: nil, recentFirst: true, limit: nil)
            let previews = assets.prefix(previewLimit).map(\.localIdentifier)
            let totalKB = assets.reduce(0) { $0 + Self.realBytesKB($1) }
            return (Array(previews), assets.count, totalKB)
        }.value
    }

    // `sinceDays`: only include assets created within the last N days (nil = all).
    // `largestFirst`: sort the resulting groups by total byte size desc/asc.
    //
    // Clustering is CONTENT-based via Vision feature prints (VisionSimilarity) —
    // photos are grouped by what they actually look like, not by file
    // size/dimensions. Videos still fall back to time-window grouping (Vision
    // image prints don't apply to video frames in this MVP).
    func detectSimilarGroups(
        config: DetectionConfig = DetectionConfig(),
        clusteringWindow: TimeInterval = 60,
        sinceDays: Int? = nil,
        largestFirst: Bool = true
    ) async -> [PHAssetGroup] {
        guard authStatus.canRead else { return [] }

        // 1. Fetch matching assets (off main) — same pool the Home card previews.
        let assets: [PHAsset] = await Task.detached(priority: .userInitiated) {
            Self.matchingAssets(config: config, sinceDays: sinceDays, recentFirst: false, limit: nil)
        }.value

        // Flat browse bucket (Other / Other Screenshots / Chat / Videos Organizer):
        // no clustering, no Best Match — ONE list of every match, newest first, so
        // the user can always open it and delete by hand. Returns empty only when
        // there are genuinely no matching assets.
        if !config.grouped {
            guard !assets.isEmpty else { return [] }
            return await Task.detached(priority: .userInitiated) {
                // Sort the flat list by REAL size so the "Large/Small to size" filter
                // actually orders the items (it only ordered groups before).
                let sized = assets.map { ($0, Self.realBytesKB($0)) }
                    .sorted { largestFirst ? $0.1 > $1.1 : $0.1 < $1.1 }
                return [PHAssetGroup(title: "\(sized.count) \(config.groupNoun)",
                                     assets: sized.map(\.0), sizesKB: sized.map(\.1), bestMatchIndex: -1)]
            }.value
        }

        // 2. Cluster. Exact duplicates use a CHEAP signature (dimensions + real byte
        // size), NOT Vision — running Vision feature prints over the whole library
        // froze the Duplicates screen for ~2 min. Similar = Vision (content), videos
        // = time-window.
        let clusters: [[PHAsset]]
        if config.exactDuplicates {
            clusters = await Task.detached(priority: .userInitiated) {
                Self.exactDuplicateClusters(assets)
            }.value
        } else if config.mediaType == .video {
            clusters = await Task.detached(priority: .userInitiated) {
                Self.timeWindowClusters(assets, window: clusteringWindow)
            }.value
        } else {
            clusters = await VisionSimilarity.cluster(assets, mode: .similar)
        }

        // 3. Real byte sizes per asset + sort groups by total size.
        return await Task.detached(priority: .userInitiated) {
            let sized = clusters.map { cluster -> (cluster: [PHAsset], sizes: [Int], bytes: Int) in
                let sizes = cluster.map { Self.realBytesKB($0) }
                return (cluster, sizes, sizes.reduce(0, +))
            }
            let ordered = sized.sorted { largestFirst ? $0.bytes > $1.bytes : $0.bytes < $1.bytes }
            return ordered.map { item in
                PHAssetGroup(title: "\(item.cluster.count) \(config.groupNoun)",
                             assets: item.cluster, sizesKB: item.sizes,
                             bestMatchIndex: 0)  // first asset (oldest) wins as MVP
            }
        }.value
    }

    // Per-asset size cache — `PHAssetResource.assetResources(for:)` is a slow Photos
    // round-trip, and Home re-scans every category on each appearance. Caching by
    // localIdentifier means each asset's size is fetched once for its lifetime.
    private nonisolated(unsafe) static var sizeCacheStore: [String: Int] = [:]
    private static let sizeCacheLock = NSLock()

    /// Real on-disk size of an asset in KB (from its `PHAssetResource`), falling
    /// Streams Similar/Similar-Screenshots groups over the WHOLE gallery, newest
    /// first, in chunks — so the caller can show the review screen immediately and
    /// append groups as they're found, instead of blocking on a full Vision scan.
    /// `onBatch` is called on the main actor for each chunk that yields groups.
    /// Feature prints are cached, so re-opening is near-instant.
    func detectSimilarGroupsStreaming(
        config: DetectionConfig,
        sinceDays: Int? = nil,
        chunkSize: Int = 150,
        onBatch: @MainActor @escaping ([PHAssetGroup]) -> Void
    ) async {
        guard authStatus.canRead else { return }
        // Whole pool, newest first (so recent groups appear at the top first).
        let all: [PHAsset] = await Task.detached(priority: .userInitiated) {
            Self.matchingAssets(config: config, sinceDays: sinceDays, recentFirst: true, limit: nil)
        }.value
        guard !all.isEmpty else { return }

        var start = 0
        while start < all.count {
            if Task.isCancelled { return }
            let end = min(start + chunkSize, all.count)
            let chunk = Array(all[start..<end])
            start = end

            // Cluster this chunk (assets sorted ascending for the time-window union-find).
            let ascending = chunk.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            let clusters = await VisionSimilarity.cluster(ascending, mode: .similar)
            guard !clusters.isEmpty else { continue }

            // Build groups + real sizes off main, then hand to the UI.
            let groups: [PHAssetGroup] = await Task.detached(priority: .userInitiated) {
                clusters.map { c in
                    let sizes = c.map { Self.realBytesKB($0) }
                    return PHAssetGroup(title: "\(c.count) \(config.groupNoun)",
                                        assets: c, sizesKB: sizes, bestMatchIndex: 0)
                }
            }.value
            if Task.isCancelled { return }
            onBatch(groups)
        }
    }

    /// back to the dimension estimate when the resource size is unavailable. Cached.
    nonisolated static func realBytesKB(_ asset: PHAsset) -> Int {
        let id = asset.localIdentifier
        sizeCacheLock.lock(); let cached = sizeCacheStore[id]; sizeCacheLock.unlock()
        if let cached { return cached }

        var kb = Int(asset.estimatedSizeKB)
        for resource in PHAssetResource.assetResources(for: asset) {
            if let bytes = resource.value(forKey: "fileSize") as? Int, bytes > 0 {
                kb = bytes / 1024; break
            }
        }
        sizeCacheLock.lock(); sizeCacheStore[id] = kb; sizeCacheLock.unlock()
        return kb
    }

    /// Exact-duplicate clustering WITHOUT Vision: group assets sharing the same
    /// dimensions AND real byte size (a strong exact-copy signal), O(n). Each
    /// cluster has ≥2 members, oldest first.
    nonisolated static func exactDuplicateClusters(_ assets: [PHAsset]) -> [[PHAsset]] {
        var buckets: [String: [PHAsset]] = [:]
        for a in assets {
            let key = "\(a.pixelWidth)x\(a.pixelHeight)-\(realBytesKB(a))"
            buckets[key, default: []].append(a)
        }
        return buckets.values
            .filter { $0.count >= 2 }
            .map { $0.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) } }
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
    var sizesKB: [Int] = []   // real per-asset size (KB), parallel to `assets`
    let bestMatchIndex: Int

    /// Real total size of the group in KB.
    var totalSizeKB: Int { sizesKB.reduce(0, +) }
}
