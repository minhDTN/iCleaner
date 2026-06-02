import SwiftUI
import LibEarnMoneyIOS

struct RootView: View {
    @State private var selection: AppTab = .home
    @State private var showLaunchPaywall: Bool = false
    @State private var didTriggerLaunchPaywall: Bool = false

    init() {
        UITabBar.appearance().isHidden = true
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().compactAppearance    = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().isTranslucent        = true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                HomeView()
                    .tag(AppTab.home)
                    .toolbar(.hidden, for: .tabBar)

                VaultView()
                    .tag(AppTab.vault)
                    .toolbar(.hidden, for: .tabBar)

                ContactsView()
                    .tag(AppTab.contacts)
                    .toolbar(.hidden, for: .tabBar)

                CompressView()
                    .tag(AppTab.compress)
                    .toolbar(.hidden, for: .tabBar)
            }

            VStack(spacing: 0) {
                CustomTabBar(selection: $selection)
                if let bannerID = bannerAdUnitID {
                    BannerAdView(adUnitID: bannerID)
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $showLaunchPaywall) {
            PaywallView()
        }
        .task {
            // Show paywall once after lib splash + cold-start ad finish routing here.
            // `.task` can re-fire when UIKit modals (interstitials) come and go on top
            // of the SwiftUI hosting controller; guard against re-trigger so we don't
            // race a category fullScreenCover and accidentally show the paywall
            // mid-session (playbook §4).
            guard !didTriggerLaunchPaywall else { return }
            didTriggerLaunchPaywall = true
            guard !PremiumGate.isPremium else { return }
            try? await Task.sleep(for: .milliseconds(400))
            showLaunchPaywall = true
        }
    }

    private var bannerAdUnitID: String? {
        switch selection {
        case .home:     return AdUnits.bannerHome
        case .contacts: return AdUnits.bannerContacts
        case .vault:    return AdUnits.bannerVault
        case .compress: return AdUnits.bannerCompress
        }
    }
}

#Preview {
    RootView()
}
