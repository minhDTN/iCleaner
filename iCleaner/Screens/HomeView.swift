import SwiftUI
import LibEarnMoneyIOS

// Figma `2005:22671` (empty state) / `2005:21769` (populated).
// IMPORTANT: the Figma populated home is mostly placeholder — section titles,
// per-category icons, "+N" overlays, KPI strings are NOT in the export. The
// titles/icons/counts below are authored in code; replace when designer ships
// the real per-section assets.
//
// Card chrome (verbatim from Figma):
//   • bg #FFFFFF, stroke rgba(13,127,242,0.2) 1px, radius 12,
//     shadow 0 4 20 -10 rgba(13,127,242,0.15), padding 0/0/10 bottom.
//   • Title row: padding 10×16, bottom border 1px #F1F5F9.
//   • Best Photo 198.67 wide + Stack of Duplicates 105.33 wide, total 316 + 12 gap.
//   • Best Match pill (top-left): white 90%, brand-blue stroke 20%, blur 8, radius 4,
//     Inter Bold 10/15 brand-blue.
//   • Review Group button: stroke rgba(13,127,242,0.3) 1px, radius 8, padding 10/0,
//     Inter Medium 14/20 brand-blue + chevron.
//   • Video play badge: 42×42 white 20%, stroke white 30% 0.66px, blur 7.875.
struct HomeView: View {
    @State private var showPopulated: Bool = true
    @State private var openedCategory: HomeCategory?
    @State private var showQuickClean: Bool = false
    @State private var showSettings: Bool = false
    @State private var showPaywall: Bool = false
    @State private var observedPremium = PermissionManager.shared.isPremium
    @AppStorage(PremiumGate.forcePremiumKey) private var forcePremium: Bool = false

    private var isPremium: Bool {
        #if DEBUG
        return observedPremium || forcePremium
        #else
        return observedPremium
        #endif
    }

    private var categories: [HomeCategory] {
        showPopulated ? HomeCategory.populatedMock : HomeCategory.emptyMock
    }

    private var quickCleanTotalMB: Int {
        categories.map(\.sizeMB).reduce(0, +)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surfaceBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 15) {
                    header
                    ForEach(categories) { cat in
                        HomeCategoryCard(
                            category: cat,
                            onReviewTap: { openedCategory = cat }
                        )
                    }
                    Spacer(minLength: 120)  // Room for the floating CTA.
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            quickCleanCTA
        }
        .fullScreenCover(item: $openedCategory) { cat in
            SimilarFlowView(categoryTitle: cat.title)
        }
        .fullScreenCover(isPresented: $showQuickClean) {
            QuickCleanFlowView()
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
        .onReceive(PermissionManager.shared.$isPremium) { observedPremium = $0 }
    }

    // Figma `2005:22684`: title "Your Storage" left (Inter SemiBold 18) +
    // settings + premium diamond right (gap 20, 24×24 each, no circle bg).
    // Diamond only shows when NOT premium → tapping opens the paywall.
    private var header: some View {
        HStack(spacing: 10) {
            Text("Your Storage")
                .font(.custom("Inter-SemiBold", size: 18))
                .foregroundStyle(AppColor.textBlack)

            Spacer()

            // Figma order: settings first, then premium diamond (gap 20).
            HStack(spacing: 20) {
                Button(action: { showSettings = true }) {
                    Image("Home/ic_settings")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color(hex: 0x292D32))
                        .frame(width: 24, height: 24)
                }

                if !isPremium {
                    Button(action: { showPaywall = true }) {
                        Image("Home/ic_premium_diamond")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                }
            }
        }
        .frame(height: 48)
    }

    private var quickCleanCTA: some View {
        Button(action: { showQuickClean = true }) {
            HStack(spacing: 12) {
                // Figma uses Material Icons `auto_fix_high` — SF Symbol substitute.
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 18, weight: .semibold))
                Text("Quick Clean (\(quickCleanTotalMB) MB)")
                    .font(.custom("Inter-SemiBold", size: 16))
            }
            .foregroundStyle(AppColor.textOnBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.brandPrimary)
                    .shadow(color: AppColor.brandPrimary.opacity(0.5), radius: 12, x: 0, y: 8)
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

// MARK: - Category card

private struct HomeCategoryCard: View {
    let category: HomeCategory
    var onReviewTap: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            titleRow
            if category.photoCount > 0 {
                photoStack
                reviewGroupButton
            }
        }
        .padding(.bottom, 10)
        .background(AppColor.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.brandPrimary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: AppColor.brandPrimary.opacity(0.15), radius: 10, x: 0, y: 4)
    }

    // Figma title row (2005:21772 / 18:16): left column = title + subtitle (NO
    // icon next to title). Right column = row1 [icon 24 + "X MB" Bold 16 brand-
    // blue, gap 5], row2 "N Photos" Regular 12 #94A3B8.
    private var titleRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.custom("Inter-SemiBold", size: 16))
                    .foregroundStyle(Color(hex: 0x0F172A))
                Text(category.subtitle)
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(Color(hex: 0x64748B))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: -0.5) {
                HStack(spacing: 5) {
                    Image(category.iconAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text(category.sizeLabel)
                        .font(.custom("Inter-Bold", size: 16))
                        .foregroundStyle(AppColor.brandPrimary)
                }
                Text(category.metric)
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(Color(hex: 0x94A3B8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(Color(hex: 0xF1F5F9))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var photoStack: some View {
        HStack(alignment: .top, spacing: 12) {
            bestPhoto
                .frame(width: 198.67, height: 128)
            duplicateStack
                .frame(width: 105.33, height: 128)
        }
        .padding(.horizontal, (335 - 316) / 2)  // center 316 in 335-wide card
    }

    private var bestPhoto: some View {
        ZStack(alignment: .topLeading) {
            placeholderImage
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if category.isVideo {
                videoPlayBadge
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            bestMatchPill
                .padding(8)
        }
    }

    // Figma 15:1034: ⭐ star (Material Icons 10) + "Best Match" Bold 10 brand-
    // blue, gap 4, padding 2×8, white 90% bg + brand-blue stroke 20% + blur.
    private var bestMatchPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 9))
            Text("Best Match")
                .font(.custom("Inter-Bold", size: 10))
        }
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
                .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
    }

    private var videoPlayBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.30), lineWidth: 0.66)
                    )
            )
    }

    // Figma 15:1038: top = a duplicate photo (80% opacity, border #F1F5F9);
    // bottom = "+N" box with grey #F1F5F9 background (NOT a dark overlay capsule),
    // "+N" text Inter Medium 12 #64748B centered.
    private var duplicateStack: some View {
        VStack(spacing: 8) {
            placeholderImage(seed: category.title.count + 1)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(0.8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(hex: 0xF1F5F9), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: 0xF1F5F9))
                Text("+\(max(1, category.photoCount - 3))")
                    .font(.custom("Inter-Medium", size: 12))
                    .foregroundStyle(Color(hex: 0x64748B))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var placeholderImage: some View {
        placeholderImage(seed: category.title.count)
    }

    // Deterministic colored gradient placeholder — swap to real photo thumbs when
    // Photos permission flow + PHAsset fetching land in Phase 3.
    private func placeholderImage(seed: Int) -> some View {
        let palettes: [[Color]] = [
            [Color(hex: 0xDBEAFE), Color(hex: 0xBFDBFE)],
            [Color(hex: 0xE0E7FF), Color(hex: 0xC7D2FE)],
            [Color(hex: 0xCFFAFE), Color(hex: 0xA5F3FC)],
            [Color(hex: 0xDCFCE7), Color(hex: 0xBBF7D0)],
            [Color(hex: 0xFEF3C7), Color(hex: 0xFDE68A)],
            [Color(hex: 0xFFE4E6), Color(hex: 0xFECDD3)],
            [Color(hex: 0xF3E8FF), Color(hex: 0xE9D5FF)],
        ]
        let colors = palettes[abs(seed) % palettes.count]
        return ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: category.isVideo ? "video" : "photo")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var reviewGroupButton: some View {
        Button(action: onReviewTap) {
            HStack(spacing: 6) {
                Text("Review Group")
                    .font(.custom("Inter-SemiBold", size: 15))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(AppColor.brandPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColor.brandPrimary.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.horizontal, (335 - 316) / 2)
    }
}

// MARK: - Mock model

struct HomeCategory: Identifiable {
    let key: String
    let title: String
    let subtitle: String
    let iconAsset: String   // Figma category icon in Assets/Home/
    let photoCount: Int
    let sizeMB: Int
    let isVideo: Bool

    var id: String { key }
    var metric: String { isVideo ? "\(photoCount) Videos" : "\(photoCount) Photos" }
    var sizeLabel: String { sizeMB >= 1024 ? String(format: "%.1f GB", Double(sizeMB) / 1024) : "\(sizeMB) MB" }

    static let populatedMock: [HomeCategory] = [
        .init(key: "similar",             title: "Similar",              subtitle: "Yesterday • Seattle, WA", iconAsset: "Home/ic_cat_similar",           photoCount: 15, sizeMB: 48,  isVideo: false),
        .init(key: "duplicates",          title: "Duplicates",           subtitle: "Last week • iPhone",      iconAsset: "Home/ic_cat_duplicates",        photoCount: 8,  sizeMB: 22,  isVideo: false),
        .init(key: "similar_screenshots", title: "Similar Screenshots",  subtitle: "Today • Screenshots",     iconAsset: "Home/ic_cat_screenshots",       photoCount: 24, sizeMB: 36,  isVideo: false),
        .init(key: "similar_videos",      title: "Similar Videos",       subtitle: "Last month • iPhone",     iconAsset: "Home/ic_cat_similar_videos",    photoCount: 5,  sizeMB: 124, isVideo: true),
        .init(key: "other_screenshots",   title: "Other Screenshots",    subtitle: "All time • Screenshots",  iconAsset: "Home/ic_cat_other_screenshots", photoCount: 42, sizeMB: 58,  isVideo: false),
        .init(key: "chat_photos",         title: "Chat Photos",          subtitle: "WhatsApp · Messages",     iconAsset: "Home/ic_cat_chat_photos",       photoCount: 31, sizeMB: 18,  isVideo: false),
        .init(key: "videos_organizer",    title: "Videos Organizer",     subtitle: "All time • iPhone",       iconAsset: "Home/ic_cat_videos_organizer",  photoCount: 12, sizeMB: 380, isVideo: true),
        .init(key: "other",               title: "Other",                subtitle: "Misc photos",             iconAsset: "Home/ic_cat_other",             photoCount: 7,  sizeMB: 16,  isVideo: false),
    ]

    static let emptyMock: [HomeCategory] = populatedMock.map {
        .init(key: $0.key, title: $0.title, subtitle: "Tap to scan", iconAsset: $0.iconAsset, photoCount: 0, sizeMB: 0, isVideo: $0.isVideo)
    }
}

#Preview("Populated") {
    HomeView()
}

#Preview("Empty") {
    struct Wrapper: View {
        var body: some View {
            HomeView()
        }
    }
    return Wrapper()
}
