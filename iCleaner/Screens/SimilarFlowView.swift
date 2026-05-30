import SwiftUI

// Owner of the Similar cleanup flow. Manages the state machine
// (review → deleting → success) and the modal overlays (filter sheet,
// delete confirm). Presented from Home via fullScreenCover when a
// category's "Review Group" button is tapped.
//
// MVP: mock data only. Phase 3 Part B wires in PhotoLibraryService +
// Vision similar detection + real PHAsset delete. Part C wires the
// post-delete interstitial + native ads between groups.
struct SimilarFlowView: View {
    let categoryTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .review
    @State private var groups: [SimilarGroup] = SimilarGroup.mock
    @State private var showFilter: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var filter: SimilarFilter = .default
    @State private var deletedMB: Int = 0
    @State private var deletedCount: Int = 0

    private enum Step { case review, deleting, success }

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
                SimilarCleaningView(onComplete: {
                    step = .success
                })
            case .success:
                SimilarSuccessView(deletedMB: deletedMB, onContinue: { dismiss() })
            }

            if showDeleteConfirm {
                SimilarDeleteConfirm(
                    photoCount: selectedPhotos.count,
                    sizeMB: totalSelectedMB,
                    onCancel: { showDeleteConfirm = false },
                    onDelete: {
                        deletedCount = selectedPhotos.count
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
        .animation(.easeInOut(duration: 0.22), value: showDeleteConfirm)
        .animation(.easeInOut(duration: 0.3), value: step)
    }
}

// MARK: - Mock data

struct SimilarGroup: Identifiable {
    let id = UUID()
    let title: String          // e.g. "4 Similar"
    var photos: [SimilarPhoto]
    let bestMatchIndex: Int    // index in photos that wears the Best Match pill

    static let mock: [SimilarGroup] = [
        SimilarGroup(
            title: "4 Similar",
            photos: (0..<4).map { i in SimilarPhoto(seed: i + 1, sizeKB: 2_400, isSelected: i != 0) },
            bestMatchIndex: 0
        ),
        SimilarGroup(
            title: "7 Similar",
            photos: (0..<7).map { i in SimilarPhoto(seed: i + 10, sizeKB: 1_800, isSelected: i != 0) },
            bestMatchIndex: 0
        ),
        SimilarGroup(
            title: "4 Similar",
            photos: (0..<4).map { i in SimilarPhoto(seed: i + 20, sizeKB: 3_200, isSelected: i != 0) },
            bestMatchIndex: 0
        ),
    ]
}

struct SimilarPhoto: Identifiable {
    let id = UUID()
    let seed: Int       // for placeholder gradient color
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

#Preview {
    SimilarFlowView(categoryTitle: "Similar")
}
