import SwiftUI
import AVKit
import Photos
import PhotosUI
import Observation
import LibEarnMoneyIOS

// Figma cluster: 2005:22138 (entry) → 2005:22335 (confirm) → 2005:23000 (progress)
// → 2005:22563 (result). Daily free quota of 2 (key-rolled at local midnight);
// premium bypasses. Interstitial fires after a successful Result via
// AdUnits.interGlobal (premium-gated, lib 30s cap).
//
// State machine:
//   .empty       — no video picked yet, prompt to pick
//   .ready       — video loaded, choose quality + Start
//   .confirm     — modal asking to spend a daily slot
//   .progress    — ring + Cancel Process
//   .result      — Replace Original / Keep Both
struct CompressView: View {
    @State private var compressor = VideoCompressor()
    @State private var videoLibrary = VideoLibraryService()
    @State private var step: Step = .empty
    @State private var loadingPicked = false
    @State private var pickedURL: URL?
    @State private var pickedFileName: String = ""
    @State private var pickedSizeBytes: Int = 0
    @State private var quality: VideoCompressor.Quality = .balanced
    @State private var compressedURL: URL?
    @State private var compressedSizeBytes: Int = 0
    @State private var showCancelConfirm = false
    @State private var showPaywall = false
    @State private var showError: String?

    private enum Step { case empty, ready, confirm, progress, result }

    var body: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()

            switch step {
            case .empty:    videoGridView
            case .ready:    readyView
            case .progress: progressView
            case .result:   resultView
            case .confirm:  readyView  // confirm is an overlay; ready stays visible underneath
            }

            if step == .confirm {
                confirmModal
                    .transition(.opacity)
            }
            if showCancelConfirm {
                cancelConfirmModal
                    .transition(.opacity)
            }
            if loadingPicked {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.3)
                }
            }
        }
        // Per-state bottom ad (scenario): landing banner_compress, ready/confirm
        // banner_video_compress, compressing native_video_compress, result
        // banner_success_view_compress. Sits above the tab bar.
        .safeAreaInset(edge: .bottom) { compressAd }
        .bottomChromeInset()
        .task { await videoLibrary.load() }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .alert("Compress error", isPresented: Binding(
            get: { showError != nil },
            set: { if !$0 { showError = nil } }
        )) {
            Button("OK", role: .cancel) { showError = nil }
        } message: { Text(showError ?? "") }
        .animation(.easeInOut(duration: 0.25), value: step)
        .animation(.easeInOut(duration: 0.22), value: showCancelConfirm)
    }

    // Bottom ad whose unit depends on the compress step (scenario rows 3/5/6/7).
    @ViewBuilder
    private var compressAd: some View {
        switch step {
        case .empty:           BannerAdView(adUnitID: AdUnits.bannerCompress)
        case .ready, .confirm: BannerAdView(adUnitID: AdUnits.bannerVideoCompress)
        case .progress:        NativeAdView(adUnitID: AdUnits.nativeVideoCompress, height: 120)
        case .result:          BannerAdView(adUnitID: AdUnits.bannerSuccessCompress)
        }
    }

    // MARK: - Video grid (entry — Figma 2005:22138)

    private let gridColumns = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]

    private var videoGridView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Compress")
                    .font(.custom("Inter-SemiBold", size: 18))
                    .foregroundStyle(Color(hex: 0x0F0F0F))
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 48)

            HStack(spacing: 8) {
                Text("\(videoLibrary.videos.count) Videos")
                    .font(.custom("Inter-Medium", size: 14))
                    .foregroundStyle(Color(hex: 0x00091D))
                Text(formatBytes(videoLibrary.totalBytes))
                    .font(.custom("Inter-Medium", size: 14))
                    .foregroundStyle(AppColor.brandPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if videoLibrary.auth == .denied {
                permissionGate
            } else if videoLibrary.videos.isEmpty {
                if videoLibrary.loading {
                    Spacer()
                    ProgressView().tint(AppColor.brandPrimary)
                    Spacer()
                } else {
                    emptyVideosView
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 11) {
                        ForEach(videoLibrary.videos) { v in
                            videoCell(v)
                                .onTapGesture { Task { await selectVideo(v) } }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 120)
                }
            }
        }
    }

    private func videoCell(_ v: VideoLibraryService.VideoItem) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { PHAssetThumbnail(localIdentifier: v.id, targetSize: CGSize(width: 400, height: 400)) }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(alignment: .bottomLeading) { badge(Self.durationString(v.duration), bold: false).padding(8) }
            .overlay(alignment: .bottomTrailing) { badge(formatBytes(v.sizeBytes), bold: true).padding(8) }
            .contentShape(Rectangle())
    }

    private func badge(_ text: String, bold: Bool) -> some View {
        Text(text)
            .font(.custom(bold ? "Inter-Bold" : "Inter-Medium", size: bold ? 11 : 10))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.6)))
    }

    private var emptyVideosView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "video.slash")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.textMuted)
            Text("No videos found")
                .font(.custom("Inter-Bold", size: 18))
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionGate: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.brandPrimary)
            Text("Photos access required")
                .font(.custom("Inter-Bold", size: 18))
                .foregroundStyle(AppColor.textPrimary)
            Text("Allow access so iCleaner can list your videos to compress.")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Text("Open Settings")
                    .font(.custom("Inter-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.brandPrimary))
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Tap a video → check quota → resolve its URL → quality screen.
    private func selectVideo(_ v: VideoLibraryService.VideoItem) async {
        guard compressor.canCompressMore else { showPaywall = true; return }
        loadingPicked = true
        defer { loadingPicked = false }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [v.id], options: nil).firstObject,
              let url = await Self.videoURL(for: asset) else {
            showError = "Couldn't open this video."
            return
        }
        pickedURL = url
        pickedFileName = url.lastPathComponent
        pickedSizeBytes = v.sizeBytes
        step = .ready
    }

    nonisolated private static func videoURL(for asset: PHAsset) async -> URL? {
        let opts = PHVideoRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                cont.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func durationString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Ready state (video loaded)

    private var readyView: some View {
        VStack(spacing: 20) {
            navBar
            ScrollView {
                VStack(spacing: 20) {
                    filePreviewCard
                    qualityPicker
                    estimatedBadge
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            startButton
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
    }

    private var navBar: some View {
        HStack {
            Button(action: resetToEmpty) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 24, height: 24)
            }
            Spacer()
            Text("Compress")
                .font(.custom("Inter-Bold", size: 20))
                .tracking(20 * -0.025)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Color.clear.frame(width: 24, height: 24)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    private var filePreviewCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColor.brandPrimary.opacity(0.10))
                Image(systemName: "video.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColor.brandPrimary)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(pickedFileName)
                    .font(.custom("Inter-SemiBold", size: 14))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: Int64(pickedSizeBytes), countStyle: .file))
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.brandPrimary.opacity(0.2), lineWidth: 1)
        )
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quality")
                .font(.custom("Inter-Bold", size: 12))
                .tracking(12 * 0.05)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textMuted)
            VStack(spacing: 0) {
                ForEach(VideoCompressor.Quality.allCases) { q in
                    QualityRow(quality: q, selected: quality == q)
                        .contentShape(Rectangle())
                        .onTapGesture { quality = q }
                    if q != VideoCompressor.Quality.allCases.last {
                        Rectangle()
                            .fill(Color(hex: 0xF1F5F9))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.surfaceBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xE2E8F0), lineWidth: 1)
            )
        }
    }

    private var estimatedBadge: some View {
        let estimated = VideoCompressor.estimatedOutputBytes(inputBytes: pickedSizeBytes, quality: quality)
        let savings = pickedSizeBytes - estimated
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Estimated")
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(AppColor.textSecondary)
                Text(ByteCountFormatter.string(fromByteCount: Int64(estimated), countStyle: .file))
                    .font(.custom("Inter-Bold", size: 22))
                    .foregroundStyle(AppColor.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Save")
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(AppColor.textSecondary)
                Text("≈ \(ByteCountFormatter.string(fromByteCount: Int64(max(0, savings)), countStyle: .file))")
                    .font(.custom("Inter-Bold", size: 22))
                    .foregroundStyle(AppColor.success)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.success.opacity(0.06))
        )
    }

    private var startButton: some View {
        Button(action: handleStartTap) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                Text("Start Compression")
            }
            .font(.custom("Inter-Bold", size: 16))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.brandPrimary)
                    .shadow(color: AppColor.brandPrimary.opacity(0.3), radius: 10, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirm modal

    private var confirmModal: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { step = .ready }

            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 36))
                    .foregroundStyle(AppColor.brandPrimary)
                    .padding(.bottom, 8)

                Text("Confirm Compression?")
                    .font(.custom("Inter-Bold", size: 20))
                    .foregroundStyle(Color(hex: 0x0F172A))

                let estimated = VideoCompressor.estimatedOutputBytes(inputBytes: pickedSizeBytes, quality: quality)
                let savings = pickedSizeBytes - estimated
                Text("The video will be compressed. You'll save \(ByteCountFormatter.string(fromByteCount: Int64(max(0, savings)), countStyle: .file)) of storage.")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color(hex: 0x64748B))
                    .multilineTextAlignment(.center)

                if !PremiumGate.isPremium {
                    Text("Today's uses: \(compressor.usesUsedToday)/\(VideoCompressor.dailyLimit)")
                        .font(.custom("Inter-Medium", size: 13))
                        .foregroundStyle(AppColor.warning)
                        .padding(.top, 4)
                }

                VStack(spacing: 12) {
                    Button(action: { step = .progress; Task { await runExport() } }) {
                        Text("Compress Now")
                            .font(.custom("Inter-Bold", size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppColor.brandPrimary)
                            )
                    }
                    Button(action: { step = .ready }) {
                        Text("Cancel")
                            .font(.custom("Inter-SemiBold", size: 16))
                            .foregroundStyle(Color(hex: 0x64748B))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.top, 16)
            }
            .padding(24)
            .frame(width: 326)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppColor.surfaceBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppColor.brandPrimary, lineWidth: 1)
            )
        }
    }

    // MARK: - Progress

    private var progressView: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                progressRing
                Text("Compressing your video…")
                    .font(.custom("Inter-Bold", size: 20))
                    .foregroundStyle(Color(hex: 0x333333))
                Text("Original \(ByteCountFormatter.string(fromByteCount: Int64(pickedSizeBytes), countStyle: .file))   →   Target \(ByteCountFormatter.string(fromByteCount: Int64(VideoCompressor.estimatedOutputBytes(inputBytes: pickedSizeBytes, quality: quality)), countStyle: .file))")
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                cancelProcessButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: 0xF8FAFC), lineWidth: 20)
                .frame(width: 220, height: 220)
            Circle()
                .trim(from: 0, to: compressor.progress)
                .stroke(AppColor.brandPrimary,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .frame(width: 220, height: 220)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: compressor.progress)
            Circle()
                .fill(AppColor.brandPrimary)
                .frame(width: 176, height: 176)
                .overlay(
                    Text("\(Int(compressor.progress * 100))%")
                        .font(.custom("Inter-Bold", size: 48))
                        .tracking(48 * -0.025)
                        .foregroundStyle(.white)
                )
                .shadow(color: .black.opacity(0.25), radius: 25, x: 0, y: 25)
        }
    }

    private var cancelProcessButton: some View {
        Button(action: { showCancelConfirm = true }) {
            Text("Cancel Process")
                .font(.custom("Inter-SemiBold", size: 14))
                .foregroundStyle(AppColor.danger)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(
                    Capsule().stroke(AppColor.danger.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var cancelConfirmModal: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { showCancelConfirm = false }
            VStack(spacing: 8) {
                Text("Are you sure?")
                    .font(.custom("Inter-Bold", size: 20))
                    .foregroundStyle(Color(hex: 0x0F172A))
                Text("Do you really want to cancel the current process? Any unsaved progress will be lost.")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color(hex: 0x64748B))
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    Button(action: {
                        showCancelConfirm = false
                        compressor.cancel()
                    }) {
                        Text("Yes, Cancel")
                            .font(.custom("Inter-Bold", size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppColor.danger)
                            )
                    }
                    Button(action: { showCancelConfirm = false }) {
                        Text("No, Go Back")
                            .font(.custom("Inter-SemiBold", size: 16))
                            .foregroundStyle(Color(hex: 0x64748B))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.top, 16)
            }
            .padding(24)
            .frame(width: 326)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppColor.surfaceBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppColor.danger, lineWidth: 1)
            )
        }
    }

    // MARK: - Result

    private var resultView: some View {
        let savings = pickedSizeBytes - compressedSizeBytes
        let pct = pickedSizeBytes > 0 ? Int(Double(savings) / Double(pickedSizeBytes) * 100) : 0
        return VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(AppColor.success.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .blur(radius: 32)
                Circle()
                    .fill(AppColor.success)
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.top, 40)

            Text("Compression Complete!")
                .font(.custom("Inter-Bold", size: 24))
                .foregroundStyle(AppColor.textPrimary)
            Text("Saved \(pct)% — \(ByteCountFormatter.string(fromByteCount: Int64(max(0, savings)), countStyle: .file)) freed")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(AppColor.textSecondary)

            HStack(spacing: 16) {
                statTile(label: "Original", value: ByteCountFormatter.string(fromByteCount: Int64(pickedSizeBytes), countStyle: .file))
                statTile(label: "Compressed", value: ByteCountFormatter.string(fromByteCount: Int64(compressedSizeBytes), countStyle: .file))
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button(action: { Task { await saveAndDismiss(deleteSource: true) } }) {
                    Text("Replace Original")
                        .font(.custom("Inter-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppColor.brandPrimary)
                        )
                }
                Button(action: { Task { await saveAndDismiss(deleteSource: false) } }) {
                    Text("Keep Both")
                        .font(.custom("Inter-SemiBold", size: 16))
                        .foregroundStyle(AppColor.brandPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppColor.brandPrimary, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.custom("Inter-Bold", size: 18))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.brandPrimary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func handleStartTap() {
        guard compressor.canCompressMore else {
            showPaywall = true
            return
        }
        step = .confirm
    }

    private func runExport() async {
        guard let pickedURL else { step = .ready; return }
        do {
            let outURL = try await compressor.compress(sourceURL: pickedURL, quality: quality)
            compressedURL = outURL
            compressedSizeBytes = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
            step = .result
        } catch VideoCompressor.CompressError.cancelled {
            step = .ready
        } catch {
            showError = error.localizedDescription
            step = .ready
        }
    }

    private func saveAndDismiss(deleteSource: Bool) async {
        guard let compressedURL else { return }
        do {
            // For MVP we don't track the source PHAsset (we only have a temp file URL
            // from PhotosPicker). "Replace Original" therefore just saves the compressed
            // copy; full delete-source flow requires PHPickerViewController + PHAsset
            // bridge (Part B polish). User can clean the original via Similar/Quick Clean.
            _ = deleteSource
            try await compressor.saveToPhotos(fileURL: compressedURL, deletingSource: nil)
            fireResultInterstitial()
            resetToEmpty()
        } catch {
            showError = error.localizedDescription
        }
    }

    private func fireResultInterstitial() {
        guard !PremiumGate.isPremium,
              let vc = AdHelpers.topViewController() else { return }
        AdManager.shared.showInterstitialAd(
            adUnitID: AdUnits.interGlobal,
            from: vc,
            completion: nil
        )
    }

    private func resetToEmpty() {
        pickedURL = nil
        pickedFileName = ""
        pickedSizeBytes = 0
        compressedURL = nil
        compressedSizeBytes = 0
        quality = .balanced
        step = .empty
    }
}

// MARK: - Subviews

private struct QualityRow: View {
    let quality: VideoCompressor.Quality
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(selected ? AppColor.brandPrimary : Color(hex: 0xCBD5E1),
                                  lineWidth: selected ? 6 : 2)
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(quality.title)
                        .font(.custom("Inter-SemiBold", size: 15))
                        .foregroundStyle(AppColor.textPrimary)
                    if quality.isRecommended {
                        Text("Recommended")
                            .font(.custom("Inter-Bold", size: 10))
                            .tracking(10 * 0.05)
                            .textCase(.uppercase)
                            .foregroundStyle(AppColor.brandPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColor.brandPrimary.opacity(0.10)))
                    }
                }
                Text(quality.subtitle)
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
        }
        .padding(16)
    }
}

// MARK: - Video library (all device videos for the compress grid)

@MainActor
@Observable
final class VideoLibraryService {
    struct VideoItem: Identifiable {
        let id: String       // PHAsset.localIdentifier
        let duration: Double
        let sizeBytes: Int
    }
    enum Auth { case notDetermined, denied, authorized }

    private(set) var auth: Auth
    private(set) var videos: [VideoItem] = []
    private(set) var loading = false

    var totalBytes: Int { videos.reduce(0) { $0 + $1.sizeBytes } }

    init() { auth = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }

    func load() async {
        if auth == .notDetermined {
            auth = Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
        }
        guard auth == .authorized, videos.isEmpty else { return }
        loading = true
        videos = await Task.detached(priority: .userInitiated) { Self.fetchVideos() }.value
        loading = false
    }

    private static func map(_ s: PHAuthorizationStatus) -> Auth {
        switch s {
        case .authorized, .limited: return .authorized
        case .notDetermined:        return .notDetermined
        default:                    return .denied
        }
    }

    nonisolated private static func fetchVideos() -> [VideoItem] {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: opts)
        var items: [VideoItem] = []
        result.enumerateObjects { asset, _, _ in
            let size = PHAssetResource.assetResources(for: asset)
                .first
                .flatMap { $0.value(forKey: "fileSize") as? Int } ?? 0
            items.append(VideoItem(id: asset.localIdentifier, duration: asset.duration, sizeBytes: size))
        }
        return items
    }
}

#Preview {
    CompressView()
}
