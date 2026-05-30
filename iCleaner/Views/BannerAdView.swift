import SwiftUI
import LibEarnMoneyIOS

// Reactively collapses to zero height when the user is premium so callers don't
// need to know about the premium state — the slot disappears from layout.
// Honors PremiumGate (DEBUG override) so the Settings "Force Premium" toggle
// also collapses banners.
struct BannerAdView: View {
    let adUnitID: String
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
                BannerHost(adUnitID: adUnitID)
                    .frame(height: 60)
            }
        }
        .onReceive(PermissionManager.shared.$isPremium) { observedPremium = $0 }
    }
}

private struct BannerHost: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> UIView {
        let rootVC = UIApplication.shared
            .connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first ?? UIViewController()

        return AdManager.shared.getBannerView(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            width: UIScreen.main.bounds.width
        )
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
