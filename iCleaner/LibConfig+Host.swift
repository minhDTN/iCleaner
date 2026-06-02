import Foundation
import UIKit
import SwiftUI
import SwiftData
import LibEarnMoneyIOS

func makeLibConfig() -> LibConfig {
    LibConfig(
        appStoreId: "0000000000",
        privacyURL: AppInfo.privacyURL,
        termsURL:   AppInfo.termsURL,

        products:    MyProduct.allCases,
        permissions: [MyPermission.premium],
        defaultProductId: MyProduct.weekly.id,
        trialProductId:   MyProduct.weeklyTrial.id,

        appsFlyerDevKey: "PLACEHOLDER_APPSFLYER_DEV_KEY",

        adConfig: AdConfig(
            appOpenSettingUnitID:  AdUnits.openAll,
            openSplashUnitID:      AdUnits.openSplash,
            interSplashUnitID:     AdUnits.interSplash,
            interScanResultUnitID: AdUnits.interQuickClean
        ),

        // Lib clamps to 5s floor regardless of this default.
        remoteConfigDefaults: ["interval_show_inter_second": 5 as NSNumber],

        comebackTitle: "We miss you!",
        comebackBody:  "🔥 Tap to come back",

        splashConfig: SplashConfig(
            // `AppIcon` is a special asset bucket UIImage(named:) cannot load — use a regular imageset.
            logo: UIImage(named: "Splash/splash_logo"),
            logoMaxHeight: 160,
            backgroundColor: .white
        ),

        paywallTheme: PaywallTheme(),

        homeFactory: {
            UIHostingController(rootView: AppRootView().modelContainer(for: VaultItem.self))
        }
    )
}

// First-launch gate: show the Language picker once, then the main app. The
// chosen language is persisted for when localization wiring lands.
struct AppRootView: View {
    @AppStorage("app.didSelectLanguage") private var didSelectLanguage = false
    @AppStorage("app.languageCode") private var languageCode = "en-gb"

    var body: some View {
        if didSelectLanguage {
            RootView()
        } else {
            LanguageView(showBack: false, onStart: { code in
                languageCode = code
                withAnimation { didSelectLanguage = true }
            })
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.minhdtn.iCleaner"
    }

    static let termsURL   = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    // Both pulled verbatim from Figma annotation nodes 2005:23750 (FAQ) /
    // 2005:23752 (Policy).
    static let privacyURL = URL(string: "https://sites.google.com/view/daliti-global/policy")!
    static let faqURL     = URL(string: "https://docs.google.com/document/d/12O9-91SlfRKRZbl_Hmq65njdvKzFA_AkvZLp5Lp4iYo/edit?usp=sharing")!

    static func fetchAppStoreURL() async -> URL? {
        guard let endpoint = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)") else { return nil }
        struct LookupResponse: Decodable {
            struct Result: Decodable { let trackId: Int }
            let results: [Result]
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: endpoint)
            let resp = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let trackId = resp.results.first?.trackId else { return nil }
            return URL(string: "https://apps.apple.com/app/id\(trackId)")
        } catch {
            return nil
        }
    }
}
