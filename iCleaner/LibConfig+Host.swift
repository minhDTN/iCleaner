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
        trialProductId:   MyProduct.yearlyTrial.id,

        appsFlyerDevKey: "PLACEHOLDER_APPSFLYER_DEV_KEY",

        adConfig: AdConfig(
            appOpenSettingUnitID:  AdUnits.openAll,
            openSplashUnitID:      AdUnits.openSplash,
            interSplashUnitID:     AdUnits.interSplash,
            interScanResultUnitID: AdUnits.interScanResult
        ),

        remoteConfigDefaults: ["interval_show_inter_second": 5 as NSNumber],

        comebackTitle: "We miss you!",
        comebackBody:  "🔥 Tap to come back",

        splashConfig: SplashConfig(
            // `AppIcon` is a special asset bucket that UIImage(named:) cannot load.
            // Use our branded splash logo asset so the splash shows the actual app logo.
            logo: UIImage(named: "Splash/splash_logo"),
            logoMaxHeight: 160,
            backgroundColor: .white
        ),

        paywallTheme: PaywallTheme(),

        homeFactory: {
            UIHostingController(rootView: RootView().modelContainer(for: QRRecord.self))
        }
    )
}
