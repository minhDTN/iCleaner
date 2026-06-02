import SwiftUI
import Observation
import LibEarnMoneyIOS

// Shared chrome state: lets a tab tell RootView to fully hide the tab bar +
// banner for full-screen states (Contacts detail, Vault lock/create) that have
// their own bottom controls and must not stack under the tab bar.
@MainActor
@Observable
final class TabChrome {
    var contactsDepth = 0
    var vaultGated = false
}

// Measured height of the tab bar + banner, fed back as a bottom safe-area inset
// on each tab so no content/button is ever covered.
private struct ChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct RootView: View {
    @State private var selection: AppTab = .home
    @State private var chrome = TabChrome()
    @State private var chromeHeight: CGFloat = 0
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
            reserved(HomeView(), .home)
            reserved(VaultView(), .vault)
            reserved(ContactsView(), .contacts)
            reserved(CompressView(), .compress)
        }
        .environment(chrome)
        // Single chrome instance overlaid at the bottom; its measured height is
        // reserved per-tab via `reserved(...)` so buttons never sit underneath.
        .overlay(alignment: .bottom) {
            if !chromeHidden {
                VStack(spacing: 0) {
                    CustomTabBar(selection: $selection)
                    if let bannerID = bannerAdUnitID {
                        BannerAdView(adUnitID: bannerID)
                    }
                }
                .background(AppColor.surfaceBackground)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: ChromeHeightKey.self, value: g.size.height)
                    }
                )
            }
        }
        .onPreferenceChange(ChromeHeightKey.self) { chromeHeight = $0 }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $showLaunchPaywall) {
            PaywallView()
        }
        .task {
            guard !didTriggerLaunchPaywall else { return }
            didTriggerLaunchPaywall = true
            guard !PremiumGate.isPremium else { return }
            try? await Task.sleep(for: .milliseconds(400))
            showLaunchPaywall = true
        }
    }

    // Reserve space for the chrome on each tab. safeAreaInset on a concrete view
    // (vs. on the TabView) reliably insets that view's content + bottom buttons.
    @ViewBuilder
    private func reserved<V: View>(_ view: V, _ tab: AppTab) -> some View {
        view
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: chromeHidden ? 0 : chromeHeight)
            }
            .tag(tab)
            .toolbar(.hidden, for: .tabBar)
    }

    // Fully hide tab bar + banner for full-screen states in the current tab.
    private var chromeHidden: Bool {
        switch selection {
        case .contacts: return chrome.contactsDepth > 0
        case .vault:    return chrome.vaultGated
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
