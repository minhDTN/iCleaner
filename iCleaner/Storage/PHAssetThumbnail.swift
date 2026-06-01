import SwiftUI
import Photos

// Async PHAsset thumbnail loader. Re-fetches when `localIdentifier` changes.
// Falls back to a neutral grey placeholder while loading.
//
// Quality: `.highQualityFormat` + `.resizeMode .exact` so thumbnails are sharp
// (not the blurry low-res frame `.fastFormat` returns first). `targetSize` is in
// POINTS — we multiply by the screen scale so PHImageManager renders at native
// pixel density.
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
                let px = CGSize(width: targetSize.width * displayScale,
                                height: targetSize.height * displayScale)
                image = await Self.loadThumbnail(localIdentifier: localIdentifier, targetSize: px)
            }
    }

    private static func loadThumbnail(localIdentifier: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            return nil
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true

            // `.highQualityFormat` delivers exactly one (final) callback, so a
            // single resume is safe.
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                cont.resume(returning: image)
            }
        }
    }
}
