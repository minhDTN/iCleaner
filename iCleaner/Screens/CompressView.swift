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
    @State private var pickedDuration: Double = 0
    @State private var estimates: [VideoCompressor.Quality: Int] = [:]   // real per-quality output sizes
    @State private var previewPlayer: AVPlayer?
    @State private var compressedURL: URL?
    @State private var compressedSizeBytes: Int = 0
    @State private var showCancelConfirm = false
    @State private var showPaywall = false
    @State private var showError: String?
    @Environment(TabChrome.self) private var chrome: TabChrome?

    private enum Step { case empty, ready, confirm, progress, result, notification }

    var body: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()

            switch step {
            case .empty:        videoGridView
            case .ready:        readyView
            case .progress:     progressView
            case .result:       resultView
            case .notification: notificationView
            case .confirm:      readyView  // confirm is an overlay; ready stays visible underneath
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
        // Per-step bottom ad is published to the shared chrome so it renders BELOW
        // the tab bar (same place as Home), not above it. Scenario: landing
        // banner_compress, ready/confirm banner_video_compress, compressing
        // native_video_compress, result banner_success_view_compress.
        .bottomChromeInset()
        .onChange(of: step, initial: true) { _, s in
            let ad = Self.compressAd(for: s)
            chrome?.compressAdUnit = ad.unit
            chrome?.compressAdIsNative = ad.isNative
        }
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

    // Bottom ad unit for each compress step (scenario rows 3/5/6/7); rendered by
    // the chrome below the tab bar. Progress uses a native, the others a banner.
    private static func compressAd(for step: Step) -> (unit: String?, isNative: Bool) {
        switch step {
        case .empty:           return (AdUnits.bannerCompress, false)
        case .ready, .confirm: return (AdUnits.bannerVideoCompress, false)
        case .progress:        return (AdUnits.nativeVideoCompress, true)
        case .result:          return (AdUnits.bannerSuccessCompress, false)
        case .notification:    return (nil, false)
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
        pickedDuration = v.duration
        previewPlayer = AVPlayer(url: url)
        await computeEstimates(url: url, originalBytes: v.sizeBytes)
        step = .ready
    }

    // Ask the system for the real exported size of each quality so the screen shows
    // what the compression will actually produce (computed under the loading spinner).
    private func computeEstimates(url: URL, originalBytes: Int) async {
        var result: [VideoCompressor.Quality: Int] = [:]
        for q in VideoCompressor.Quality.allCases {
            result[q] = await compressor.estimateOutput(sourceURL: url, quality: q, originalBytes: originalBytes)
        }
        estimates = result
    }

    // Selected quality's real estimated output size (0 until computed).
    private var estimatedBytes: Int { estimates[quality] ?? 0 }

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
                    selectedFileCard
                    qualityPicker
                    savingsRow
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
        HStack(spacing: 8) {
            Button(action: resetToEmpty) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0F0F0F))
                    .frame(width: 24, height: 24)
            }
            Text("Video Compress")
                .font(.custom("Inter-SemiBold", size: 18))
                .foregroundStyle(Color(hex: 0x0F0F0F))
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    // "Selected File" — a playable preview of the chosen video (Figma 2005:22335 /
    // compress preview). Tap to play with native controls; duration + size badges
    // sit in the corners.
    private var selectedFileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Selected File")
                    .font(.custom("Inter-SemiBold", size: 16))
                    .foregroundStyle(Color(hex: 0x0F0F0F))
                Spacer()
                Button(action: resetToEmpty) {
                    Text("Change File")
                        .font(.custom("Inter-SemiBold", size: 14))
                        .foregroundStyle(AppColor.brandPrimary)
                }
                .buttonStyle(.plain)
            }

            ZStack {
                Group {
                    if let previewPlayer {
                        VideoPlayer(player: previewPlayer)
                    } else {
                        Color(hex: 0xEDEDF9)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    badge(Self.durationString(pickedDuration), bold: false).padding(8)
                }
                .overlay(alignment: .bottomTrailing) {
                    badge(formatBytes(pickedSizeBytes), bold: true).padding(8)
                }
            }

            Text(pickedFileName)
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compression Quality")
                .font(.custom("Inter-SemiBold", size: 16))
                .foregroundStyle(Color(hex: 0x0F0F0F))
            ForEach(VideoCompressor.Quality.allCases) { q in
                QualityRow(quality: q, selected: quality == q, inputBytes: pickedSizeBytes, estimatedBytes: estimates[q] ?? 0)
                    .contentShape(Rectangle())
                    .onTapGesture { quality = q }
            }
        }
    }

    // POTENTIAL SAVINGS | ORIGINAL → ESTIMATED (Figma 2005:22335 footer row).
    private var savingsRow: some View {
        let estimated = estimatedBytes
        let savings = max(0, pickedSizeBytes - estimated)
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("POTENTIAL SAVINGS")
                    .font(.custom("Inter-SemiBold", size: 10)).tracking(0.5)
                    .foregroundStyle(AppColor.textMuted)
                Text(formatBytes(savings))
                    .font(.custom("Inter-Bold", size: 18))
                    .foregroundStyle(AppColor.textPrimary)
            }
            Spacer()
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ORIGINAL")
                        .font(.custom("Inter-SemiBold", size: 10)).tracking(0.5)
                        .foregroundStyle(AppColor.textMuted)
                    Text(formatBytes(pickedSizeBytes))
                        .font(.custom("Inter-SemiBold", size: 13))
                        .foregroundStyle(AppColor.textPrimary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.textMuted)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ESTIMATED")
                        .font(.custom("Inter-SemiBold", size: 10)).tracking(0.5)
                        .foregroundStyle(AppColor.brandPrimary)
                    Text(formatBytes(estimated))
                        .font(.custom("Inter-SemiBold", size: 13))
                        .foregroundStyle(AppColor.brandPrimary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: 0xE2E8F0), lineWidth: 1)
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
        let savings = max(0, pickedSizeBytes - estimatedBytes)
        let savingsText = ByteCountFormatter.string(fromByteCount: Int64(savings), countStyle: .file)
        return ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { step = .ready }

            VStack(spacing: 0) {
                // No icon (per design) — title leads the card.
                Text("Confirm Compression?")
                    .font(.custom("Inter-Bold", size: 22))
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .multilineTextAlignment(.center)

                // "You will save 38 MB of storage." — the size is bold.
                (
                    Text("The video will be compressed. You will save ")
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundStyle(Color(hex: 0x64748B))
                    + Text(savingsText)
                        .font(.custom("Inter-Bold", size: 14))
                        .foregroundStyle(Color(hex: 0x0F172A))
                    + Text(" of storage.")
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundStyle(Color(hex: 0x64748B))
                )
                .multilineTextAlignment(.center)
                .padding(.top, 12)

                if !PremiumGate.isPremium {
                    Text("Today's uses: \(compressor.usesUsedToday)/\(VideoCompressor.dailyLimit)")
                        .font(.custom("Inter-SemiBold", size: 14))
                        .foregroundStyle(AppColor.brandPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color(hex: 0xF6F7FF)))
                        .overlay(Capsule().stroke(AppColor.brandPrimary.opacity(0.25), lineWidth: 1))
                        .padding(.top, 20)
                }

                Button(action: { step = .progress; Task { await runExport() } }) {
                    Text("Compress Now")
                        .font(.custom("Inter-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColor.brandPrimary)
                                .shadow(color: AppColor.brandPrimary.opacity(0.2), radius: 12, x: 0, y: 8)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 24)

                Button(action: { step = .ready }) {
                    Text("Cancel")
                        .font(.custom("Inter-SemiBold", size: 16))
                        .foregroundStyle(Color(hex: 0x64748B))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(24)
            .frame(width: 326)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppColor.surfaceBackground)
                    .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppColor.brandPrimary.opacity(0.15), lineWidth: 1)
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
                Text("Original \(ByteCountFormatter.string(fromByteCount: Int64(pickedSizeBytes), countStyle: .file))   →   Target \(ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file))")
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
        let savings = max(0, pickedSizeBytes - compressedSizeBytes)
        let pct = pickedSizeBytes > 0 ? Int(Double(savings) / Double(pickedSizeBytes) * 100) : 0
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    successCheckBadge(full: false)
                        .padding(.top, 48)
                        .padding(.bottom, 32)
                    Text("Compression Complete!")
                        .font(.custom("Inter-Bold", size: 24))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .padding(.bottom, 32)
                    resultCard(pct: pct)
                        .padding(.horizontal, 24)
                    Spacer(minLength: 24)
                }
            }
            VStack(spacing: 12) {
                Button(action: { Task { await saveAndDismiss(deleteSource: true) } }) {
                    Text("Replace Original")
                        .font(.custom("Inter-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColor.brandPrimary)
                                .shadow(color: AppColor.brandPrimary.opacity(0.2), radius: 10, x: 0, y: 6)
                        )
                }
                .buttonStyle(.plain)
                Button(action: { Task { await saveAndDismiss(deleteSource: false) } }) {
                    Text("Keep Both")
                        .font(.custom("Inter-Bold", size: 16))
                        .foregroundStyle(Color(hex: 0x334155))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: 0xF1F5F9))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
    }

    // Card: playable preview + "SAVED %" badge, Original → arrow → Compressed,
    // and a quality note. Figma 2005:22573.
    private func resultCard(pct: Int) -> some View {
        VStack(spacing: 24) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let previewPlayer {
                        VideoPlayer(player: previewPlayer)
                    } else {
                        Color(hex: 0xE2E8F0)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 173)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("SAVED \(pct)%")
                    .font(.custom("Inter-Bold", size: 10)).tracking(10 * 0.05)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(AppColor.brandPrimary))
                    .padding(12)
            }

            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ORIGINAL")
                            .font(.custom("Inter-Bold", size: 10)).tracking(10 * 0.10)
                            .foregroundStyle(Color(hex: 0x94A3B8))
                        Text(formatBytes(pickedSizeBytes))
                            .font(.custom("Inter-Bold", size: 18))
                            .strikethrough()
                            .foregroundStyle(Color(hex: 0x475569))
                    }
                    Spacer(minLength: 0)
                    Image("Compress/ic_arrow")
                        .renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 20, height: 12)
                        .foregroundStyle(Color(hex: 0xCBD5E1))
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("COMPRESSED")
                            .font(.custom("Inter-Bold", size: 10)).tracking(10 * 0.10)
                            .foregroundStyle(AppColor.brandPrimary)
                        Text(formatBytes(compressedSizeBytes))
                            .font(.custom("Inter-Bold", size: 24))
                            .foregroundStyle(AppColor.brandPrimary)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image("Compress/ic_quality")
                        .renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(AppColor.brandPrimary)
                        .padding(.top, 1)
                    Text("The video quality has been preserved while reducing the file size by half.")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(Color(hex: 0x64748B))
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0xF1F5F9), lineWidth: 1))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(hex: 0xF8FAFC))
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color(hex: 0xF1F5F9), lineWidth: 1)
        )
    }

    // Glowing green check (Figma "Interface / Check"). `full` adds the soft halo +
    // glass ring used on the Successfully-Compressed screen; the Complete screen
    // uses just the radial-gradient core.
    @ViewBuilder
    private func successCheckBadge(full: Bool) -> some View {
        ZStack {
            if full {
                Circle()
                    .fill(Color(hex: 0x45EF89).opacity(0.2))
                    .frame(width: 192, height: 192)
                    .blur(radius: 64)
                Circle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 128, height: 128)
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
                    .shadow(color: Color(hex: 0x1F2687).opacity(0.07), radius: 16, x: 0, y: 8)
            }
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xCDF6DD), Color(hex: 0x2BEE79)],
                                     center: .center, startRadius: 4, endRadius: 46))
                .frame(width: 85, height: 85)
                .shadow(color: Color(hex: 0x4FF090), radius: 18, x: 0, y: 0)
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Successfully Compressed notification (Figma "popup after")

    private var notificationView: some View {
        let savings = max(0, pickedSizeBytes - compressedSizeBytes)
        let pct = pickedSizeBytes > 0 ? Int((Double(savings) / Double(pickedSizeBytes)) * 100) : 0
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: finishNotification) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .frame(width: 24, height: 24)
                }
                Spacer()
                Text("Notification")
                    .font(.custom("Inter-Bold", size: 18))
                    .foregroundStyle(Color(hex: 0x0F172A))
                Spacer()
                Color.clear.frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xF1F5F9)).frame(height: 1) }

            ScrollView {
                VStack(spacing: 0) {
                    successCheckBadge(full: true)
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                    Text("Successfully Compressed!")
                        .font(.custom("Inter-Bold", size: 24))
                        .foregroundStyle(Color(hex: 0x0F172A))
                        .multilineTextAlignment(.center)
                    Text("Your file has been fully optimized to save storage space without losing quality.")
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundStyle(Color(hex: 0x64748B))
                        .multilineTextAlignment(.center)
                        .padding(.top, 7)
                        .padding(.horizontal, 16)

                    HStack(spacing: 16) {
                        notifStat(value: "\(pct)%", label: "SAVED")
                        notifStat(value: formatBytes(savings), label: "CLEARED")
                    }
                    .padding(.top, 32)

                    fileDetailsCard(original: pickedSizeBytes, new: compressedSizeBytes)
                        .padding(.top, 24)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }

            Button(action: finishNotification) {
                Text("Great!")
                    .font(.custom("Inter-Bold", size: 18))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColor.brandPrimary)
                            .shadow(color: AppColor.brandPrimary.opacity(0.2), radius: 12, x: 0, y: 8)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // Stat box: value (blue) over label (gray), white fill + thin blue border.
    private func notifStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.custom("Inter-Bold", size: 24))
                .foregroundStyle(AppColor.brandPrimary)
            Text(label)
                .font(.custom("Inter-Bold", size: 10)).tracking(10 * 0.05)
                .foregroundStyle(Color(hex: 0x94A3B8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0x135BEC, alpha: 0.2), lineWidth: 1))
    }

    // File Details: Original Size → progress bar → New Size (Figma 144:2990).
    private func fileDetailsCard(original: Int, new: Int) -> some View {
        let ratio = original > 0 ? min(1, max(0, Double(new) / Double(original))) : 0
        return VStack(spacing: 24) {
            HStack {
                Text("File Details")
                    .font(.custom("Inter-Bold", size: 16))
                    .foregroundStyle(Color(hex: 0x0F172A))
                Spacer()
                Image("Compress/ic_file_details")
                    .renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(AppColor.brandPrimary)
            }
            VStack(spacing: 16) {
                HStack {
                    Text("Original Size")
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundStyle(Color(hex: 0x64748B))
                    Spacer()
                    Text(formatBytes(original))
                        .font(.custom("Inter-Bold", size: 14))
                        .foregroundStyle(Color(hex: 0x0F172A))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0xF1F5F9))
                        Capsule().fill(AppColor.brandPrimary).frame(width: geo.size.width * ratio)
                    }
                }
                .frame(height: 6)
                HStack {
                    Text("New Size")
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundStyle(Color(hex: 0x64748B))
                    Spacer()
                    Text(formatBytes(new))
                        .font(.custom("Inter-Bold", size: 14))
                        .foregroundStyle(AppColor.brandPrimary)
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0x135BEC, alpha: 0.2), lineWidth: 1))
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
            previewPlayer = AVPlayer(url: outURL)   // play the compressed result
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
            await videoLibrary.reload()   // show the newly saved compressed video in the grid
            previewPlayer?.pause()
            step = .notification
        } catch {
            showError = error.localizedDescription
        }
    }

    // "Great!" / back on the success notification → ad + back to the video grid.
    private func finishNotification() {
        fireResultInterstitial()
        resetToEmpty()
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
        previewPlayer?.pause()
        previewPlayer = nil
        pickedURL = nil
        pickedFileName = ""
        pickedSizeBytes = 0
        compressedURL = nil
        compressedSizeBytes = 0
        quality = .balanced
        estimates = [:]
        step = .empty
    }
}

// MARK: - Subviews

private struct QualityRow: View {
    let quality: VideoCompressor.Quality
    let selected: Bool
    let inputBytes: Int
    let estimatedBytes: Int   // real system estimate; 0 until computed

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
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
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteCountFormatter.string(fromByteCount: Int64(inputBytes), countStyle: .file))
                    .font(.custom("Inter-Regular", size: 12))
                    .strikethrough()
                    .foregroundStyle(AppColor.textMuted)
                Text(estimatedBytes > 0 ? "~\(ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file))" : "…")
                    .font(.custom("Inter-Bold", size: 14))
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? AppColor.brandPrimary : Color(hex: 0xE2E8F0),
                        lineWidth: selected ? 2 : 1)
        )
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

    /// Re-fetch unconditionally (e.g. after a compress saves a new file to Photos).
    func reload() async {
        guard auth == .authorized else { return }
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
