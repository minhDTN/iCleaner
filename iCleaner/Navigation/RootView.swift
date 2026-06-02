import SwiftUI
import Observation
import LibEarnMoneyIOS

// Shared chrome state: the measured tab bar + banner height (so each screen can
// reserve space for it) and flags letting a tab fully hide the chrome for
// full-screen states (Contacts detail, Vault lock/create).
@MainActor
@Observable
final class TabChrome {
    var contactsDepth = 0
    var vaultGated = false
    var vaultDepth = 0        // pushed full-screen vault detail (e.g. Change Passcode)
    var height: CGFloat = 0   // measured tab bar + banner height
}

private struct ChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
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
            HomeView().tag(AppTab.home).toolbar(.hidden, for: .tabBar)
            VaultView(isActive: selection == .vault).tag(AppTab.vault).toolbar(.hidden, for: .tabBar)
            ContactsView().tag(AppTab.contacts).toolbar(.hidden, for: .tabBar)
            CompressView().tag(AppTab.compress).toolbar(.hidden, for: .tabBar)
        }
        .environment(chrome)
        // One chrome instance overlaid at the bottom. Its measured height is
        // published via `chrome.height`; each screen reserves it with
        // `.bottomChromeInset()` so no content/button is ever covered. (Reserving
        // on individual screens is reliable even inside a NavigationStack, unlike
        // safeAreaInset applied to the TabView.)
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
        .onPreferenceChange(ChromeHeightKey.self) { h in
            chrome.height = chromeHidden ? chrome.height : h
        }
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

    // Fully hide tab bar + banner for full-screen states in the current tab.
    private var chromeHidden: Bool {
        switch selection {
        case .contacts: return chrome.contactsDepth > 0
        case .vault:    return chrome.vaultGated || chrome.vaultDepth > 0
        default:        return false
        }
    }

    private var bannerAdUnitID: String? {
        // Home shows a tab-bar banner. Compress manages its own per-state bottom
        // ad inside CompressView (banner_compress / video / success / native).
        switch selection {
        case .home:     return AdUnits.bannerHome
        case .compress, .contacts, .vault: return nil
        }
    }
}

// Reserve bottom space for the tab bar + banner. Applied to each screen that
// renders under the chrome (Home, Compress, Vault grid, Contacts dashboard) —
// works reliably even inside a NavigationStack.
extension View {
    func bottomChromeInset() -> some View { modifier(BottomChromeInset()) }
}

private struct BottomChromeInset: ViewModifier {
    @Environment(TabChrome.self) private var chrome: TabChrome?
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: chrome?.height ?? 0)
        }
    }
}

#Preview {
    RootView()
}
