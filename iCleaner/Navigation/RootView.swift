import SwiftUI
import LibEarnMoneyIOS

struct RootView: View {
    @State private var selection: AppTab = .home

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

                ContactsView()
                    .tag(AppTab.contacts)
                    .toolbar(.hidden, for: .tabBar)

                VaultView()
                    .tag(AppTab.vault)
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
