import SwiftUI

// Figma `2005:23459` (cleaning). Center: large circular progress ring 176×176
// brand-blue with white "65%" (Inter Bold 48/48, -2.5% tracking). Scattered
// brand-blue dots in faint opacities around the ring. Below: "Deleting Selected
// photos..." (Inter Bold 20/28 #333333). Then a 311×80 frame of rolling log
// paths (Inter Regular 12/16 #94A3B8) with a vertical fade gradient overlay.
//
// MVP: drives a fake 0→1 progress over 2.4s then calls onComplete. Phase 3
// Part B swaps to real PHPhotoLibrary delete progress.
struct SimilarCleaningView: View {
    var onComplete: () -> Void

    @State private var progress: Double = 0
    @State private var logIndex: Int = 0

    private static let logPaths: [String] = [
        "/cache/app_data/tmp_01_user_logs.db",
        "/system/cache/dalvik-cache/x86_64",
        "/storage/emulated/0/Android/data/cache",
        "/Photos/Library/Caches/duplicates.tmp",
        "/Photos/Library/Caches/thumbnails.idx",
        "/var/mobile/Containers/Data/Application/temp",
    ]

    var body: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                progressRing
                    .frame(width: 256, height: 256)

                Spacer().frame(height: 56)

                Text("Deleting Selected photos...")
                    .font(.custom("Inter-Bold", size: 20))
                    .foregroundStyle(Color(hex: 0x333333))

                Spacer().frame(height: 24)

                logStrip
                    .frame(width: 311, height: 80)

                Spacer(minLength: 64)
            }
        }
        .task {
            // Drive fake progress + log roll.
            let total: Double = 2.4
            let steps = 60
            for i in 0...steps {
                try? await Task.sleep(nanoseconds: UInt64(total / Double(steps) * 1_000_000_000))
                progress = Double(i) / Double(steps)
                if i % 6 == 0 {
                    logIndex = (logIndex + 1) % Self.logPaths.count
                }
            }
            onComplete()
        }
    }

    private var progressRing: some View {
        ZStack {
            // Scattered faint dots around the ring (Figma decoration).
            scatteredDots

            Circle()
                .stroke(Color(hex: 0xF8FAFC), lineWidth: 20)
                .frame(width: 220, height: 220)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AppColor.brandPrimary,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .frame(width: 220, height: 220)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)

            Circle()
                .fill(AppColor.brandPrimary)
                .frame(width: 176, height: 176)
                .overlay(
                    Text("\(Int(progress * 100))%")
                        .font(.custom("Inter-Bold", size: 48))
                        .tracking(48 * -0.025)
                        .foregroundStyle(.white)
                )
                .shadow(color: .black.opacity(0.25), radius: 25, x: 0, y: 25)
        }
    }

    private var scatteredDots: some View {
        // Position relative to 256×256 frame, taken from Figma layout coords.
        ZStack {
            dot(size: 12, x: 103, y: 99,  opacity: 0.3)
            dot(size: 11, x: 192, y: 154, opacity: 0.2)
            dot(size: 16, x: 270, y: 95,  opacity: 0.4)
            dot(size: 8,  x: 137, y: 9,   opacity: 0.1)
            dot(size: 12, x: 240, y: 152, opacity: 0.3)
            dot(size: 9,  x: 264, y: 102, opacity: 0.2)
        }
        .frame(width: 256, height: 256, alignment: .topLeading)
    }

    private func dot(size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(AppColor.brandPrimary.opacity(opacity))
            .frame(width: size, height: size)
            .position(x: x, y: y)
    }

    private var logStrip: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Text(Self.logPaths[(logIndex + i) % Self.logPaths.count])
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(Color(hex: 0x94A3B8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .frame(width: 311, height: 80, alignment: .topLeading)
            .overlay(
                Rectangle()
                    .fill(AppColor.brandPrimary.opacity(0.1))
                    .frame(height: 1),
                alignment: .top
            )
            .overlay(
                Rectangle()
                    .fill(AppColor.brandPrimary.opacity(0.1))
                    .frame(height: 1),
                alignment: .bottom
            )

            // Fade gradient overlay — fades top + bottom edges.
            LinearGradient(
                stops: [
                    .init(color: .white,                    location: 0),
                    .init(color: .white.opacity(0),         location: 0.5),
                    .init(color: .white,                    location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 311, height: 80)
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    SimilarCleaningView(onComplete: {})
}
