import SwiftUI

// Figma `2005:21828` (similar review).
// Top: nav row (back + "15 Photos · 48MB" centered + filter pill 126×32 rounded
// 20, stroke + bg #E4F1FF), then 3+ sections each with "N Similar" header +
// 2-column grid (Best Match large + duplicates square). Bottom: 337×56 red
// destructive CTA "Delete N Selected (X MB)" with brand-red shadow.
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

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surfaceBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(spacing: 24) {
                        ForEach($groups) { $group in
                            SimilarGroupSection(group: $group)
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

    private var navBar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 24, height: 24)
            }

            Spacer()

            HStack(spacing: 8) {
                Text("\(headerPhotoCount) Photos")
                    .font(.custom("Inter-Medium", size: 14))
                    .foregroundStyle(Color(hex: 0x00091D))
                Text("·")
                    .foregroundStyle(AppColor.textMuted)
                Text("\(headerSizeMB) MB")
                    .font(.custom("Inter-Medium", size: 14))
                    .foregroundStyle(AppColor.brandPrimary)
            }

            Spacer()

            Button(action: onFilter) {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Filter")
                        .font(.custom("Inter-SemiBold", size: 13))
                }
                .foregroundStyle(AppColor.brandPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color(hex: 0xE4F1FF))
                )
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

    private var deleteCTA: some View {
        let isDisabled = selectedCount == 0
        return Button(action: onDeleteTap) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .semibold))
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

private struct SimilarGroupSection: View {
    @Binding var group: SimilarGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.brandPrimary)
                Text(group.title)
                    .font(.custom("Inter-SemiBold", size: 16))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Button(action: toggleAllExceptBest) {
                    Text(allExceptBestSelected ? "Deselect" : "Select all")
                        .font(.custom("Inter-Medium", size: 13))
                        .foregroundStyle(AppColor.brandPrimary)
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

    private var selectionToggle: some View {
        ZStack {
            Circle()
                .fill(photo.isSelected ? AppColor.brandPrimary : Color.white.opacity(0.8))
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            if photo.isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}
