import SwiftUI
import Photos

// Async PHAsset thumbnail loader. Re-fetches when `localIdentifier` changes.
// Falls back to a neutral grey placeholder while loading.
//
// Delivery: `.opportunistic` streams TWO frames — the instant local low-res
// thumbnail first (so iCloud-optimized photos show immediately instead of a
// blank box), then the sharp high-res once it's rendered/downloaded. We update
// the view on each frame, so the grid never sits empty waiting on iCloud.
//
// Layout: fills its container edge-to-edge via an overlay + `.clipped()`, so the
// image never overflows the fixed card frame even at `.fill` content mode.
struct PHAssetThumbnail: View {
    let localIdentifier: String
    let targetSize: CGSize

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color(hex: 0xE2E8F0)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: localIdentifier) {
                image = nil
                let px = CGSize(width: targetSize.width * displayScale,
                                height: targetSize.height * displayScale)
                for await frame in Self.thumbnailStream(localIdentifier: localIdentifier, targetSize: px) {
                    image = frame
                }
            }
    }

    // Yields the low-res frame first, then the high-res. Finishes on the final
    // (non-degraded) callback, an error, or cancellation. Cancels the underlying
    // Photos request when the task is torn down (id change / scroll-away).
    private static func thumbnailStream(localIdentifier: String, targetSize: CGSize) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
                continuation.finish(); return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic   // local low-res first, then high-res
            options.isSynchronous = false
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true    // allow iCloud download for the sharp frame

            let requestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let image { continuation.yield(image) }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let failed = info?[PHImageErrorKey] != nil
                if !degraded || cancelled || failed { continuation.finish() }
            }
            continuation.onTermination = { @Sendable _ in
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }
}
