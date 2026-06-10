import SwiftUI
import Photos
import LibEarnMoneyIOS

// 1-tap cleanup across ALL detected similar groups. Auto-selects every
// non-Best-Match photo in every group. Presented from Home's sticky
// "Quick Clean (X MB)" CTA.
//
// State machine: scanning → confirm → cleaning → success / empty / permGate.
// Reuses SimilarCleaningView (parameterized title). Interstitial after success
// via lib's 30s global cap (same pattern as SimilarFlowView).
//
// Figma: `2005:23105` (confirm popup), `2005:23265` (cleaning your phone),
// `2005:23298` (success — 3 stat tiles).
struct QuickCleanFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photoLibrary = PhotoLibraryService()
    @State private var step: Step = .scanning
    @State private var deletableAssets: [PHAsset] = []
    @State private var deletableKB: Int = 0
    @State private var deletablePhotoCount: Int = 0
    @State private var deletableGroupCount: Int = 0
    @State private var deleteError: String?
    @State private var showPaywall: Bool = false

    private enum Step { case scanning, permissionGate, confirm, empty, cleaning, success }

    var body: some View {
        ZStack {
            switch step {
            case .scanning, .cleaning, .empty, .permissionGate, .success:
                // Scaffold uses brand-tinted bg so the confirm modal pops on top
                // with proper contrast (matches Figma popup-over-home framing).
                AppColor.surfaceBackground.ignoresSafeArea()
            case .confirm:
                Color.black.opacity(0.5).ignoresSafeArea()
            }

            switch step {
            case .scanning:           scanningView
            case .permissionGate:     permissionGateView
            case .confirm:            confirmModal
            case .empty:              emptyView
            case .cleaning:
                SimilarCleaningView(
                    title: L("quickclean.cleaning"),
                    performDelete: performQuickClean,
                    onComplete: { success in
                        // Only show success if the OS actually deleted. Denying the
                        // system prompt → back to confirm.
                        step = success ? .success : .confirm
                    }
                )
            case .success:
                QuickCleanSuccessView(
                    cleanedSizeLabel: CleanSize.label(kb: deletableKB),
                    photosOptimized: deletablePhotoCount,
                    memoryBoostedLabel: CleanSize.label(kb: deletableKB * 4),  // boost ≈ deleted × 4 (cache + thumbs)
                    onContinue: showInterstitialThenDismiss
                )
            }
        }
        .alert(L("flow.deleteErrorTitle"), isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .task { await bootstrap() }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Lifecycle

    private func bootstrap() async {
        if photoLibrary.authStatus == .notDetermined {
            await photoLibrary.requestAuthorization()
        }
        guard photoLibrary.authStatus.canRead else {
            step = .permissionGate
            return
        }
        FlowGate.showStartAd()   // ad on feature entry (free users)
        // Same canonical Similar config as the Home card → the popup's size equals
        // the "Quick Clean (X)" CTA number (both are the Similar non-Best total).
        let groups = await photoLibrary.detectSimilarGroups(config: .similar)
        guard !groups.isEmpty else {
            step = .empty
            return
        }
        // Auto-select all non-Best-Match across every group; sum their REAL sizes.
        var assets: [PHAsset] = []
        var totalKB = 0
        for g in groups {
            for (idx, asset) in g.assets.enumerated() where idx != g.bestMatchIndex {
                assets.append(asset)
                totalKB += idx < g.sizesKB.count ? g.sizesKB[idx] : Int(asset.estimatedSizeKB)
            }
        }
        deletableAssets = assets
        deletablePhotoCount = assets.count
        deletableKB = totalKB
        deletableGroupCount = groups.count
        step = .confirm
    }

    // Returns true only when the OS confirmed the deletion (false if the user
    // denied the system delete prompt) — caller stays on confirm otherwise.
    private func performQuickClean() async -> Bool {
        guard !deletableAssets.isEmpty else { return false }
        do {
            try await photoLibrary.delete(assets: deletableAssets)
            return true
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return false
        } catch {
            deleteError = (error as NSError).localizedDescription
            return false
        }
    }

    // Show the post-clean interstitial only if one is ready, then dismiss (never
    // block on a "loading ad" spinner).
    private func showInterstitialThenDismiss() {
        FlowGate.showInterstitial(onDone: { dismiss() })
    }

    // MARK: - Step subviews

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(AppColor.brandPrimary)
                .scaleEffect(1.4)
            Text(L("quickclean.scanning"))
                .font(.custom("Inter-SemiBold", size: 14))
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var permissionGateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.brandPrimary)
            Text(L("compress.permTitle"))
                .font(.custom("Inter-Bold", size: 22))
                .foregroundStyle(AppColor.textPrimary)
            Text(L("quickclean.permBody"))
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: { photoLibrary.opensSettings() }) {
                Text(L("common.openSettings"))
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
                Text(L("common.back"))
                    .font(.custom("Inter-SemiBold", size: 14))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.success)
            Text(L("quickclean.emptyTitle"))
                .font(.custom("Inter-Bold", size: 20))
                .foregroundStyle(AppColor.textPrimary)
            Text(L("quickclean.emptyBody"))
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: { dismiss() }) {
                Text(L("common.done"))
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

    private var confirmModal: some View {
        QuickCleanConfirmModal(
            sizeLabel: CleanSize.label(kb: deletableKB),
            photoCount: deletablePhotoCount,
            groupCount: deletableGroupCount,
            onCancel: { dismiss() },
            // Final step → free users hit the paywall instead of cleaning.
            onClean: { if FlowGate.requiresPaywall { showPaywall = true } else { step = .cleaning } }
        )
    }
}

#Preview {
    QuickCleanFlowView()
}
