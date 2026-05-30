import SwiftUI
import SwiftData
import LibEarnMoneyIOS

// Vault tab root. State machine:
//   • No passcode set → CreatePasscodeView (onboarding)
//   • Has passcode, not unlocked → VaultLockView (Face ID / passcode)
//   • Unlocked → NavigationStack with VaultGridView
//
// Lifecycle: re-lock when the app enters background (security). Interstitial
// fires once per unlock event (premium-gated, lib's 30s global cap applies).
struct VaultView: View {
    @State private var vault = VaultService()
    @State private var didShowUnlockAd: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !vault.hasPasscode {
                CreatePasscodeView(vault: vault)
            } else if !vault.isUnlocked {
                VaultLockView(vault: vault)
            } else {
                NavigationStack {
                    VaultGridView(vault: vault)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vault.hasPasscode)
        .animation(.easeInOut(duration: 0.25), value: vault.isUnlocked)
        .onChange(of: vault.isUnlocked) { _, unlocked in
            // Reset the per-unlock ad gate. Fire interstitial when transitioning
            // to unlocked, not while locked.
            if !unlocked { didShowUnlockAd = false; return }
            guard !didShowUnlockAd else { return }
            didShowUnlockAd = true
            fireUnlockInterstitial()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // Re-lock on background — vault stays secret if user app-switches
                // and someone else picks up the phone.
                vault.lock()
            }
        }
    }

    private func fireUnlockInterstitial() {
        guard !PremiumGate.isPremium,
              let vc = AdHelpers.topViewController() else { return }
        AdManager.shared.showInterstitialAd(
            adUnitID: AdUnits.interVaultUnlock,
            from: vc,
            completion: nil
        )
    }
}

#Preview {
    VaultView()
}
