import SwiftUI
import Observation
import LibEarnMoneyIOS

// Shared chrome state: lets a tab's pushed detail screen tell RootView to hide
// the custom tab bar + banner (so detail screens are full-bleed, matching Figma,
// instead of stacking their own action bar under the tab bar). Tracked per tab
// by navigation depth — robust against TabView's onAppear/onDisappear quirks.
@MainActor
@Observable
final class TabChrome {
    var contactsDepth = 0
}

struct RootView: View {
    @State private var selection: AppTab = .home
    @State private var chrome = TabChrome()
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
        .environment(chrome)
        // Chrome as a safe-area inset (not a ZStack overlay) so every screen's
        // content + bottom buttons inset ABOVE the tab bar and banner instead of
        // being covered by them.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !chromeHidden {
                VStack(spacing: 0) {
                    CustomTabBar(selection: $selection)
                    if let bannerID = bannerAdUnitID {
                        BannerAdView(adUnitID: bannerID)
                    }
                }
                .background(AppColor.surfaceBackground)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $showLaunchPaywall) {
            PaywallView()
        }
        .task {
            // Show paywall once after lib splash + cold-start ad finish routing here.
            guard !didTriggerLaunchPaywall else { return }
            didTriggerLaunchPaywall = true
            guard !PremiumGate.isPremium else { return }
            try? await Task.sleep(for: .milliseconds(400))
            showLaunchPaywall = true
        }
    }

    // Hide the tab bar + banner while a detail screen is pushed in the current
    // tab (only Contacts pushes full-screen detail with its own bottom bar).
    private var chromeHidden: Bool {
        switch selection {
        case .contacts: return chrome.contactsDepth > 0
        default:        return false
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
