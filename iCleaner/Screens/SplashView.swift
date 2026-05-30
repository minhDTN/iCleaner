import SwiftUI

// Figma `2005:24774` (Splash).
// Background: linear gradient #DEEFFF → #FFFFFF (180°).
// Children:
//   1) Logo illustration (SVG `Splash/splash_logo`, 236×182).
//   2) Wordmark "iCLENER" — Figma uses Orbitron Black 35 with a -45° blue gradient;
//      fallback to Inter-Bold + solid brand color until Orbitron is bundled.
//   3) 8 loading dots (28×9, 5px gap): 5 brand-blue dots with 16px glow at
//      decreasing opacity 1.0/0.8/0.6/0.4/0.2 + 3 grey dots (#E2E8F0).
//   4) Footnote "This action can contain ads" — Inter Regular 12/16 bottom-centered.
//
// NOTE: The cold-start splash is rendered by the lib via SplashConfig (see
// LibConfig+Host.swift) using the same `Splash/splash_logo` asset. This SwiftUI
// view is for in-app preview / re-entry only.
struct SplashView: View {
    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 181)

                Image("Splash/splash_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 235.6, height: 181.5)

                Spacer().frame(height: 69)  // 432 - (181 + 181.5) ≈ 69

                Text("iCLENER")
                    // TODO: swap to Orbitron-Black when bundled; design uses 35pt black.
                    .font(.custom("Inter-Bold", size: 35))
                    .foregroundStyle(wordmarkGradient)
                    .frame(width: 176, height: 44)

                Spacer().frame(height: 26)  // 502 - (432 + 44) = 26

                loadingDots
                    .frame(height: 9)

                Spacer()

                Text("This action can contain ads")
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(Color(hex: 0x040516))
                    .frame(height: 16)
                    .padding(.bottom, 43)  // 812 - (753 + 16) = 43
            }
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xDEEFFF), Color(hex: 0xFFFFFF)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var wordmarkGradient: LinearGradient {
        // Figma -45° gradient: #3DABFF → #1D67FC. SwiftUI's `topTrailing → bottomLeading`
        // matches a -45° angle in a square text frame.
        LinearGradient(
            colors: [Color(hex: 0x3DABFF), Color(hex: 0x1D67FC)],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    private var loadingDots: some View {
        // Opacities pulled verbatim from Figma — 5 blue dots fade out, then 3 grey.
        let opacities: [Double] = [1.0, 0.8, 0.6, 0.4, 0.2]
        return HStack(spacing: 5) {
            ForEach(opacities.indices, id: \.self) { idx in
                blueDot(opacity: opacities[idx])
            }
            greyDot()
            greyDot()
            greyDot()
        }
    }

    private func blueDot(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(AppColor.brandPrimary)
            .frame(width: 28, height: 9)
            .opacity(opacity)
            // Figma effect_QDFKY7 — 0px 0px 16px rgba(13,127,242,1).
            .shadow(color: AppColor.brandPrimary.opacity(opacity), radius: 8)
    }

    private func greyDot() -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color(hex: 0xE2E8F0))
            .frame(width: 28, height: 9)
    }
}

#Preview {
    SplashView()
}
