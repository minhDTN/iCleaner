import SwiftUI
import Photos

// Owner of the Similar cleanup flow. Manages the state machine
// (loading → review → deleting → success) and the modal overlays
// (filter sheet, delete confirm). Presented from Home via fullScreenCover
// when a category's "Review Group" button is tapped.
//
// Phase 3 Part B wired here: real Photos permission + PHAsset fetch via
// PhotoLibraryService. On first launch we request permission, then fetch
// time-window clusters. If the user denies, we show a permission-gate UI
// instead of the review screen.
//
// Phase 3 Part C will wire the post-delete interstitial + native ads
// between groups (premium-gated).
struct SimilarFlowView: View {
    let categoryTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var photoLibrary = PhotoLibraryService()
    @State private var step: Step = .loading
    @State private var groups: [SimilarGroup] = []
    @State private var showFilter: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var filter: SimilarFilter = .default
    @State private var deletedMB: Int = 0
    @State private var deleteError: String?

    private enum Step { case loading, permissionGate, empty, review, deleting, success }

    private var selectedPhotos: [SimilarPhoto] {
        groups.flatMap { $0.photos.filter { $0.isSelected } }
    }
    private var totalSelectedMB: Int {
        selectedPhotos.reduce(0) { $0 + $1.sizeKB } / 1024
    }
    private var totalPhotos: Int {
        groups.reduce(0) { $0 + $1.photos.count }
    }
    private var totalMB: Int {
        groups.flatMap(\.photos).reduce(0) { $0 + $1.sizeKB } / 1024
    }

    var body: some View {
        ZStack {
            switch step {
            case .loading:
                loadingView
            case .permissionGate:
                permissionGateView
            case .empty:
                emptyView
            case .review:
                SimilarReviewScreen(
                    categoryTitle: categoryTitle,
                    groups: $groups,
                    headerPhotoCount: totalPhotos,
                    headerSizeMB: totalMB,
                    selectedCount: selectedPhotos.count,
                    selectedMB: totalSelectedMB,
                    onBack: { dismiss() },
                    onFilter: { showFilter = true },
                    onDeleteTap: { if !selectedPhotos.isEmpty { showDeleteConfirm = true } }
                )
            case .deleting:
                SimilarCleaningView(
                    performDelete: performRealDelete,
                    onComplete: { step = .success }
                )
            case .success:
                SimilarSuccessView(deletedMB: deletedMB, onContinue: { dismiss() })
            }

            if showDeleteConfirm {
                SimilarDeleteConfirm(
                    photoCount: selectedPhotos.count,
                    sizeMB: totalSelectedMB,
                    onCancel: { showDeleteConfirm = false },
                    onDelete: {
                        deletedMB = totalSelectedMB
                        showDeleteConfirm = false
                        step = .deleting
                    }
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showFilter) {
            SimilarFilterSheet(filter: $filter, onApply: { showFilter = false }, onClear: {
                filter = .default
            })
            .presentationDetents([.height(510)])
        }
        .alert("Couldn't delete", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .task { await bootstrap() }
        .animation(.easeInOut(duration: 0.22), value: showDeleteConfirm)
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Lifecycle

    private func bootstrap() async {
        // Ask once if we haven't yet; then route to the right step.
        if photoLibrary.authStatus == .notDetermined {
            await photoLibrary.requestAuthorization()
        }
        guard photoLibrary.authStatus.canRead else {
            step = .permissionGate
            return
        }
        await reloadGroups()
    }

    private func reloadGroups() async {
        let assetGroups = await photoLibrary.detectSimilarGroups()
        if assetGroups.isEmpty {
            step = .empty
        } else {
            // Convert PHAssetGroup → SimilarGroup. Selection defaults: select all
            // except the Best Match (so the user can one-tap to clean up duplicates).
            groups = assetGroups.map { g in
                let photos = g.assets.enumerated().map { (idx, asset) in
                    SimilarPhoto(
                        assetID: asset.localIdentifier,
                        seed: idx,
                        sizeKB: Int(asset.estimatedSizeKB),
                        isSelected: idx != g.bestMatchIndex
                    )
                }
                return SimilarGroup(title: g.title, photos: photos, bestMatchIndex: g.bestMatchIndex)
            }
            step = .review
        }
    }

    private func performRealDelete() async {
        let toDelete = selectedPhotos.compactMap(\.assetID)
        guard !toDelete.isEmpty else { return }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: toDelete, options: nil)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        do {
            try await photoLibrary.delete(assets: assets)
            // Remove from local model so a refresh shows the right state.
            for groupIdx in groups.indices {
                groups[groupIdx].photos.removeAll { $0.isSelected }
            }
        } catch {
            deleteError = (error as NSError).localizedDescription
        }
    }

    // MARK: - State subviews

    private var loadingView: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()
            ProgressView()
                .tint(AppColor.brandPrimary)
        }
    }

    private var permissionGateView: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColor.brandPrimary)
                Text("Photos access required")
                    .font(.custom("Inter-Bold", size: 22))
                    .foregroundStyle(AppColor.textPrimary)
                Text("iCleaner needs access to your photo library to find similar photos and duplicates you can clean up.")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: { photoLibrary.opensSettings() }) {
                    Text("Open Settings")
                        .font(.custom("Inter-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppColor.brandPrimary)
                        )
                }
                .padding(.horizontal, 32)
                Button(action: { dismiss() }) {
                    Text("Back")
                        .font(.custom("Inter-SemiBold", size: 14))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private var emptyView: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColor.brandPrimary)
                Text("Nothing to clean")
                    .font(.custom("Inter-Bold", size: 20))
                    .foregroundStyle(AppColor.textPrimary)
                Text("We didn't find any similar photos in your library right now.")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.custom("Inter-Bold", size: 16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppColor.brandPrimary)
                        )
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Mock model

struct SimilarGroup: Identifiable {
    let id = UUID()
    let title: String          // e.g. "4 Similar"
    var photos: [SimilarPhoto]
    let bestMatchIndex: Int    // index in photos that wears the Best Match pill

    // Mock kept for SwiftUI previews + design QA. Real groups come from
    // PhotoLibraryService.detectSimilarGroups().
    static let mock: [SimilarGroup] = [
        SimilarGroup(
            title: "4 Similar",
            photos: (0..<4).map { i in SimilarPhoto(assetID: nil, seed: i + 1, sizeKB: 2_400, isSelected: i != 0) },
            bestMatchIndex: 0
        ),
        SimilarGroup(
            title: "7 Similar",
            photos: (0..<7).map { i in SimilarPhoto(assetID: nil, seed: i + 10, sizeKB: 1_800, isSelected: i != 0) },
            bestMatchIndex: 0
        ),
    ]
}

struct SimilarPhoto: Identifiable {
    let id = UUID()
    let assetID: String?    // PHAsset.localIdentifier; nil for mock data
    let seed: Int           // fallback gradient color when assetID == nil
    let sizeKB: Int
    var isSelected: Bool
}

struct SimilarFilter: Equatable {
    var sortBySize: SortBySize = .largeFirst
    var dateRange: DateRange = .allTime
    var sources: Set<Source> = [.camera, .screenshots, .download]

    enum SortBySize: String, CaseIterable { case largeFirst = "Large to Small", smallFirst = "Small to Large" }
    enum DateRange: String, CaseIterable { case sevenDays = "7 days", thirtyDays = "30 days", allTime = "All time" }
    enum Source: String, CaseIterable, Hashable { case camera = "Camera", screenshots = "Screenshots", download = "Download" }

    static let `default` = SimilarFilter()
}

// PHAsset doesn't expose file size directly; estimate from pixel dimensions.
// Rough heuristic: JPEG ~3 bytes per pixel after compression, divide by 1024.
extension PHAsset {
    var estimatedSizeKB: Int {
        let pixels = pixelWidth * pixelHeight
        return max(1, pixels * 3 / 1024)
    }
}

#Preview {
    SimilarFlowView(categoryTitle: "Similar")
}
