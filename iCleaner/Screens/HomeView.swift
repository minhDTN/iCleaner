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

    @State private var photoLibrary = PhotoLibraryService()
    @State private var previewIDs: [String: [String]] = [:]   // per-category card thumbnails
    @State private var stats: [String: CardStat] = [:]        // per-category REAL count + size

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

    // The card's preview photos for `cat` — the newest assets matching that
    // category's own detection config, so the card shows the same KIND of photos
    // (videos for video cards, screenshots for screenshot cards, chat photos for
    // Chat Photos) drawn from the same pool the detail scans. nil → placeholder.
    private func assetIDs(for cat: HomeCategory) -> CardAssets? {
        guard let ids = previewIDs[cat.key], !ids.isEmpty else { return nil }
        func at(_ i: Int) -> String? { i < ids.count ? ids[i] : nil }
        return CardAssets(best: at(0), dup1: at(1), dup2: at(2))
    }

    // Scan each category once (concurrently, off main) for its preview thumbnails
    // AND its REAL count + size — so the cards stop showing hardcoded mock numbers.
    // Called on appear and after a SimilarFlow dismiss (where Photos permission is
    // first granted), so cards refresh on return.
    private func reloadThumbnails() async {
        guard photoLibrary.authStatus.canRead else { return }
        let cats = HomeCategory.populatedMock
        // Phase 1: light scans (metadata clustering + sizes) → cards appear quickly
        // even on a 100GB+ library. Phase 2: the heavy per-image analysis (Duplicates
        // content-hash) runs AFTER, so it never blocks the other cards from showing.
        await scanCategories(cats.filter { !$0.isHeavyScan })
        await scanCategories(cats.filter { $0.isHeavyScan })
    }

    // Scan a set of categories concurrently, applying each card's stats AS IT
    // FINISHES (live fill-in), not all-at-once after the slowest one.
    private func scanCategories(_ cats: [HomeCategory]) async {
        await withTaskGroup(of: (String, [String], CardStat).self) { group in
            for cat in cats {
                group.addTask {
                    let r = await photoLibrary.categoryScan(config: cat.detectionConfig, previewLimit: 3)
                    return (cat.key, r.previewIDs, CardStat(count: r.count, sizeKB: r.totalKB, reclaimableKB: r.reclaimableKB))
                }
            }
            for await (key, p, s) in group {
                previewIDs[key] = p
                stats[key] = s
            }
        }
    }

    // nil until this category's real scan lands → the card shows a "scanning" state
    // rather than a misleading hardcoded number on first launch.
    private func stat(for cat: HomeCategory) -> CardStat? { stats[cat.key] }

    // Quick Clean frees the non-Best-Match photos of the Similar groups — the SAME
    // value the confirm popup shows (both derive from the identical Similar scan), so
    // the CTA number and the popup number always match. "…" while still scanning.
    private var quickCleanLabel: String {
        guard let kb = stats["similar"]?.reclaimableKB else { return "…" }
        return CleanSize.label(kb: kb)
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
                            stat: stat(for: cat),
                            assets: assetIDs(for: cat),
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
        .bottomChromeInset()
        .task { await reloadThumbnails() }
        .fullScreenCover(item: $openedCategory, onDismiss: { Task { await reloadThumbnails() } }) { cat in
            SimilarFlowView(categoryTitle: cat.title, categoryTitleKey: cat.titleKey, detectionConfig: cat.detectionConfig)
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
            Text(L("home.storage"))
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
                Text(L("home.quickClean", quickCleanLabel))
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
    var stat: CardStat? = nil       // nil → still scanning (show loading, not mock)
    var assets: CardAssets? = nil   // real PHAsset IDs; nil → placeholder gradient
    var onReviewTap: () -> Void

    // Shared horizontal inset for photo stack + Review Group so both align to
    // the same left/right margin inside the card.
    private let cardInset: CGFloat = 16

    private var isLoading: Bool { stat == nil }
    private var count: Int { stat?.count ?? 0 }
    private var sizeLabel: String { stat.map { CleanSize.label(kb: $0.sizeKB) } ?? "…" }

    var body: some View {
        VStack(spacing: 10) {
            titleRow
            if count > 0 {
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
                Text(L(category.titleKey))
                    .font(.custom("Inter-SemiBold", size: 16))
                    .foregroundStyle(Color(hex: 0x0F172A))
                Text(isLoading ? L("home.scanning") : (count == 0 ? L("home.tapToScan") : L(category.subtitleKey)))
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
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColor.brandPrimary)
                    } else {
                        Text(sizeLabel)
                            .font(.custom("Inter-Bold", size: 16))
                            .foregroundStyle(AppColor.brandPrimary)
                    }
                }
                if !isLoading {
                    Text(L(category.isVideo ? "home.videos" : "home.photos", count))
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(Color(hex: 0x94A3B8))
                }
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

    // Flexible widths (not fixed 198.67/105.33) so the stack stretches to the
    // card's real width and its left/right inset matches the Review Group button
    // exactly. Figma ratio Best:Dup = 198.67 : 105.33 of the 316 inner width.
    private var photoStack: some View {
        GeometryReader { geo in
            let gap: CGFloat = 12
            let avail = geo.size.width - gap
            HStack(spacing: gap) {
                bestPhoto
                    .frame(width: avail * (198.67 / 316))
                duplicateStack
                    .frame(width: avail * (105.33 / 316))
            }
        }
        .frame(height: 128)
        .padding(.horizontal, cardInset)
    }

    private var bestPhoto: some View {
        ZStack(alignment: .topLeading) {
            thumbnail(assetID: assets?.best, seed: category.title.count)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if category.isVideo {
                videoPlayBadge
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Best Match pill only for Similar/Duplicate-style cards (bug: it
            // wrongly appeared on browse buckets like Other / Screenshots).
            if category.hasBestMatch {
                bestMatchPill
                    .padding(8)
            }
        }
    }

    // Real PHAsset thumbnail when an ID is available, else placeholder gradient.
    @ViewBuilder
    private func thumbnail(assetID: String?, seed: Int) -> some View {
        if let assetID {
            PHAssetThumbnail(localIdentifier: assetID, targetSize: CGSize(width: 400, height: 400))
        } else {
            placeholderImage(seed: seed)
        }
    }

    // Figma 15:1034: ⭐ star (Material Icons 10) + "Best Match" Bold 10 brand-
    // blue, gap 4, padding 2×8, white 90% bg + brand-blue stroke 20% + blur.
    private var bestMatchPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 9))
            Text(L("home.bestMatch"))
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
            thumbnail(assetID: assets?.dup1, seed: category.title.count + 1)
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
                Text("+\(max(1, count - 3))")
                    .font(.custom("Inter-Medium", size: 12))
                    .foregroundStyle(Color(hex: 0x64748B))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Deterministic colored gradient placeholder — shown only until real
    // PHAsset thumbnails load (or when Photos access hasn't been granted yet).
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
                Text(L("home.reviewGroup"))
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
        .padding(.horizontal, cardInset)
    }
}

// MARK: - Mock model

// Real PHAsset localIdentifiers a card shows: 1 best-match + 2 duplicates.
struct CardAssets {
    let best: String?
    let dup1: String?
    let dup2: String?
}

// Real per-category stats scanned from the library — replaces the hardcoded mock
// numbers on the Home cards. `count`/`sizeKB` cover only CLUSTERED photos for
// grouped categories (so the card matches the Review Group header); `reclaimableKB`
// is the non-Best-Match total that a 1-tap clean would free.
struct CardStat: Equatable {
    let count: Int
    let sizeKB: Int
    let reclaimableKB: Int
}

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

    // Duplicates content-hashes every image (expensive at scale), so its Home scan
    // runs in a deferred second phase and never blocks the lighter cards. (Chat now
    // counts from cache on Home — its OCR runs only inside the Chat screen.)
    var isHeavyScan: Bool { key == "duplicates" }
    var sizeLabel: String { sizeMB >= 1024 ? String(format: "%.1f GB", Double(sizeMB) / 1024) : "\(sizeMB) MB" }

    // Only Similar/Duplicate-style cards cluster into packs + show "Best Match".
    // Browse buckets (Other, Other Screenshots, Chat Photos, Videos Organizer)
    // are a flat manual list.
    var hasBestMatch: Bool {
        switch key {
        case "similar", "duplicates", "similar_screenshots", "similar_videos": return true
        default: return false
        }
    }

    // Localization key for the card title (the English `title` is still used for
    // SimilarFlow detection logic, so it stays as-is).
    var titleKey: String {
        switch key {
        case "similar":             return "home.cat.similar"
        case "duplicates":          return "home.cat.duplicates"
        case "similar_screenshots": return "home.cat.similarScreenshots"
        case "similar_videos":      return "home.cat.similarVideos"
        case "other_screenshots":   return "home.cat.otherScreenshots"
        case "chat_photos":         return "home.cat.chatPhotos"
        case "videos_organizer":    return "home.cat.videosOrganizer"
        default:                    return "home.cat.other"
        }
    }

    var subtitleKey: String {
        switch key {
        case "similar":             return "home.sub.similar"
        case "duplicates":          return "home.sub.duplicates"
        case "similar_screenshots": return "home.sub.similarScreenshots"
        case "similar_videos":      return "home.sub.similarVideos"
        case "other_screenshots":   return "home.sub.otherScreenshots"
        case "chat_photos":         return "home.sub.chatPhotos"
        case "videos_organizer":    return "home.sub.videosOrganizer"
        default:                    return "home.sub.other"
        }
    }

    // Detection rules per category so each card scans the right subset of the
    // library instead of every card showing the same pool.
    var detectionConfig: PhotoLibraryService.DetectionConfig {
        switch key {
        case "similar":
            // Similar photos: image bursts, screenshots excluded. Canonical config
            // shared with Quick Clean so the CTA number matches the popup.
            return .similar
        case "duplicates":
            // Exact duplicates: same dimensions + size.
            return .init(mediaType: .image, exactDuplicates: true, groupNoun: "Duplicates")
        case "similar_screenshots":
            // Similar screenshots: cluster look-alike screenshots into packs.
            return .init(mediaType: .image, screenshotsOnly: true, groupNoun: "Screenshots")
        case "other_screenshots":
            // ALL screenshots as a flat manual list (browse + delete by hand).
            return .init(mediaType: .image, screenshotsOnly: true, groupNoun: "Screenshots",
                         grouped: false, hasBestMatch: false)
        case "similar_videos":
            // Similar videos: time-window clustering into packs.
            return .init(mediaType: .video, groupNoun: "Videos")
        case "videos_organizer":
            // All videos as a flat manual list.
            return .init(mediaType: .video, groupNoun: "Videos", grouped: false, hasBestMatch: false)
        case "chat_photos":
            // Chat photos = ANY image (screenshot OR downloaded) that looks like a chat
            // conversation, classified by OCR + bubble-layout. Camera shots are
            // pre-filtered out cheaply. Flat list.
            return .init(mediaType: .image,
                         groupNoun: "Photos", grouped: false, hasBestMatch: false,
                         detectChat: true)
        case "other":
            // Misc photos as a flat manual list.
            return .init(mediaType: .image, excludeScreenshots: true, groupNoun: "Photos",
                         grouped: false, hasBestMatch: false)
        default:
            return .init()
        }
    }

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
