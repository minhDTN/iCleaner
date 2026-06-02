import SwiftUI
import Photos
import AVKit

// Figma `2008:31427` (preview image). Single-item full-screen preview opened by
// tapping any photo/video in a review group. Shows just that one item (no
// swiping through the whole section). Delete (X, red) and Keep (heart, green)
// float at the vertical centre over the left/right edges of the media, matching
// the design. A Vault button sits centred at the bottom.
//
// Delete marks the item selected (the review screen's Delete CTA executes the
// real PHPhotoLibrary delete); Keep clears the selection. Either dismisses.
struct PhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var group: SimilarGroup
    let index: Int

    @State private var dragOffset: CGSize = .zero

    private var photo: SimilarPhoto? {
        guard index >= 0, index < group.photos.count else { return nil }
        return group.photos[index]
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
            }

            if let photo {
                mediaCard(for: photo)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 100)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.textBlack)
                    .frame(width: 24, height: 24)
            }
            Spacer()
            Color.clear.frame(width: 24, height: 24)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .padding(.top, 44)
    }

    // MARK: - Media card with side action buttons

    private func mediaCard(for photo: SimilarPhoto) -> some View {
        // No filler background — the media fits its own aspect ratio. Swipe left
        // → Delete, right → Keep, with a tint + indicator following the drag.
        mediaContent(for: photo)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { dragIndicator }
            .offset(x: dragOffset.width, y: dragOffset.height * 0.15)
            .rotationEffect(.degrees(Double(dragOffset.width / 25)))
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        let threshold: CGFloat = 110
                        if value.translation.width < -threshold {
                            decide(keep: false)
                        } else if value.translation.width > threshold {
                            decide(keep: true)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )
            // Delete + Keep float at vertical centre, inset from the media edges.
            .overlay(alignment: .leading) {
                actionButton(asset: "Clean/ic_delete_x", bg: Color(hex: 0xBA1A1A)) {
                    decide(keep: false)
                }
                .padding(.leading, 20)
            }
            .overlay(alignment: .trailing) {
                actionButton(asset: "Clean/ic_keep", bg: AppColor.success) {
                    decide(keep: true)
                }
                .padding(.trailing, 20)
            }
            .overlay(alignment: .bottom) {
                actionButton(asset: "Clean/ic_vault", bg: Color(hex: 0x004AC6)) {
                    sendToVault()
                }
                .offset(y: 32)
            }
    }

    // DELETE / KEEP badge that fades in as the user drags.
    @ViewBuilder
    private var dragIndicator: some View {
        let w = dragOffset.width
        if w < -20 {
            badge(text: "DELETE", color: Color(hex: 0xBA1A1A))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(16)
                .opacity(Double(min(1, -w / 100)))
        } else if w > 20 {
            badge(text: "KEEP", color: AppColor.success)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .opacity(Double(min(1, w / 100)))
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.custom("Inter-SemiBold", size: 20))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color, lineWidth: 4)
                    .background(Color(hex: 0xFAF8FF).opacity(0.2))
            )
    }

    @ViewBuilder
    private func mediaContent(for photo: SimilarPhoto) -> some View {
        if let assetID = photo.assetID {
            PreviewMedia(localIdentifier: assetID)
        } else {
            LinearGradient(colors: [Color(hex: 0xDBEAFE), Color(hex: 0xBFDBFE)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func actionButton(asset: String, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(bg))
                .shadow(color: Color(hex: 0x0F172A).opacity(0.15), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Decisions

    private func decide(keep: Bool) {
        if index < group.photos.count {
            group.photos[index].isSelected = (!keep && index != group.bestMatchIndex)
        }
        dismiss()
    }

    private func sendToVault() {
        // Vault move is a Phase 6 integration point — for now just dismiss.
        // TODO: wire VaultService import.
        dismiss()
    }
}

// MARK: - Media loader (image or video)

private struct PreviewMedia: View {
    let localIdentifier: String
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isVideo = false

    var body: some View {
        Group {
            if isVideo, let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(AppColor.brandPrimary)
            }
        }
        .task(id: localIdentifier) { await load() }
    }

    private func load() async {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return }
        if asset.mediaType == .video {
            isVideo = true
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .automatic
            player = await withCheckedContinuation { (cont: CheckedContinuation<AVPlayer?, Never>) in
                PHImageManager.default().requestPlayerItem(forVideo: asset, options: opts) { item, _ in
                    cont.resume(returning: item.map(AVPlayer.init(playerItem:)))
                }
            }
        } else {
            isVideo = false
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            opts.resizeMode = .exact
            image = await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: CGSize(width: 1200, height: 1400),
                    contentMode: .aspectFit,
                    options: opts
                ) { img, _ in cont.resume(returning: img) }
            }
        }
    }
}
