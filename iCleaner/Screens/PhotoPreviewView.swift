import SwiftUI
import Photos
import AVKit

// Figma `2008:31427` (preview image). Full-screen swipe Keep/Delete viewer for a
// group's photos/videos. Swipe right or tap Keep (green) to keep, swipe left or
// tap Delete (red) to mark for deletion, tap Vault (blue) to send to vault.
// Drag shows a DELETE / KEEP indicator overlay. Advances to the next item until
// the group is exhausted, then dismisses.
//
// "Mark for deletion" here just flips the photo's isSelected in the bound group;
// the actual PHPhotoLibrary delete still happens via the review screen's Delete
// CTA. This keeps preview a fast triage tool, not a destructive one.
struct PhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var group: SimilarGroup
    @State private var index: Int
    @State private var dragOffset: CGSize = .zero

    init(group: Binding<SimilarGroup>, startIndex: Int) {
        self._group = group
        self._index = State(initialValue: startIndex)
    }

    private var current: SimilarPhoto? {
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

            if let current {
                card(for: current)
                    .padding(.horizontal, 14)
                    .padding(.top, 88)
                    .padding(.bottom, 120)
            }

            VStack {
                Spacer()
                actionBar
                    .padding(.bottom, 32)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
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
            Text("\(min(index + 1, group.photos.count)) / \(group.photos.count)")
                .font(.custom("Inter-SemiBold", size: 15))
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Color.clear.frame(width: 24, height: 24)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .padding(.top, 44)  // status bar
    }

    // MARK: - Card

    private func card(for photo: SimilarPhoto) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: 0xEDEDF9))

            mediaContent(for: photo)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Swipe indicators
            indicatorOverlay
        }
        .offset(x: dragOffset.width, y: dragOffset.height * 0.2)
        .rotationEffect(.degrees(Double(dragOffset.width / 20)))
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation }
                .onEnded { value in
                    let threshold: CGFloat = 100
                    if value.translation.width < -threshold {
                        decide(keep: false)
                    } else if value.translation.width > threshold {
                        decide(keep: true)
                    } else {
                        dragOffset = .zero
                    }
                }
        )
    }

    @ViewBuilder
    private func mediaContent(for photo: SimilarPhoto) -> some View {
        if let assetID = photo.assetID {
            PreviewMedia(localIdentifier: assetID)
        } else {
            // Mock fallback for previews.
            LinearGradient(colors: [Color(hex: 0xDBEAFE), Color(hex: 0xBFDBFE)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private var indicatorOverlay: some View {
        let dragging = dragOffset.width
        if dragging < -20 {
            indicator(text: "DELETE", color: Color(hex: 0xBA1A1A), align: .trailing)
                .opacity(Double(min(1, -dragging / 100)))
        } else if dragging > 20 {
            indicator(text: "KEEP", color: AppColor.success, align: .leading)
                .opacity(Double(min(1, dragging / 100)))
        }
    }

    private func indicator(text: String, color: Color, align: Alignment) -> some View {
        Text(text)
            .font(.custom("Inter-SemiBold", size: 20))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: 0xFAF8FF).opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(color, lineWidth: 4))
            )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity, alignment: align == .trailing ? .trailing : .leading)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack {
            actionButton(asset: "Clean/ic_delete_x", bg: Color(hex: 0xBA1A1A)) { decide(keep: false) }
            Spacer()
            actionButton(asset: "Clean/ic_vault", bg: Color(hex: 0x004AC6)) { sendToVault() }
            Spacer()
            actionButton(asset: "Clean/ic_keep", bg: AppColor.success) { decide(keep: true) }
        }
        .padding(.horizontal, 40)
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
                .shadow(color: Color(hex: 0x0F172A).opacity(0.05), radius: 20, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Decisions

    private func decide(keep: Bool) {
        if index < group.photos.count {
            // Delete decision → mark selected (review's Delete CTA executes later).
            // Keep decision → ensure not selected. Best Match stays kept.
            group.photos[index].isSelected = (!keep && index != group.bestMatchIndex)
        }
        advance()
    }

    private func sendToVault() {
        // Vault move is a Phase 6 integration point — for now treat like Keep so
        // triage flow stays usable. TODO: wire VaultService import.
        advance()
    }

    private func advance() {
        dragOffset = .zero
        if index + 1 < group.photos.count {
            index += 1
        } else {
            dismiss()
        }
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
