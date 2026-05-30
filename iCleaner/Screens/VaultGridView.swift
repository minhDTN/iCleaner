import SwiftUI
import SwiftData
import PhotosUI
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
    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var previewItem: VaultItem?
    @State private var importing: Bool = false
    @State private var importError: String?

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Color(hex: 0xFAF8FF), Color(hex: 0xFFFFFF)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if items.isEmpty && !importing {
                emptyState
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
        .navigationTitle("Private Vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { vault.lock() }) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(AppColor.brandPrimary)
                }
            }
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
            matching: .images
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
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(items) { item in
                    VaultThumbnail(vault: vault, item: item)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onTapGesture { previewItem = item }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
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

    private var fab: some View {
        Button(action: { showAddSheet = true }) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
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
                guard let data = try await pick.loadTransferable(type: Data.self) else { continue }
                let fileName = pick.itemIdentifier ?? "Photo-\(UUID().uuidString.prefix(6))"
                try saveImported(data: data, fileName: String(fileName))
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
}

// MARK: - Thumbnail

private struct VaultThumbnail: View {
    let vault: VaultService
    let item: VaultItem
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: 0xE2E8F0)
                    .overlay(
                        Image(systemName: "lock.fill")
                            .foregroundStyle(AppColor.textMuted)
                    )
            }
        }
        .task(id: item.id) {
            image = await Self.loadThumbnail(vault: vault, item: item)
        }
    }

    // Decrypt off the main thread so the grid scrolls smoothly. Capture only
    // `id` (Sendable) before crossing actor boundary — VaultItem isn't Sendable.
    private static func loadThumbnail(vault: VaultService, item: VaultItem) async -> UIImage? {
        let itemID = item.id
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? vault.readDecrypted(for: itemID),
                  let img = UIImage(data: data) else { return nil }
            // Downscale to ~256pt longest edge — playbook §4 perf principle.
            return img.preparingThumbnail(of: CGSize(width: 256, height: 256))
        }.value
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
