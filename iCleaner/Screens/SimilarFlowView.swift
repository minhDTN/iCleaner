import SwiftUI
import Photos
import LibEarnMoneyIOS

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
    var detectionConfig: PhotoLibraryService.DetectionConfig = .init()

    @Environment(\.dismiss) private var dismiss
    @State private var photoLibrary = PhotoLibraryService()
    @State private var step: Step = .loading
    @State private var groups: [SimilarGroup] = []
    @State private var showFilter: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var filter: SimilarFilter = .default
    @State private var deletedMB: Int = 0
    @State private var deleteError: String?
    @State private var previewGroupIndex: Int?
    @State private var previewPhotoIndex: Int = 0

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
                    onDeleteTap: { if !selectedPhotos.isEmpty { showDeleteConfirm = true } },
                    onOpenPreview: { gIdx, pIdx in
                        previewPhotoIndex = pIdx
                        previewGroupIndex = gIdx
                    }
                )
            case .deleting:
                SimilarCleaningView(
                    performDelete: performRealDelete,
                    onComplete: { success in
                        // Only celebrate if the OS actually deleted the assets.
                        // If the user denied the system delete prompt, go back to
                        // review and surface the reason.
                        step = success ? .success : .review
                    }
                )
            case .success:
                SimilarSuccessView(deletedMB: deletedMB, onContinue: continueAfterSuccess)
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
            SimilarFilterSheet(
                filter: $filter,
                onApply: {
                    showFilter = false
                    Task { await applyFilter() }
                },
                onClear: { filter = .default }
            )
            .presentationDetents([.height(510)])
        }
        .fullScreenCover(item: Binding(
            get: { previewGroupIndex.map { PreviewTarget(groupIndex: $0) } },
            set: { previewGroupIndex = $0?.groupIndex }
        )) { target in
            if groups.indices.contains(target.groupIndex) {
                PhotoPreviewView(group: $groups[target.groupIndex], index: previewPhotoIndex)
            }
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

    // Re-fetch after a filter change. Stays on .review even if 0 groups match
    // (so the user can open the filter again), unlike the initial bootstrap
    // which routes to .empty.
    private func applyFilter() async {
        let assetGroups = await photoLibrary.detectSimilarGroups(
            config: detectionConfig,
            sinceDays: filterSinceDays,
            largestFirst: filter.sortBySize == .largeFirst
        )
        groups = mapGroups(assetGroups)
        step = .review
    }

    private var filterSinceDays: Int? {
        switch filter.dateRange {
        case .sevenDays:  return 7
        case .thirtyDays: return 30
        case .allTime:    return nil
        }
    }

    private func mapGroups(_ assetGroups: [PHAssetGroup]) -> [SimilarGroup] {
        assetGroups.map { g in
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
    }

    private func reloadGroups() async {
        let assetGroups = await photoLibrary.detectSimilarGroups(
            config: detectionConfig,
            sinceDays: filterSinceDays,
            largestFirst: filter.sortBySize == .largeFirst
        )
        if assetGroups.isEmpty {
            step = .empty
        } else {
            // Selection default: all except Best Match (one-tap dedup cleanup).
            groups = mapGroups(assetGroups)
            step = .review
        }
    }

    // Returns true only when the OS confirmed the deletion. Returns false if the
    // user denied the system delete prompt (PHPhotosError.userCancelled) or any
    // other failure — the caller then stays on review instead of showing success.
    private func performRealDelete() async -> Bool {
        let toDelete = selectedPhotos.compactMap(\.assetID)
        guard !toDelete.isEmpty else { return false }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: toDelete, options: nil)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        do {
            try await photoLibrary.delete(assets: assets)
            // Prune selected photos AND drop any group that becomes empty so the
            // post-success refresh doesn't render an empty card.
            groups = groups.compactMap { g in
                var trimmed = g
                trimmed.photos.removeAll { $0.isSelected }
                return trimmed.photos.isEmpty ? nil : trimmed
            }
            return true
        } catch let error as PHPhotosError where error.code == .userCancelled {
            // User tapped "Don't Allow" on the system delete sheet — silent, no
            // error alert (it's a deliberate choice, not a failure).
            return false
        } catch {
            deleteError = (error as NSError).localizedDescription
            return false
        }
    }

    // After tapping Perfect!: show the interstitial, then route back to the
    // review screen if there are still groups left to clean (so the user can keep
    // deleting), or dismiss to Home when everything's been cleaned up.
    // `performRealDelete` already pruned deleted photos + emptied groups, so a
    // non-empty `groups` means there's more to do.
    private func continueAfterSuccess() {
        let next: () -> Void = {
            if groups.isEmpty {
                dismiss()
            } else {
                step = .review
            }
        }
        guard !PremiumGate.isPremium,
              let vc = AdHelpers.topViewController() else {
            next()
            return
        }
        AdManager.shared.showInterstitialAd(
            adUnitID: AdUnits.interGlobal,
            from: vc
        ) {
            Task { @MainActor in next() }
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

// Identifiable wrapper so the preview cover binds to a group index.
struct PreviewTarget: Identifiable {
    let groupIndex: Int
    var id: Int { groupIndex }
}

struct SimilarGroup: Identifiable {
    let id = UUID()
    let title: String          // e.g. "4 Similar"
    var photos: [SimilarPhoto]
    let bestMatchIndex: Int    // index in photos that wears the Best Match pill

    // Total size of this group's photos, formatted (e.g. "12 MB").
    var sizeLabel: String {
        let mb = photos.reduce(0) { $0 + $1.sizeKB } / 1024
        return mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }

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
