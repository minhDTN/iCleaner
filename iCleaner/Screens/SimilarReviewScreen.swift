import SwiftUI

// Figma `2005:21828` (similar review).
// Nav bar: back + "{category}" title (left) + "Select All" pill (right, bg
// #E4F1FF, stroke #0D7FF2, radius 20, icon + text). Sub-header row below:
// "15 Photos · 48MB" (left) + filter icon 24×24 bare (right). Then sections,
// each "N Similar" + "X MB" + grey "Select All" text. Bottom: red delete CTA.
struct SimilarReviewScreen: View {
    let categoryTitle: String
    @Binding var groups: [SimilarGroup]
    let headerPhotoCount: Int
    let headerSizeMB: Int
    let selectedCount: Int
    let selectedMB: Int
    var onBack: () -> Void
    var onFilter: () -> Void
    var onDeleteTap: () -> Void

    // Whether every non-best photo across all groups is selected.
    private var allSelected: Bool {
        groups.allSatisfy { g in
            g.photos.enumerated().allSatisfy { idx, p in idx == g.bestMatchIndex || p.isSelected }
        }
    }

    private func toggleSelectAll() {
        let target = !allSelected
        for gi in groups.indices {
            for pi in groups[gi].photos.indices where pi != groups[gi].bestMatchIndex {
                groups[gi].photos[pi].isSelected = target
            }
        }
    }

    // Compute once per body so SwiftUI's diffing tracks stable IDs. Inserts a
    // native ad after every 2 groups except the last slot (so the ad never
    // appears as the final item right above the delete CTA).
    private var feed: [ReviewFeedItem] {
        var items: [ReviewFeedItem] = []
        for (idx, group) in groups.enumerated() {
            items.append(.group(idx: idx, id: group.id))
            if (idx + 1) % 2 == 0 && idx < groups.count - 1 {
                items.append(.nativeAd(slot: idx / 2))
            }
        }
        return items
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surfaceBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                subHeader
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(feed) { item in
                            switch item {
                            case .group(let idx, _):
                                SimilarGroupSection(group: $groups[idx])
                            case .nativeAd:
                                NativeAdView(adUnitID: AdUnits.nativeSimilarList, height: 120)
                            }
                        }
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }

            deleteCTA
        }
    }

    // Figma 2005:21832: back + "{category}" title (left) + Select All pill (right).
    private var navBar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.textBlack)
                    .frame(width: 24, height: 24)
            }

            Text(categoryTitle)
                .font(.custom("Inter-SemiBold", size: 18))
                .foregroundStyle(AppColor.textBlack)

            Spacer()

            Button(action: toggleSelectAll) {
                HStack(spacing: 5) {
                    Image("Clean/ic_select_multiple")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text("Select All")
                        .font(.custom("Inter-Regular", size: 16))
                }
                // Active (all selected) → solid brand-blue fill + white content.
                // Inactive → light tint #E4F1FF + brand-blue content.
                .foregroundStyle(allSelected ? .white : AppColor.brandPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(height: 32)
                .background(Capsule().fill(allSelected ? AppColor.brandPrimary : Color(hex: 0xE4F1FF)))
                .overlay(Capsule().stroke(AppColor.brandPrimary, lineWidth: 1))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .background(
            AppColor.surfaceBackground
                .overlay(Rectangle().fill(Color(hex: 0xB2B2B2).opacity(0.4)).frame(height: 1), alignment: .bottom)
        )
    }

    // Figma 2005:21851: "{N} Photos · {X}MB" (left) + bare filter icon (right).
    private var subHeader: some View {
        HStack(spacing: 8) {
            Text("\(headerPhotoCount) Photos")
                .font(.custom("Inter-Medium", size: 14))
                .foregroundStyle(Color(hex: 0x00091D))
            Text("·")
                .font(.custom("Inter-Medium", size: 14))
                .foregroundStyle(AppColor.textMuted)
            Text("\(headerSizeMB)MB")
                .font(.custom("Inter-Medium", size: 14))
                .foregroundStyle(AppColor.brandPrimary)

            Spacer()

            Button(action: onFilter) {
                Image("Clean/ic_filter")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(hex: 0x0F0F0F))
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    private var deleteCTA: some View {
        let isDisabled = selectedCount == 0
        return Button(action: onDeleteTap) {
            HStack(spacing: 8) {
                Image("Clean/ic_delete")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text(isDisabled
                     ? "Delete Selected"
                     : "Delete \(selectedCount) Selected (\(selectedMB) MB)")
                    .font(.custom("Inter-Bold", size: 16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.danger.opacity(isDisabled ? 0.4 : 1.0))
                    .shadow(color: AppColor.danger.opacity(isDisabled ? 0 : 0.2),
                            radius: 10, x: 0, y: 8)
                    .shadow(color: AppColor.danger.opacity(isDisabled ? 0 : 0.2),
                            radius: 12, x: 0, y: 20)
            )
        }
        .disabled(isDisabled)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

private enum ReviewFeedItem: Identifiable {
    case group(idx: Int, id: UUID)
    case nativeAd(slot: Int)

    var id: String {
        switch self {
        case .group(_, let gid):  return "g_\(gid)"
        case .nativeAd(let slot): return "ad_\(slot)"
        }
    }
}

private struct SimilarGroupSection: View {
    @Binding var group: SimilarGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Figma 2005:21866: "N Similar" Bold 16 + "X MB" Medium 12 brand-blue
            // (baseline-aligned) on the left; grey "Select All" text on the right.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .font(.custom("Inter-Bold", size: 16))
                    .foregroundStyle(Color(hex: 0x0F172A))
                Text(group.sizeLabel)
                    .font(.custom("Inter-Medium", size: 12))
                    .foregroundStyle(AppColor.brandPrimary)
                Spacer()
                Button(action: toggleAllExceptBest) {
                    Text(allExceptBestSelected ? "Deselect" : "Select All")
                        .font(.custom("Inter-SemiBold", size: 12))
                        .foregroundStyle(Color(hex: 0x64748B))
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(group.photos.indices, id: \.self) { idx in
                    SimilarPhotoCell(
                        photo: $group.photos[idx],
                        isBestMatch: idx == group.bestMatchIndex
                    )
                }
            }
        }
    }

    private var allExceptBestSelected: Bool {
        group.photos.enumerated().allSatisfy { idx, photo in
            idx == group.bestMatchIndex || photo.isSelected
        }
    }

    private func toggleAllExceptBest() {
        let target = !allExceptBestSelected
        for idx in group.photos.indices where idx != group.bestMatchIndex {
            group.photos[idx].isSelected = target
        }
    }
}

private struct SimilarPhotoCell: View {
    @Binding var photo: SimilarPhoto
    let isBestMatch: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            placeholderImage
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            if isBestMatch {
                bestMatchPill.padding(8)
            } else {
                selectionToggle
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Best Match is not selectable by design (it stays).
            guard !isBestMatch else { return }
            photo.isSelected.toggle()
        }
    }

    @ViewBuilder
    private var placeholderImage: some View {
        if let assetID = photo.assetID {
            PHAssetThumbnail(localIdentifier: assetID, targetSize: CGSize(width: 320, height: 320))
        } else {
            mockGradient
        }
    }

    private var mockGradient: some View {
        let palettes: [[Color]] = [
            [Color(hex: 0xDBEAFE), Color(hex: 0xBFDBFE)],
            [Color(hex: 0xE0E7FF), Color(hex: 0xC7D2FE)],
            [Color(hex: 0xCFFAFE), Color(hex: 0xA5F3FC)],
            [Color(hex: 0xDCFCE7), Color(hex: 0xBBF7D0)],
            [Color(hex: 0xFEF3C7), Color(hex: 0xFDE68A)],
            [Color(hex: 0xFFE4E6), Color(hex: 0xFECDD3)],
            [Color(hex: 0xF3E8FF), Color(hex: 0xE9D5FF)],
        ]
        let colors = palettes[abs(photo.seed) % palettes.count]
        return ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "photo.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var bestMatchPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 9))
            Text("Best Match")
        }
        .font(.custom("Inter-Bold", size: 10))
        .foregroundStyle(AppColor.brandPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(AppColor.brandPrimary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
    }

    // Figma 2005:21879: unselected = 23×23 circle, fill rgba(0,0,0,0.1) +
    // stroke rgba(255,255,255,0.8) 1.9px + blur (a subtle glass dot, NO check).
    // Selected = solid brand-blue + white checkmark.
    private var selectionToggle: some View {
        ZStack {
            Circle()
                .fill(photo.isSelected ? AnyShapeStyle(AppColor.brandPrimary)
                                       : AnyShapeStyle(.ultraThinMaterial))
                .frame(width: 23, height: 23)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.9)
                )
            if photo.isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}
