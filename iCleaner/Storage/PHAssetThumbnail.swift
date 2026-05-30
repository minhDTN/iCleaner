import SwiftUI
import Photos

// Async PHAsset thumbnail loader. Re-fetches when `localIdentifier` changes.
// Falls back to a neutral grey placeholder while loading.
//
// `targetSize` is in points — PHImageManager handles scale internally.
// Uses `.fastFormat` for a single callback (good enough for list thumbnails
// at 160×160; switch to `.opportunistic` if grid sizes grow past 400pt).
struct PHAssetThumbnail: View {
    let localIdentifier: String
    let targetSize: CGSize

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: 0xE2E8F0)
            }
        }
        .task(id: localIdentifier) {
            image = await Self.loadThumbnail(localIdentifier: localIdentifier, targetSize: targetSize)
        }
    }

    private static func loadThumbnail(localIdentifier: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            return nil
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isSynchronous = false
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

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
