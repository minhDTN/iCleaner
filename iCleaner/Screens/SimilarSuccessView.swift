import SwiftUI

// Figma `2005:23492` (successfully clean). White bg. Glass green check badge
// 128×128 (white 40% + stroke white 60% + blur 20 + green radial inner 85×85)
// over a green-glow halo (192×192 blur 64 rgba(69,239,137,0.2)). Below:
// "Congratulations!" (Inter Bold 30/36 #333333 -2.5% tracking). Stat card
// 311 wide (white bg + stroke rgba(13,127,242,0.2) + shadow + radius 16,
// padding 32) showing big stat "X MB" (Inter Bold 36/40 #333333) with header
// "Junk Files Removed" + footer "CLEANED". Bottom CTA "Perfect!" (335×56 brand
// blue, Inter Bold 18/28 white, radius 16, brand-blue 0.2 shadow).
struct SimilarSuccessView: View {
    let deletedMB: Int
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

                statCard
                    .padding(.horizontal, 32)

                Spacer()
            }

            VStack(spacing: 16) {
                // Scenario: deletion success → native (native_success_view_delete).
                NativeAdView(adUnitID: AdUnits.nativeSuccessDelete, height: 120)
                    .padding(.horizontal, 20)

                Button(action: onContinue) {
                    Text(L("success.perfect"))
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
            // Green halo glow (Figma effect_4KQ7NL — blur 64).
            Circle()
                .fill(Color(hex: 0x45EF89).opacity(0.2))
                .frame(width: 192, height: 192)
                .blur(radius: 64)

            // Glass circle (Figma fill_QGS4C4 + stroke fill_NH3VYK + blur 20).
            Circle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 128, height: 128)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.6), lineWidth: 2)
                )
                .background(
                    Circle().fill(Color.white.opacity(0.001)).blur(radius: 20)
                )

            // Inner radial green orb (Figma fill_JXZIYS).
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

    private var statCard: some View {
        VStack(spacing: 8) {
            Text(L("success.junkRemoved"))
                .font(.custom("Inter-Regular", size: 12))
                .tracking(12 * 0.10)
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: 0x94A3B8))

            Text("\(deletedMB) MB")
                .font(.custom("Inter-Bold", size: 36))
                .foregroundStyle(Color(hex: 0x333333))

            Text(L("success.cleaned"))
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
}

#Preview {
    SimilarSuccessView(deletedMB: 12, onContinue: {})
}
