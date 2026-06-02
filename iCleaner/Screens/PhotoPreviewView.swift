import SwiftUI
import Photos
import AVKit

// Figma `2008:31427` (preview image) — extended to a browsable gallery: the
// tapped photo shows large with Delete (left) / Keep (right) / Vault (bottom)
// actions + swipe, and a filmstrip of EVERY photo in the group sits at the
// bottom (tap to jump, current ringed). Acting on a photo advances to the next
// one so the whole group can be reviewed without leaving the preview.
//
// Delete marks the item selected (the review screen's Delete CTA executes the
// real PHPhotoLibrary delete); Keep clears the selection.
struct PhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var group: SimilarGroup
    @State private var index: Int
    @State private var dragOffset: CGSize = .zero

    init(group: Binding<SimilarGroup>, index: Int) {
        self._group = group
        self._index = State(initialValue: index)
    }

    private var current: SimilarPhoto? {
        guard index >= 0, index < group.photos.count else { return nil }
        return group.photos[index]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let photo = current {
                mediaCard(for: photo)
                    .padding(.horizontal, 14)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
            filmstrip
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .background(Color.white.ignoresSafeArea())
        // Scenario: similar preview → bottom-anchored banner (banner_preview_similar).
        .safeAreaInset(edge: .bottom) { BannerAdView(adUnitID: AdUnits.bannerPreviewSimilar) }
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
            Text("\(index + 1) / \(group.photos.count)")
                .font(.custom("Inter-SemiBold", size: 15))
                .foregroundStyle(Color(hex: 0x0F0F0F))
            Spacer()
            Color.clear.frame(width: 24, height: 24)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .padding(.top, 44)
    }

    // MARK: - Media card with side action buttons

    private func mediaCard(for photo: SimilarPhoto) -> some View {
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
                .padding(.bottom, 12)
            }
            .id(index)  // reset drag transform when the photo changes
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

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(group.photos.enumerated()), id: \.element.id) { i, p in
                        thumb(p, isCurrent: i == index)
                            .id(i)
                            .onTapGesture { withAnimation { index = i } }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 60)
            .onChange(of: index) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
        }
    }

    private func thumb(_ p: SimilarPhoto, isCurrent: Bool) -> some View {
        Group {
            if let id = p.assetID {
                PHAssetThumbnail(localIdentifier: id, targetSize: CGSize(width: 160, height: 160))
            } else {
                LinearGradient(colors: [Color(hex: 0xDBEAFE), Color(hex: 0xBFDBFE)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isCurrent ? AppColor.brandPrimary : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if p.isSelected {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0xBA1A1A), .white)
                    .padding(2)
            }
        }
        .opacity(isCurrent ? 1 : 0.65)
    }

    // MARK: - Decisions

    private func decide(keep: Bool) {
        if index < group.photos.count {
            group.photos[index].isSelected = (!keep && index != group.bestMatchIndex)
        }
        advance()
    }

    // Move to the next photo so the group can be reviewed sequentially; dismiss
    // once the last one has been acted on.
    private func advance() {
        dragOffset = .zero
        if index + 1 < group.photos.count {
            withAnimation { index += 1 }
        } else {
            dismiss()
        }
    }

    private func sendToVault() {
        // Vault move is a Phase 6 integration point — for now just advance.
        // TODO: wire VaultService import.
        advance()
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
