import SwiftUI
import SwiftData
import Photos
import AVKit

// Figma `2010:2345` (private preview). White screen: header (back + "Private
// Vault" + "AES-256 Encrypted" subtitle), metadata row (date + file • size), the
// decrypted media filling the middle, and a bottom bar with Share + Delete.
//
// Media decrypts via VaultService.readDecrypted off the main actor. Delete
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
        VStack(spacing: 0) {
            header
            metaRow
            mediaArea
            bottomBar
        }
        .background(AppColor.surfaceBackground.ignoresSafeArea())
        .task { await loadMedia() }
        .onDisappear {
            // Clean up the temp plaintext file so decrypted media never lingers.
            if let url = decryptedURL { try? FileManager.default.removeItem(at: url) }
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
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

    // MARK: - Header

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Private Vault")
                    .font(.custom("Inter-Bold", size: 18))
                    .foregroundStyle(Color(hex: 0x131B2E))
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("AES-256 Encrypted")
                        .font(.custom("Inter-Medium", size: 11))
                }
                .foregroundStyle(AppColor.brandPrimary)
            }
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColor.brandPrimary)
                        .frame(width: 40, height: 40, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Color.clear.frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(
            AppColor.surfaceBackground
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(hex: 0xB2B2B2)).frame(height: 1)
                }
        )
    }

    private var metaRow: some View {
        let dateStr = Self.dateString(item.addedAt)
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateStr)
                Text("\(item.fileName) • \(sizeStr)")
            }
            .font(.custom("Inter-Regular", size: 13))
            .foregroundStyle(Color(hex: 0x434655))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var mediaArea: some View {
        ZStack {
            Color(hex: 0x0F172A).opacity(0.03)
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
                        ProgressView().tint(AppColor.brandPrimary).scaleEffect(1.3)
                        Text("Decrypting…")
                            .font(.custom("Inter-SemiBold", size: 14))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            barButton(systemIcon: "square.and.arrow.up", label: "Share",
                      tint: AppColor.brandPrimary, action: prepareShare)
            Spacer()
            barButton(systemIcon: "trash", label: "Delete",
                      tint: AppColor.danger, action: { showDeleteConfirm = true })
            Spacer()
        }
        .padding(.vertical, 16)
        .background(
            AppColor.surfaceBackground
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(hex: 0xB2B2B2)).frame(height: 1)
                }
        )
    }

    private func barButton(systemIcon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemIcon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.custom("Inter-SemiBold", size: 12))
            }
            .foregroundStyle(tint)
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Format

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy • HH:mm"
        return f.string(from: date)
    }

    // MARK: - Load

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
