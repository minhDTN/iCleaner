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
        var detectChat: Bool = false         // OCR-classify ANY image: keep only chat conversations

        // Similar / Similar Screenshots / Chat stream in batches so results appear
        // progressively while the slow part (clustering sizes, or OCR for Chat) runs.
        // Exact duplicates and the other flat browse buckets use the one-shot scan.
        var usesStreamingScan: Bool { (grouped || detectChat) && mediaType == .image && !exactDuplicates }

        // Canonical "Similar photos" rule — non-screenshot image bursts. Shared by
        // the Home Similar card AND Quick Clean so their numbers match exactly.
        static var similar: DetectionConfig { .init(mediaType: .image, excludeScreenshots: true, groupNoun: "Similar") }
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

    // Per-card stats. For GROUPED categories the count/size cover ONLY photos that
    // land in a cluster (>=2) — so the Home card matches the Review Group header
    // exactly. `reclaimableKB` = everything except the Best Match per group (what a
    // 1-tap clean would free). Browse buckets are a flat list of all matches.
    struct CategoryStat {
        var previewIDs: [String] = []
        var count: Int = 0
        var totalKB: Int = 0
        var reclaimableKB: Int = 0
        var reclaimableCount: Int = 0
        var groupCount: Int = 0
    }

    /// One scan per Home card: preview IDs + REAL count/size — using the SAME
    /// clustering policy as the detail scan, so the card never disagrees with what
    /// the user sees inside Review Group (off main).
    func categoryScan(config: DetectionConfig, previewLimit: Int = 3) async -> CategoryStat {
        guard authStatus.canRead else { return CategoryStat() }
        return await Task.detached(priority: .utility) {
            var assets = Self.matchingAssets(config: config, sinceDays: nil, recentFirst: false, limit: nil)
            // Chat: keep only images whose filename matches a chat app (cheap metadata
            // read, not OCR). Runs in the deferred phase so it doesn't block the other
            // cards; verdicts are cached + persisted so it's one-time per asset.
            if config.detectChat { assets = await Self.filterChatImages(assets) }
            guard !assets.isEmpty else { return CategoryStat() }

            // Browse bucket: flat list of EVERY match (its Review Group is the same).
            if !config.grouped {
                let newest = Array(assets.suffix(previewLimit).reversed()).map(\.localIdentifier)
                return CategoryStat(previewIDs: newest, count: assets.count,
                                    totalKB: assets.reduce(0) { $0 + Self.realBytesKB($1) })
            }

            // Grouped: cluster exactly like the detail scan, count only clustered photos.
            let clusters = await Self.clustersAsync(config: config, assets: assets)
            var count = 0, totalKB = 0, reclaimableKB = 0, reclaimableCount = 0
            for c in clusters {
                count += c.count
                for (idx, a) in c.enumerated() {
                    let kb = Self.realBytesKB(a)
                    totalKB += kb
                    if idx != 0 { reclaimableKB += kb; reclaimableCount += 1 }  // best = idx 0
                }
            }
            let previews = Array(clusters.reversed().flatMap { $0 }.prefix(previewLimit)).map(\.localIdentifier)
            return CategoryStat(previewIDs: previews, count: count, totalKB: totalKB,
                                reclaimableKB: reclaimableKB, reclaimableCount: reclaimableCount,
                                groupCount: clusters.count)
        }.value
    }

    // `sinceDays`: only include assets created within the last N days (nil = all).
    // `largestFirst`: sort the resulting groups by total byte size desc/asc.
    //
    // One-shot scan used by Duplicates, videos and flat browse buckets. Similar
    // photos/screenshots use detectSimilarGroupsStreaming instead. Clustering is
    // TIME-based (bursts shot close together) — instant and iCloud-safe, unlike
    // Vision feature prints which needed a per-photo thumbnail that stalled.
    func detectSimilarGroups(
        config: DetectionConfig = DetectionConfig(),
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

        // 2. Cluster via the SHARED policy (identical to the Home card scan + the
        // streaming scan) so a category's groups never disagree across screens.
        let clusters = await Task.detached(priority: .userInitiated) {
            await Self.clustersAsync(config: config, assets: assets)
        }.value

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

    // Single clustering policy shared by the Home card scan (categoryScan), the
    // streaming Similar scan, and the one-shot detail scan — so a category's photo
    // count / size is IDENTICAL on the Home card and inside Review Group. Returns
    // only clusters of >=2 (a lone photo isn't "similar"); assets must be in date
    // order. Time-window grouping for Similar/videos (Duplicates take the async
    // content-hash path in `clustersAsync`; the exact-byte branch here is a fallback).
    nonisolated static func clusters(config: DetectionConfig, assets: [PHAsset]) -> [[PHAsset]] {
        if config.exactDuplicates { return exactDuplicateClusters(assets) }
        if config.mediaType == .video { return timeWindowClusters(assets, window: 60) }
        return timeWindowClusters(assets, window: 20)
    }

    // Async entry point — same as `clusters` but Duplicates use CONTENT matching
    // (perceptual hash), which needs to load a tiny thumbnail per asset. Similar and
    // videos stay on the instant metadata-only time-window path.
    nonisolated static func clustersAsync(config: DetectionConfig, assets: [PHAsset]) async -> [[PHAsset]] {
        if config.exactDuplicates { return await duplicateClusters(assets) }
        return clusters(config: config, assets: assets)
    }

    // Content-based duplicate clustering. Groups photos that look the SAME via a
    // 64-bit perceptual hash (dHash) of a TINY 9×8 thumbnail — so a re-saved /
    // re-compressed / resized copy lands with its original even though its bytes
    // differ. Tiny local thumbnails load fast and exist even for iCloud-optimized
    // photos (it's what the Photos grid shows), so this never stalls the way the
    // old Vision feature-print did. Falls back to the exact-byte signature when a
    // thumbnail can't be produced. Hashes run in parallel and are cached.
    nonisolated static func duplicateClusters(_ assets: [PHAsset]) async -> [[PHAsset]] {
        let maxConcurrent = 12
        var keyed: [(PHAsset, String)] = []
        await withTaskGroup(of: (PHAsset, String?).self) { group in
            var next = 0
            while next < min(maxConcurrent, assets.count) {
                let a = assets[next]; next += 1
                group.addTask { (a, await Self.duplicateKey(a)) }
            }
            while let (asset, key) = await group.next() {
                if let key { keyed.append((asset, key)) }
                if next < assets.count {
                    let a = assets[next]; next += 1
                    group.addTask { (a, await Self.duplicateKey(a)) }
                }
            }
        }
        var buckets: [String: [PHAsset]] = [:]
        for (a, key) in keyed { buckets[key, default: []].append(a) }
        return buckets.values
            .filter { $0.count >= 2 }
            .map { $0.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) } }
    }

    // Visual fingerprint key for an asset: the perceptual hash if we can render a
    // thumbnail, else the exact-byte signature, else nil (excluded — never grouped
    // by the dimension estimate).
    private nonisolated static func duplicateKey(_ asset: PHAsset) async -> String? {
        if let h = await perceptualHash(asset) { return "dh\(h)" }
        if let bytes = realBytesExact(asset) { return "by\(asset.pixelWidth)x\(asset.pixelHeight)-\(bytes)" }
        return nil
    }

    // dHash: render the asset into a 9×8 grayscale buffer, then for each row emit a
    // bit per adjacent-pixel comparison (left brighter than right) → 64 bits. Robust
    // to brightness / compression, so true duplicates collapse to the same hash.
    private nonisolated(unsafe) static var hashCacheStore: [String: UInt64] = [:]
    private nonisolated static func cachedHash(_ id: String) -> UInt64? {
        byteCacheLock.lock(); defer { byteCacheLock.unlock() }
        return hashCacheStore[id]
    }
    private nonisolated static func storeHash(_ id: String, _ hash: UInt64) {
        byteCacheLock.lock(); defer { byteCacheLock.unlock() }
        hashCacheStore[id] = hash
    }
    private nonisolated static func perceptualHash(_ asset: PHAsset) async -> UInt64? {
        let id = asset.localIdentifier
        if let cached = cachedHash(id) { return cached }

        guard let cg = await smallCGImage(asset) else { return nil }
        let w = 9, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hash: UInt64 = 0, bit = 0
        for row in 0..<h {
            for col in 0..<(w - 1) {
                if pixels[row * w + col] > pixels[row * w + col + 1] { hash |= (UInt64(1) << UInt64(bit)) }
                bit += 1
            }
        }
        storeHash(id, hash)
        return hash
    }

    // Tiny LOCAL thumbnail (no iCloud wait). Returns the first frame delivered.
    private nonisolated static func smallCGImage(_ asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .fastFormat
            opts.resizeMode = .fast
            opts.isSynchronous = false
            opts.isNetworkAccessAllowed = false   // tiny grid thumbnail is always local → never stalls
            nonisolated(unsafe) var resumed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 32, height: 32),
                contentMode: .aspectFit, options: opts
            ) { image, _ in
                if resumed { return }; resumed = true
                cont.resume(returning: image?.cgImage)
            }
        }
    }

    // MARK: - Chat detection (filename match)

    // true = this image is a chat photo (filename matched a chat app). Cached per asset
    // AND persisted to disk so the resource read runs once per image, not every launch.
    private nonisolated(unsafe) static var chatCacheStore: [String: Bool] = [:]
    private nonisolated(unsafe) static var chatCacheLoaded = false
    private nonisolated static let chatCacheURL: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("chat_classify_cache.json")

    private nonisolated static func loadChatCacheIfNeeded() {
        byteCacheLock.lock(); defer { byteCacheLock.unlock() }
        guard !chatCacheLoaded else { return }
        chatCacheLoaded = true
        if let data = try? Data(contentsOf: chatCacheURL),
           let dict = try? JSONDecoder().decode([String: Bool].self, from: data) {
            chatCacheStore = dict
        }
    }
    private nonisolated static func saveChatCache() {
        byteCacheLock.lock(); let snapshot = chatCacheStore; byteCacheLock.unlock()
        // Encode + write off the main thread (this is called from the MainActor scan
        // loop); atomic write + last-writer-wins is fine for a derived cache.
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: chatCacheURL, options: .atomic)
            }
        }
    }
    private nonisolated static func cachedChat(_ id: String) -> Bool? {
        loadChatCacheIfNeeded()
        byteCacheLock.lock(); defer { byteCacheLock.unlock() }
        return chatCacheStore[id]
    }
    private nonisolated static func storeChat(_ id: String, _ v: Bool) {
        byteCacheLock.lock(); defer { byteCacheLock.unlock() }
        chatCacheStore[id] = v
    }

    // Cheap metadata pre-filter (no resource read): a geotagged / Live / Portrait /
    // Panorama / HDR photo is a camera capture, never a saved chat image — skip it
    // before paying the filename round-trip. Saved chat media has none of these.
    private nonisolated static func isObviouslyCamera(_ asset: PHAsset) -> Bool {
        if asset.location != nil { return true }   // geotagged → taken by a camera
        let cameraOnly: PHAssetMediaSubtype = [.photoLive, .photoPanorama, .photoHDR, .photoDepthEffect]
        return !asset.mediaSubtypes.isDisjoint(with: cameraOnly)
    }

    /// Decide if an image is a chat photo by its ORIGINAL FILENAME — chat apps save
    /// media with telltale names. ~100× cheaper than OCR (one resource metadata read,
    /// no thumbnail / Vision), so it scales to large libraries. Cached + persisted.
    /// NOTE: catches SAVED chat media (WhatsApp, WeChat, …), NOT chat screenshots
    /// (named IMG_xxxx, no app marker — undetectable from metadata).
    nonisolated static func isChatImage(_ asset: PHAsset) async -> Bool {
        let id = asset.localIdentifier
        if let c = cachedChat(id) { return c }
        if isObviouslyCamera(asset) { storeChat(id, false); return false }
        let result = matchesChatPattern(originalFilename(asset))
        storeChat(id, result)
        return result
    }

    // First resource's original filename (the round-trip). Caches the byte size from
    // the SAME read so chat detection and size labels don't pay two Photos round-trips.
    private nonisolated(unsafe) static var nameCacheStore: [String: String] = [:]
    private nonisolated static func originalFilename(_ asset: PHAsset) -> String {
        let id = asset.localIdentifier
        byteCacheLock.lock(); let cached = nameCacheStore[id]; byteCacheLock.unlock()
        if let cached { return cached }

        var name = ""; var bytes = -1
        for r in PHAssetResource.assetResources(for: asset) {
            if name.isEmpty { name = r.originalFilename }
            if bytes < 0, let sz = r.value(forKey: "fileSize") as? Int, sz > 0 { bytes = sz }
        }
        byteCacheLock.lock()
        nameCacheStore[id] = name
        if byteCacheStore[id] == nil { byteCacheStore[id] = bytes }   // size is free here
        byteCacheLock.unlock()
        return name
    }

    // Distinctive per-app markers in a saved filename: WhatsApp `IMG-…-WA0001`,
    // WeChat `mmexport…`/`wx_camera…`, KakaoTalk, Viber, Telegram, Signal, LINE.
    private nonisolated static func matchesChatPattern(_ filename: String) -> Bool {
        guard !filename.isEmpty else { return false }
        let n = filename.lowercased()
        let markers = ["mmexport", "wx_camera", "kakaotalk", "viber", "telegram", "signal-", "line_"]
        if markers.contains(where: { n.contains($0) }) { return true }
        // WhatsApp variants: IMG-/VID-/STK-/PTT- … "-wa" immediately followed by a digit.
        if let r = n.range(of: "-wa"), r.upperBound < n.endIndex, n[r.upperBound].isNumber { return true }
        // Messenger / Facebook save received media as a 32-char hex (MD5) basename,
        // e.g. "80f6941241f39ef64630d1b250a23c86.jpeg" — camera/screenshots never do.
        let base = (n as NSString).deletingPathExtension
        if base.count == 32 && base.allSatisfy({ $0.isHexDigit }) { return true }
        return false
    }

    /// Keep only images classified as chats (parallel OCR, bounded, cached).
    /// Order-preserving. Used by the Home card scan (count/size).
    nonisolated static func filterChatImages(_ assets: [PHAsset]) async -> [PHAsset] {
        var keep: [(Int, PHAsset)] = []
        await withTaskGroup(of: (Int, PHAsset, Bool).self) { group in
            var next = 0
            let maxConcurrent = 4                   // OCR is CPU-heavy; don't flood
            while next < min(maxConcurrent, assets.count) {
                let i = next, a = assets[i]; next += 1
                group.addTask { (i, a, await Self.isChatImage(a)) }
            }
            while let (i, a, isChat) = await group.next() {
                if isChat { keep.append((i, a)) }
                if next < assets.count {
                    let j = next, b = assets[j]; next += 1
                    group.addTask { (j, b, await Self.isChatImage(b)) }
                }
            }
        }
        saveChatCache()   // persist OCR verdicts so this never re-runs for these assets
        return keep.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private nonisolated static func buildFlatGroup(_ assets: [PHAsset], noun: String) -> PHAssetGroup {
        let sizes = assets.map { Self.realBytesKB($0) }
        return PHAssetGroup(title: "\(assets.count) \(noun)", assets: assets, sizesKB: sizes, bestMatchIndex: -1)
    }

    /// Streams chat images: OCR every image (newest first, parallel, pre-filtered)
    /// and emit each recognised chat photo in small batches so the review list fills
    /// as they're found, reporting scan progress per image. Verdicts persist to disk.
    func detectChatImagesStreaming(
        config: DetectionConfig,
        sinceDays: Int? = nil,
        batchSize: Int = 6,
        onProgress: @MainActor @escaping (_ scanned: Int, _ total: Int) -> Void,
        onBatch: @MainActor @escaping ([PHAssetGroup]) -> Void
    ) async {
        guard authStatus.canRead else { onProgress(0, 0); return }
        let shots: [PHAsset] = await Task.detached(priority: .userInitiated) {
            Self.matchingAssets(config: config, sinceDays: sinceDays, recentFirst: true, limit: nil)
        }.value
        let total = shots.count
        guard total > 0 else { onProgress(0, 0); return }
        onProgress(0, total)

        var scanned = 0
        var pending: [PHAsset] = []
        func flush() async {
            guard !pending.isEmpty else { return }
            let chunk = pending; pending = []
            let g = await Task.detached(priority: .userInitiated) { Self.buildFlatGroup(chunk, noun: config.groupNoun) }.value
            onBatch([g])
        }
        await withTaskGroup(of: (PHAsset, Bool).self) { group in
            var next = 0
            let maxConcurrent = 4
            while next < min(maxConcurrent, shots.count) {
                let a = shots[next]; next += 1
                group.addTask { (a, await Self.isChatImage(a)) }
            }
            while let (asset, isChat) = await group.next() {
                if Task.isCancelled { Self.saveChatCache(); return }
                scanned += 1
                if isChat { pending.append(asset) }
                if pending.count >= batchSize { await flush() }
                // Persist verdicts periodically so a mid-scan quit doesn't waste OCR.
                if scanned % 100 == 0 { Self.saveChatCache() }
                onProgress(scanned, total)
                if next < shots.count {
                    let a = shots[next]; next += 1
                    group.addTask { (a, await Self.isChatImage(a)) }
                }
            }
        }
        Self.saveChatCache()
        if Task.isCancelled { return }
        await flush()
    }

    // Per-asset EXACT byte size cache (-1 = no real size, only the dimension
    // estimate). `PHAssetResource.assetResources(for:)` is a slow Photos round-trip
    // and Home re-scans every category on each appearance, so each asset's size is
    // fetched once for its lifetime. Both the size labels and the duplicate
    // signature read this.
    private nonisolated(unsafe) static var byteCacheStore: [String: Int] = [:]
    private nonisolated static let byteCacheLock = NSLock()

    /// Streams Similar/Similar-Screenshots groups over the WHOLE gallery, newest
    /// first, in batches — the caller shows the review screen immediately and appends
    /// groups as each batch is processed. Uses fast TIME-WINDOW clustering (photos
    /// shot close in time = bursts/retakes), NOT Vision: no per-photo thumbnail load,
    /// so it's instant AND works for iCloud-optimized photos (which often can't
    /// produce a local thumbnail to feature-print, which is why Vision stalled).
    func detectSimilarGroupsStreaming(
        config: DetectionConfig,
        sinceDays: Int? = nil,
        groupsPerBatch: Int = 8,
        onProgress: @MainActor @escaping (_ scanned: Int, _ total: Int) -> Void,
        onBatch: @MainActor @escaping ([PHAssetGroup]) -> Void
    ) async {
        guard authStatus.canRead else { onProgress(0, 0); return }

        // Cluster the WHOLE library ONCE using the shared policy — IDENTICAL to the
        // Home card scan, so the header count/size here matches the Similar card
        // exactly. Time-window clustering is O(n) instant; only the per-asset real
        // sizes are slow, so we defer those to the per-batch emit below and the
        // groups still appear progressively (newest first).
        let clusters: [[PHAsset]] = await Task.detached(priority: .userInitiated) {
            let all = Self.matchingAssets(config: config, sinceDays: sinceDays, recentFirst: false, limit: nil)
            return Array((await Self.clustersAsync(config: config, assets: all)).reversed())  // newest groups first
        }.value
        let total = clusters.reduce(0) { $0 + $1.count }
        guard total > 0 else { onProgress(0, 0); return }
        onProgress(0, total)

        var scanned = 0
        var i = 0
        while i < clusters.count {
            if Task.isCancelled { return }
            let slice = Array(clusters[i..<min(i + groupsPerBatch, clusters.count)])
            i += groupsPerBatch
            let built: [PHAssetGroup] = await Task.detached(priority: .userInitiated) {
                slice.map { c in
                    let sizes = c.map { Self.realBytesKB($0) }
                    return PHAssetGroup(title: "\(c.count) \(config.groupNoun)",
                                        assets: c, sizesKB: sizes, bestMatchIndex: 0)
                }
            }.value
            if Task.isCancelled { return }
            scanned += built.reduce(0) { $0 + $1.assets.count }
            onProgress(scanned, total)
            onBatch(built)
        }
    }

    /// EXACT on-disk byte size from the asset's `PHAssetResource`, or nil when only
    /// the dimension ESTIMATE is available. nil is critical for duplicate detection:
    /// the estimate (`pixelWidth*pixelHeight*3/1024`) is identical for every photo of
    /// the same dimensions, so using it as a signature falsely marks thousands of
    /// distinct same-size photos as duplicates. Cached.
    nonisolated static func realBytesExact(_ asset: PHAsset) -> Int? {
        let id = asset.localIdentifier
        byteCacheLock.lock(); let cached = byteCacheStore[id]; byteCacheLock.unlock()
        if let cached { return cached < 0 ? nil : cached }

        var bytes = -1
        for resource in PHAssetResource.assetResources(for: asset) {
            if let size = resource.value(forKey: "fileSize") as? Int, size > 0 { bytes = size; break }
        }
        byteCacheLock.lock(); byteCacheStore[id] = bytes; byteCacheLock.unlock()
        return bytes < 0 ? nil : bytes
    }

    /// Real on-disk size in KB, falling back to the dimension estimate FOR DISPLAY
    /// when the exact size is unavailable. Never use this as a duplicate signature —
    /// use `realBytesExact` (which returns nil instead of a degenerate estimate).
    nonisolated static func realBytesKB(_ asset: PHAsset) -> Int {
        if let bytes = realBytesExact(asset) { return bytes / 1024 }
        return Int(asset.estimatedSizeKB)
    }

    /// Exact-duplicate clustering WITHOUT Vision: group assets that share the SAME
    /// dimensions AND the SAME exact byte count — a strong "identical file" signal,
    /// O(n). Assets with no real byte size (estimate-only, e.g. some iCloud-optimized
    /// photos) are SKIPPED so the dimension estimate can't falsely group every
    /// same-size photo into one giant "duplicate" pile. ≥2 per cluster, oldest first.
    nonisolated static func exactDuplicateClusters(_ assets: [PHAsset]) -> [[PHAsset]] {
        var buckets: [String: [PHAsset]] = [:]
        for a in assets {
            guard let bytes = realBytesExact(a) else { continue }   // no real size → not a duplicate candidate
            let key = "\(a.pixelWidth)x\(a.pixelHeight)-\(bytes)"
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
