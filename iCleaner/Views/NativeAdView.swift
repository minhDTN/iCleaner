import SwiftUI
import LibEarnMoneyIOS
import GoogleMobileAds // needed for AdLoader / NativeAd / Request types only

// Reactively collapses when premium so the slot vanishes from the layout.
// Honors PremiumGate (DEBUG override) so Settings "Force Premium" hides natives.
struct NativeAdView: View {
    let adUnitID: String
    var height: CGFloat = 100
    @State private var observedPremium = PermissionManager.shared.isPremium
    @AppStorage(PremiumGate.forcePremiumKey) private var forcePremium: Bool = false

    private var isHidden: Bool {
        #if DEBUG
        return observedPremium || forcePremium
        #else
        return observedPremium
        #endif
    }

    var body: some View {
        Group {
            if !isHidden {
                NativeHost(adUnitID: adUnitID)
                    .frame(height: height)
            }
        }
        .onReceive(PermissionManager.shared.$isPremium) { observedPremium = $0 }
    }
}

private struct NativeHost: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> StandardNativeAdView {
        let view = StandardNativeAdView()
        context.coordinator.adView = view
        context.coordinator.load(adUnitID: adUnitID)
        return view
    }

    func updateUIView(_ uiView: StandardNativeAdView, context: Context) {}

    final class Coordinator: NSObject, NativeAdLoaderDelegate {
        weak var adView: StandardNativeAdView?
        private var adLoader: AdLoader?

        func load(adUnitID: String) {
            let rootVC = UIApplication.shared
                .connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
                .first ?? UIViewController()

            guard let loader = AdManager.shared.createNativeAdLoader(
                adUnitID: adUnitID,
                rootViewController: rootVC,
                delegate: self
            ) else { return }
            adLoader = loader
            loader.load(Request())
        }

        func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
            adView?.populate(with: nativeAd)
        }

        func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
            adView?.isHidden = true
        }
    }
}
