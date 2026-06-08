import SwiftUI
import SwiftData
import Photos
import AVKit

// Figma `2010:2345` (private preview). Immersive gallery: the selected media fills
// the screen, with a glass header (back + "Private Vault" + "AES-256 Encrypted"),
// a metadata pill (date / file • size), a horizontal filmstrip of EVERY vault item
// (tap to switch; the active one has a blue ring), and a Share / Delete footer.
//
// Media decrypts via VaultService.readDecrypted off the main actor. Delete removes
// the SwiftData row + the encrypted blob, then moves to an adjacent item (or
// dismisses when the vault is empty).
struct VaultPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let vault: VaultService
    @State private var items: [VaultItem]
    @State private var currentID: UUID

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var decryptedURL: URL?
    @State private var showDeleteConfirm = false
    @State private var showShareSheet = false
    @State private var showChangePass = false
    @State private var loadError: String?

    init(vault: VaultService, items: [VaultItem], current: VaultItem) {
        self.vault = vault
        _items = State(initialValue: items)
        _currentID = State(initialValue: current.id)
    }

    private var current: VaultItem? { items.first { $0.id == currentID } }
    private var isVideo: Bool { current?.mimeType.hasPrefix("video") ?? false }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            mediaArea

            VStack(spacing: 0) {
                header
                metadataRow
                Spacer(minLength: 0)
                filmstrip
                footer
                // Scenario: image preview → bottom-anchored banner (banner_preview_image).
                BannerAdView(adUnitID: AdUnits.bannerPreviewImage)
            }
        }
        .task(id: currentID) { await loadMedia() }
        .onDisappear { cleanupTemp() }
        .confirmationDialog(L("vault.deleteItemTitle"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(L("common.delete"), role: .destructive) { performDelete() }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("vault.deleteItemBody"))
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = decryptedURL { ShareSheet(items: [url]) }
        }
        .fullScreenCover(isPresented: $showChangePass) {
            ChangePasscodeView(vault: vault)
        }
        .alert(L("vault.decryptFailTitle"), isPresented: Binding(
            get: { loadError != nil }, set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) { loadError = nil }
        } message: { Text(loadError ?? "") }
    }

    // MARK: - Media

    private var mediaArea: some View {
        Group {
            if isVideo, let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(AppColor.brandPrimary).scaleEffect(1.3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(L("vault.title"))
                    .font(.custom("Inter-SemiBold", size: 20))
                    .foregroundStyle(Color(hex: 0x111827))
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L("vault.aes"))
                        .font(.custom("Inter-SemiBold", size: 12))
                        .tracking(12 * 0.05)
                }
                .foregroundStyle(Color(hex: 0x4B5563))
            }
            HStack {
                Button(action: { dismiss() }) {
                    Image("Common/icon_back_vault_change_password")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .frame(width: 40, height: 40, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                // Change-passcode shortcut (Figma 2010:2382) — was a missing placeholder.
                Button(action: { showChangePass = true }) {
                    Image("Vault/ic_change_pass")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .foregroundStyle(Color(hex: 0x292D32))
                        .frame(width: 40, height: 40, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: 0xB2B2B2)).frame(height: 1)
        }
    }

    private var metadataRow: some View {
        HStack {
            if let cur = current {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.dateString(cur.addedAt))
                    Text("\(cur.fileName) • \(ByteCountFormatter.string(fromByteCount: Int64(cur.sizeBytes), countStyle: .file))")
                }
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(Color(hex: 0x1F2937))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: 0xF3F4F6).opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
                        )
                )
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { it in
                        let isCurrent = it.id == currentID
                        // No border (it clipped at the strip edge anyway) — the active
                        // item is shown just by staying full-opacity while the rest dim.
                        VaultThumbnail(vault: vault, item: it)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .opacity(isCurrent ? 1 : 0.5)
                            .id(it.id)
                            .onTapGesture { currentID = it.id }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 64)
            .padding(.vertical, 16)
            .onChange(of: currentID) { _, id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .background(Color.white)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 98) {
            footerButton(icon: "square.and.arrow.up", label: L("vault.share"),
                         tint: Color(hex: 0x374151), action: prepareShare)
            footerButton(icon: "trash", label: L("common.delete"),
                         tint: Color(hex: 0xDC2626), action: { showDeleteConfirm = true })
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(Color.white)
    }

    private func footerButton(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 18))
                Text(label)
                    .font(.custom("Inter-SemiBold", size: 12))
                    .tracking(12 * 0.05)
            }
            .foregroundStyle(tint)
            .frame(minWidth: 58)
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
        cleanupTemp()
        image = nil
        player = nil
        guard let cur = current else { return }
        let itemID = cur.id
        let video = cur.mimeType.hasPrefix("video")
        let ext = video ? "mov" : "jpg"
        let v = vault
        let result: (url: URL?, image: UIImage?)? = await Task.detached(priority: .userInitiated) {
            guard let data = try? v.readDecrypted(for: itemID) else { return nil }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("vault-open-\(itemID.uuidString).\(ext)")
            try? data.write(to: tmp, options: .atomic)
            return (tmp, video ? nil : UIImage(data: data))
        }.value

        // Ignore a result that arrived after the user already switched items.
        guard cur.id == currentID else { return }
        guard let result, let url = result.url else {
            loadError = L("vault.decryptFailBody")
            return
        }
        decryptedURL = url
        if video { player = AVPlayer(url: url) }
        else {
            image = result.image
            if image == nil { loadError = "Couldn't decrypt this file. It may be corrupted." }
        }
    }

    private func cleanupTemp() {
        if let url = decryptedURL { try? FileManager.default.removeItem(at: url); decryptedURL = nil }
    }

    // MARK: - Actions

    private func performDelete() {
        guard let cur = current, let idx = items.firstIndex(where: { $0.id == cur.id }) else { return }
        vault.deleteFile(for: cur.id)
        modelContext.delete(cur)
        try? modelContext.save()
        items.remove(at: idx)
        if items.isEmpty { dismiss(); return }
        currentID = items[min(idx, items.count - 1)].id
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
