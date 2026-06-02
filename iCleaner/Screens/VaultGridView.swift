import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import LibEarnMoneyIOS

// Figma `2010:2568` (private — empty/grid state).
// LazyVGrid 3 cols of encrypted vault items + sticky FAB "Add More" bottom-right.
// When @Query returns empty → friendly empty illustration overlay.
struct VaultGridView: View {
    @Bindable var vault: VaultService
    @Query(sort: \VaultItem.addedAt, order: .reverse) private var items: [VaultItem]
    @Environment(\.modelContext) private var modelContext

    @State private var showAddSheet: Bool = false
    @State private var showPhotosPicker: Bool = false
    @State private var showCamera: Bool = false
    @State private var showChangePasscode: Bool = false
    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var previewItem: VaultItem?
    @State private var importing: Bool = false
    @State private var importError: String?

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 11), count: 2)

    var body: some View {
        VStack(spacing: 0) {
            VaultHeader(title: "Private Vault", onChangePass: { showChangePasscode = true })

            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [Color(hex: 0xFAF8FF), Color(hex: 0xFFFFFF)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)

                if items.isEmpty && !importing {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    grid
                }

                fab
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)

                if importing {
                    importingOverlay
                }
            }
            .bottomChromeInset()
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showChangePasscode) {
            ChangePasscodeView(vault: vault)
        }
        .confirmationDialog("Add to Vault", isPresented: $showAddSheet, titleVisibility: .hidden) {
            Button("Add from Camera") { showCamera = true }
            Button("Add from Photos") { showPhotosPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $pickerSelection,
            maxSelectionCount: 20,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: pickerSelection) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await importFromPicker(newItems) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { data, fileName in
                Task { await importImage(data: data, fileName: fileName) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $previewItem) { item in
            VaultPreviewView(vault: vault, item: item)
        }
        .alert("Couldn't import", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Subviews

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 11) {
                ForEach(items) { item in
                    VaultThumbnail(vault: vault, item: item)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(alignment: .topTrailing) { glassDot.padding(8) }
                        .onTapGesture { previewItem = item }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)  // room for FAB
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.brandPrimary)
            Text("No private photos yet")
                .font(.custom("Inter-Bold", size: 20))
                .foregroundStyle(AppColor.textPrimary)
            Text("Tap Add More to bring photos here.\nThey're encrypted AES-256 on this device only.")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // Decorative glass dot in each cell's top-right corner (Figma overlay).
    private var glassDot: some View {
        Circle()
            .fill(Color.black.opacity(0.1))
            .frame(width: 23, height: 23)
            .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.9))
    }

    private var fab: some View {
        Button(action: { showAddSheet = true }) {
            HStack(spacing: 8) {
                Image("Vault/ic_add_plus")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text("Add More")
                    .font(.custom("Inter-Bold", size: 16))
                    .tracking(16 * -0.025)
            }
            .foregroundStyle(Color(hex: 0xEEEFFF))
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(AppColor.brandPrimary)
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 10)
            )
        }
        .buttonStyle(.plain)
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white).scaleEffect(1.4)
                Text("Encrypting…")
                    .font(.custom("Inter-SemiBold", size: 14))
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.6))
            )
        }
    }

    // MARK: - Import

    private func importFromPicker(_ picks: [PhotosPickerItem]) async {
        importing = true
        defer {
            importing = false
            pickerSelection = []
        }
        for pick in picks {
            do {
                // Raw bytes regardless of type; classify by supplied content types.
                guard let data = try await pick.loadTransferable(type: Data.self) else { continue }
                let isVideo = pick.supportedContentTypes.contains { $0.conforms(to: .movie) }
                let stamp = String(UUID().uuidString.prefix(6))
                if isVideo {
                    try saveImportedVideo(data: data, fileName: pick.itemIdentifier ?? "Video-\(stamp)")
                } else {
                    try saveImported(data: data, fileName: pick.itemIdentifier ?? "Photo-\(stamp)")
                }
            } catch {
                importError = (error as NSError).localizedDescription
                return
            }
        }
    }

    private func importImage(data: Data, fileName: String) async {
        importing = true
        defer { importing = false }
        do {
            try saveImported(data: data, fileName: fileName)
        } catch {
            importError = (error as NSError).localizedDescription
        }
    }

    private func saveImported(data: Data, fileName: String) throws {
        guard let img = UIImage(data: data) else {
            throw NSError(domain: "iCleaner", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't read image data."])
        }
        let item = VaultItem(
            sizeBytes: data.count,
            fileName: fileName.isEmpty ? "Photo" : fileName,
            mimeType: "image/jpeg",
            pixelWidth: Int(img.size.width * img.scale),
            pixelHeight: Int(img.size.height * img.scale)
        )
        try vault.writeEncrypted(data, for: item.id)
        modelContext.insert(item)
        try? modelContext.save()
    }

    private func saveImportedVideo(data: Data, fileName: String) throws {
        // Video dimensions aren't needed for the grid (we show a play badge), so
        // store 0×0. mimeType drives the play overlay + video preview path.
        let item = VaultItem(
            sizeBytes: data.count,
            fileName: fileName.isEmpty ? "Video" : fileName,
            mimeType: "video/quicktime",
            pixelWidth: 0,
            pixelHeight: 0
        )
        try vault.writeEncrypted(data, for: item.id)
        modelContext.insert(item)
        try? modelContext.save()
    }
}

// MARK: - Thumbnail

private struct VaultThumbnail: View {
    let vault: VaultService
    let item: VaultItem
    @State private var image: UIImage?

    private var isVideo: Bool { item.mimeType.hasPrefix("video") }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: 0xE2E8F0)
                    .overlay(
                        Image(systemName: isVideo ? "video.fill" : "lock.fill")
                            .foregroundStyle(AppColor.textMuted)
                    )
            }
        }
        .overlay {
            if isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 3)
            }
        }
        .task(id: item.id) {
            image = await Self.loadThumbnail(vault: vault, item: item, isVideo: isVideo)
        }
    }

    // Decrypt off the main thread so the grid scrolls smoothly. Capture only
    // `id` (Sendable) before crossing actor boundary — VaultItem isn't Sendable.
    private static func loadThumbnail(vault: VaultService, item: VaultItem, isVideo: Bool) async -> UIImage? {
        let itemID = item.id
        let fileName = item.fileName
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? vault.readDecrypted(for: itemID) else { return nil }
            if isVideo {
                return Self.videoThumbnail(from: data, fileName: fileName)
            }
            guard let img = UIImage(data: data) else { return nil }
            // Downscale to ~256pt longest edge — playbook §4 perf principle.
            return img.preparingThumbnail(of: CGSize(width: 256, height: 256))
        }.value
    }

    // Decode a poster frame from decrypted video bytes via a temp file.
    nonisolated private static func videoThumbnail(from data: Data, fileName: String) -> UIImage? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-thumb-\(UUID().uuidString.prefix(6)).mov")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard (try? data.write(to: tmp)) != nil else { return nil }
        let asset = AVURLAsset(url: tmp)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 256, height: 256)
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 0, preferredTimescale: 60), actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Camera capture bridge (UIImagePickerController)

private struct CameraCapture: UIViewControllerRepresentable {
    var onPicked: (Data, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.allowsEditing = false
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onPicked: (Data, String) -> Void
        init(onPicked: @escaping (Data, String) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.92) else { return }
            onPicked(data, "Camera-\(Int(Date().timeIntervalSince1970)).jpg")
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
