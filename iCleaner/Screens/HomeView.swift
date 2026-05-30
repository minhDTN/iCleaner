import SwiftUI

// Figma `2005:22671` (home — empty state) / `2005:21769` (home — populated).
// Bg white. Layout: status bar → "Your Storage" header → 8 category section cards
// → sticky `Quick Clean (X MB)` CTA → bottom tab bar (rendered by RootView).
//
// Card spec: 335 wide, white bg, stroke rgba(13,127,242,0.2) 1px, radius 12,
// shadow `0 4 20 -10 rgba(13,127,242,0.15)`, padding 10x16.
// CTA spec: brand-blue #0D7FF2, radius 12, padding 16/12, shadow `0 8 25 -5 rgba(13,127,242,0.5)`.
//
// Per-category icons aren't downloaded yet (each is a generic `Frame` node in the
// Figma dump that needs per-screen extraction). SF Symbol fallback for Phase 1.
struct HomeView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surfaceBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 15) {
                    storageHeader
                    ForEach(HomeCategory.all) { cat in
                        categoryCard(cat)
                    }
                    Spacer(minLength: 120)  // Room for the floating CTA.
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            quickCleanCTA
        }
    }

    private var storageHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Storage")
                .font(AppFont.titleMedium)
                .foregroundStyle(AppColor.textPrimary)
            HStack(spacing: 12) {
                statTile(label: "Used", value: "0 MB")
                statTile(label: "Photos", value: "0")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.surfaceBackground)
                .shadow(
                    color: AppColor.brandPrimary.opacity(0.15),
                    radius: 10, x: 0, y: 4
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.brandPrimary.opacity(0.2), lineWidth: 1)
        )
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.custom("Inter-Bold", size: 22))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryCard(_ cat: HomeCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: cat.systemIcon)
                .font(.system(size: 24))
                .foregroundStyle(AppColor.brandPrimary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColor.brandPrimary.opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(cat.title)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("0 photos · 0 MB")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.chevron)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.surfaceBackground)
                .shadow(
                    color: AppColor.brandPrimary.opacity(0.15),
                    radius: 10, x: 0, y: 4
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.brandPrimary.opacity(0.2), lineWidth: 1)
        )
    }

    private var quickCleanCTA: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                Text("Quick Clean (0 MB)")
                    .font(.custom("Inter-SemiBold", size: 16))
            }
            .foregroundStyle(AppColor.textOnBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.brandPrimary)
                    .shadow(
                        color: AppColor.brandPrimary.opacity(0.5),
                        radius: 12, x: 0, y: 8
                    )
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

struct HomeCategory: Identifiable {
    let key: String
    let title: String
    let systemIcon: String
    var id: String { key }

    // 8 categories from Figma populated home (2005:21769).
    static let all: [HomeCategory] = [
        .init(key: "similar",            title: "Similar",              systemIcon: "rectangle.stack.fill"),
        .init(key: "duplicates",         title: "Duplicates",           systemIcon: "doc.on.doc.fill"),
        .init(key: "similar_screenshots", title: "Similar Screenshots", systemIcon: "camera.viewfinder"),
        .init(key: "similar_videos",      title: "Similar Videos",      systemIcon: "video.fill"),
        .init(key: "other_screenshots",   title: "Other Screenshots",   systemIcon: "viewfinder"),
        .init(key: "chat_photos",         title: "Chat Photos",         systemIcon: "bubble.left.and.bubble.right.fill"),
        .init(key: "videos_organizer",    title: "Videos Organizer",    systemIcon: "play.rectangle.fill"),
        .init(key: "other",               title: "Other",               systemIcon: "photo.fill"),
    ]
}

#Preview {
    HomeView()
}
