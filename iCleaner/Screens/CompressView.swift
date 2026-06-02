import SwiftUI
import AVKit
import PhotosUI
import LibEarnMoneyIOS

// Figma cluster: 2005:22138 (entry) → 2005:22335 (confirm) → 2005:23000 (progress)
// → 2005:22563 (result). Daily free quota of 2 (key-rolled at local midnight);
// premium bypasses. Interstitial fires after a successful Result via
// AdUnits.interCompressResult (premium-gated, lib 30s cap).
//
// State machine:
//   .empty       — no video picked yet, prompt to pick
//   .ready       — video loaded, choose quality + Start
//   .confirm     — modal asking to spend a daily slot
//   .progress    — ring + Cancel Process
//   .result      — Replace Original / Keep Both
struct CompressView: View {
    @State private var compressor = VideoCompressor()
    @State private var step: Step = .empty
    @State private var showPicker: Bool = false
    @State private var pickerSelection: [PhotosPickerItem] = []
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
            case .empty:    emptyView
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
        }
        .bottomChromeInset()
        .photosPicker(
            isPresented: $showPicker,
            selection: $pickerSelection,
            maxSelectionCount: 1,
            matching: .videos
        )
        .onChange(of: pickerSelection) { _, new in
            guard let first = new.first else { return }
            Task {
                await loadPicked(first)
                pickerSelection = []
            }
        }
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

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "video.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.brandPrimary)
            VStack(spacing: 8) {
                Text("Compress a video")
                    .font(.custom("Inter-Bold", size: 22))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Pick a video from your library to shrink it down without losing what matters.")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            quotaBadge
                .padding(.top, 4)
            pickButton
                .padding(.top, 16)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var pickButton: some View {
        Button(action: { showPicker = true }) {
            HStack(spacing: 8) {
                Image(systemName: "photo.fill.on.rectangle.fill")
                Text("Pick from Photos")
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

    private var quotaBadge: some View {
        let canMore = compressor.canCompressMore
        let label: String = {
            if PremiumGate.isPremium { return "Unlimited (Premium)" }
            return "Today's uses: \(compressor.usesUsedToday)/\(VideoCompressor.dailyLimit)"
        }()
        return HStack(spacing: 6) {
            Image(systemName: canMore ? "bolt.fill" : "lock.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.custom("Inter-SemiBold", size: 12))
        }
        .foregroundStyle(canMore ? AppColor.success : AppColor.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill((canMore ? AppColor.success : AppColor.warning).opacity(0.10))
        )
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

    private func loadPicked(_ pick: PhotosPickerItem) async {
        do {
            // PhotosPickerItem.loadTransferable for .video returns a temp URL.
            // We use the Movie helper that gives us a stable URL we can hand to AVFoundation.
            guard let movie = try await pick.loadTransferable(type: PickedMovie.self) else { return }
            pickedURL = movie.url
            pickedFileName = movie.url.lastPathComponent
            pickedSizeBytes = (try? FileManager.default.attributesOfItem(atPath: movie.url.path)[.size] as? Int) ?? 0
            step = .ready
        } catch {
            showError = error.localizedDescription
        }
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
            adUnitID: AdUnits.interCompressResult,
            from: vc,
            completion: nil
        )
    }

    private func resetToEmpty() {
        pickerSelection = []
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

// MARK: - PhotosPicker movie bridge

private struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // Copy into a stable temp location — the file PhotosPicker hands us
            // gets cleaned up out from under us if we hold the original URL.
            let stable = NSURL.fileURL(withPath: NSTemporaryDirectory())
                .appendingPathComponent("iCleaner-picked-\(UUID().uuidString.prefix(8)).mov")
            try? FileManager.default.removeItem(at: stable)
            try FileManager.default.copyItem(at: received.file, to: stable)
            return Self(url: stable)
        }
    }
}

#Preview {
    CompressView()
}
