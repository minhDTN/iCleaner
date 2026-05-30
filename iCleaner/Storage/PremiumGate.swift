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
