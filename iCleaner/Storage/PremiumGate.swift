import Foundation
import LibEarnMoneyIOS

// Single source of truth for "is the user premium?" Production checks the lib's
// PermissionManager. DEBUG builds also honor a UserDefaults override toggled
// from Settings → Developer → Force Premium — handy for testing premium-only
// flows without going through StoreKit sandbox.
//
// NOTE: Always read `PremiumGate.isPremium` instead of
// `PermissionManager.shared.isPremium` directly so the DEBUG override works
// everywhere. The Combine publisher (`PermissionManager.shared.$isPremium`)
// remains the real-time signal for reactive UI (banners, native ads); pair it
// with an @AppStorage observer on `forcePremiumKey` to react to the override.
enum PremiumGate {
    static let forcePremiumKey = "debug.forcePremium"

    static var isPremium: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: forcePremiumKey) { return true }
        #endif
        return PermissionManager.shared.isPremium
    }
}

// Monetization flow gate (product spec): free users see an interstitial when they
// OPEN a cleanup feature, and hit the paywall at the feature's FINAL action
// (delete / merge / backup …) — they must upgrade to complete it. Compress is the
// exception: it keeps its own 2-free-per-day quota and is NOT gated here.
@MainActor
enum FlowGate {
    /// Interstitial on feature entry. No-op for premium; lib's 30s global cap
    /// prevents back-to-back spam when navigating between sub-screens.
    static func showStartAd() {
        guard !PremiumGate.isPremium, let vc = AdHelpers.topViewController() else { return }
        AdManager.shared.showInterstitialAd(adUnitID: AdUnits.interGlobal, from: vc, completion: nil)
    }

    /// Returns true and (caller should) present the paywall when a free user tries
    /// the final action; returns false for premium so the action proceeds.
    static var requiresPaywall: Bool { !PremiumGate.isPremium }
}
