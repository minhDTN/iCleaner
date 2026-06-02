import SwiftUI

// Figma `2005:23298` (successfully clean). Same green check badge + green halo
// glow as SimilarSuccessView. Differences from SimilarSuccessView:
//   • Title is the same "Congratulations!" (Inter Bold 30/36 -2.5% tracking).
//   • Big primary stat card (311 wide, brand stroke 20%, padding 32, radius 16,
//     shadow 0 1 2 0.05). "X MB" (Inter Bold 36/40 #333333) with labels.
//   • Two secondary stat cards side by side (147.5 wide each, gap 16, padding 20,
//     stroke brand-blue 10%, radius 16). "45" and "1.2 GB" (Inter Bold 20/28).
//   • CTA reads "Great!" instead of "Perfect!".
struct QuickCleanSuccessView: View {
    let cleanedMB: Int
    let photosOptimized: Int
    let memoryBoosted: Int   // also in MB
    var onContinue: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surfaceBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 80)
                successBadge

                Spacer().frame(height: 40)

                Text(L("success.congrats"))
                    .font(.custom("Inter-Bold", size: 30))
                    .tracking(30 * -0.025)
                    .foregroundStyle(Color(hex: 0x333333))

                Spacer().frame(height: 24)

                primaryStatCard
                    .padding(.horizontal, 32)

                Spacer().frame(height: 16)

                HStack(spacing: 16) {
                    secondaryStatCard(value: "\(photosOptimized)", label: L("success.photosOptimized"))
                    secondaryStatCard(value: formatMB(memoryBoosted), label: L("success.memoryBoosted"))
                }
                .padding(.horizontal, 32)

                Spacer()
            }

            VStack(spacing: 16) {
                // Scenario: clean "Congratulations" → native (native_success_view_clean).
                NativeAdView(adUnitID: AdUnits.nativeSuccessClean, height: 120)
                    .padding(.horizontal, 20)

                Button(action: onContinue) {
                    Text(L("common.great"))
                        .font(.custom("Inter-Bold", size: 18))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColor.brandPrimary)
                                .shadow(color: AppColor.brandPrimary.opacity(0.2), radius: 5, x: 0, y: 4)
                                .shadow(color: AppColor.brandPrimary.opacity(0.2), radius: 12, x: 0, y: 10)
                        )
                }
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 24)
        }
    }

    private var successBadge: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x45EF89).opacity(0.2))
                .frame(width: 192, height: 192)
                .blur(radius: 64)

            Circle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 128, height: 128)
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xCDF6DD), Color(hex: 0x2BEE79)],
                        center: .center, startRadius: 5, endRadius: 50
                    )
                )
                .frame(width: 85, height: 85)
                .shadow(color: Color(hex: 0x4FF090), radius: 18, x: 0, y: 0)

            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    private var primaryStatCard: some View {
        VStack(spacing: 8) {
            Text(L("success.totalCleaned"))
                .font(.custom("Inter-Regular", size: 12))
                .tracking(12 * 0.10)
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: 0x94A3B8))

            Text(formatMB(cleanedMB))
                .font(.custom("Inter-Bold", size: 36))
                .foregroundStyle(Color(hex: 0x333333))

            Text(L("success.junkRemoved2"))
                .font(.custom("Inter-Regular", size: 12))
                .tracking(12 * 0.10)
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: 0x94A3B8))
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.surfaceBackground)
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColor.brandPrimary.opacity(0.2), lineWidth: 1)
        )
    }

    private func secondaryStatCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.custom("Inter-Bold", size: 20))
                .foregroundStyle(Color(hex: 0x333333))
            Text(label)
                .font(.custom("Inter-Regular", size: 11))
                .tracking(11 * 0.10)
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: 0x94A3B8))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColor.brandPrimary.opacity(0.1), lineWidth: 1)
        )
    }

    private func formatMB(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }
}

#Preview {
    QuickCleanSuccessView(cleanedMB: 320, photosOptimized: 45, memoryBoosted: 1228, onContinue: {})
}
