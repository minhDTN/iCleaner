import SwiftUI
import SwiftData
import Photos
import AVKit

// Figma `2010:2345` (private preview). White bg. Top header (glass white 90% +
// blur 24) with close + lock badge. Meta data overlay top-left (rgba(243,244,246,0.8)
// + blur 12, Inter Regular 14/20 #1F2937). Bottom footer (glass + blur 16) with
// Share + Delete actions (58×58 padded buttons).
//
// Image decrypts via VaultService.readDecrypted off the main actor. Delete
// removes the SwiftData row + the encrypted blob file.
struct VaultPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let vault: VaultService
    let item: VaultItem

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var decryptedURL: URL?   // temp plaintext file (video / share)
    @State private var showDeleteConfirm: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var loadError: String?

    private var isVideo: Bool { item.mimeType.hasPrefix("video") }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Decrypted media
            Group {
                if isVideo, let player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                        .onDisappear { player.pause() }
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Text("Decrypting…")
                            .font(.custom("Inter-SemiBold", size: 14))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                topBar
                metaOverlay
                Spacer()
                bottomBar
            }
        }
        .task { await loadMedia() }
        .onDisappear {
            // Clean up the temp plaintext file so decrypted media never lingers.
            if let url = decryptedURL { try? FileManager.default.removeItem(at: url) }
        }
        .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the encrypted copy from your vault.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = decryptedURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Decryption failed", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) { loadError = nil; dismiss() }
        } message: { Text(loadError ?? "") }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.9)))
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("AES-256 Encrypted")
                    .font(.custom("Inter-SemiBold", size: 11))
                    .tracking(11 * 0.05)
                    .textCase(.uppercase)
            }
            .foregroundStyle(AppColor.brandPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.white.opacity(0.9))
            )
            Spacer()
            Button(action: { showDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.danger)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.9)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var metaOverlay: some View {
        let dateStr = item.addedAt.formatted(date: .abbreviated, time: .shortened)
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateStr)
                Text("\(item.fileName) • \(sizeStr)")
            }
            .font(.custom("Inter-Regular", size: 13))
            .foregroundStyle(Color(hex: 0x1F2937))
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: 0xF3F4F6).opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
                    )
            )
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 98) {
            barButton(systemIcon: "square.and.arrow.up", label: "Share", action: prepareShare)
            barButton(systemIcon: "trash", label: "Delete", tint: AppColor.danger, action: { showDeleteConfirm = true })
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            Color.white.opacity(0.9)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func barButton(systemIcon: String, label: String, tint: Color = AppColor.brandPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemIcon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.custom("Inter-SemiBold", size: 11))
            }
            .foregroundStyle(tint)
            .frame(width: 58)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load

    // Decrypt to a temp file. Videos play from that file via AVPlayer; images
    // also load a UIImage for display. The temp file doubles as the share source
    // and is removed on disappear.
    private func loadMedia() async {
        let itemID = item.id
        let v = vault
        let video = isVideo
        let ext = video ? "mov" : "jpg"
        let result: (url: URL?, image: UIImage?)? = await Task.detached(priority: .userInitiated) {
            guard let data = try? v.readDecrypted(for: itemID) else { return nil }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("vault-open-\(itemID.uuidString).\(ext)")
            try? data.write(to: tmp, options: .atomic)
            return (tmp, video ? nil : UIImage(data: data))
        }.value

        guard let result, let url = result.url else {
            loadError = "Couldn't decrypt this file. It may be corrupted."
            return
        }
        decryptedURL = url
        if video {
            player = AVPlayer(url: url)
        } else {
            image = result.image
            if image == nil { loadError = "Couldn't decrypt this file. It may be corrupted." }
        }
    }

    // MARK: - Actions

    private func performDelete() {
        vault.deleteFile(for: item.id)
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }

    private func prepareShare() {
        // Share the already-decrypted temp file (works for both image + video).
        guard decryptedURL != nil else { return }
        showShareSheet = true
    }
}

// MARK: - Share sheet bridge

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
