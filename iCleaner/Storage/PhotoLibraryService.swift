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

    // `sinceDays`: only cluster photos created within the last N days (nil = all).
    // `largestFirst`: sort the resulting groups by total byte size descending
    //   (true) or ascending (false).
    func detectSimilarGroups(
        clusteringWindow: TimeInterval = 60,
        sinceDays: Int? = nil,
        largestFirst: Bool = true
    ) async -> [PHAssetGroup] {
        guard authStatus.canRead else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            var predicates = [NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)]
            if let sinceDays, let cutoff = Calendar.current.date(byAdding: .day, value: -sinceDays, to: Date()) {
                predicates.append(NSPredicate(format: "creationDate >= %@", cutoff as NSDate))
            }
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            let fetch = PHAsset.fetchAssets(with: options)

            // Time-window cluster: same pixel orientation AND creationDate within window.
            var clusters: [[PHAsset]] = []
            var currentCluster: [PHAsset] = []
            var lastDate: Date?
            var lastOrientation: (Int, Int)?

            fetch.enumerateObjects { asset, _, _ in
                let orientation = (asset.pixelWidth, asset.pixelHeight)
                let date = asset.creationDate ?? Date.distantPast
                let fitsCluster: Bool = {
                    guard let lastDate, let lastOrientation else { return true }
                    return abs(date.timeIntervalSince(lastDate)) <= clusteringWindow
                        && lastOrientation == orientation
                }()

                if fitsCluster {
                    currentCluster.append(asset)
                } else {
                    if currentCluster.count >= 2 { clusters.append(currentCluster) }
                    currentCluster = [asset]
                }
                lastDate = date
                lastOrientation = orientation
            }
            if currentCluster.count >= 2 { clusters.append(currentCluster) }

            // Sort groups by estimated total size per the filter.
            let sized = clusters.map { cluster -> (cluster: [PHAsset], bytes: Int) in
                (cluster, cluster.reduce(0) { $0 + Int($1.estimatedSizeKB) })
            }
            let ordered = sized.sorted { largestFirst ? $0.bytes > $1.bytes : $0.bytes < $1.bytes }

            return ordered.map { item in
                PHAssetGroup(
                    title: "\(item.cluster.count) Similar",
                    assets: item.cluster,
                    bestMatchIndex: 0  // first asset (oldest in window) wins as MVP
                )
            }
        }.value
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
