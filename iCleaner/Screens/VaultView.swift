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
    var isActive: Bool = true   // true while the Vault tab is the selected tab
    @State private var vault = VaultService()
    @State private var didShowUnlockAd: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TabChrome.self) private var chrome: TabChrome?

    // The lock / create-passcode screens are full-screen gates → no tab bar.
    private var gated: Bool { !vault.hasPasscode || !vault.isUnlocked }

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
        // Hide the tab bar + banner whenever a full-screen gate (create / lock /
        // change passcode) is showing. `initial: true` sets it on first appearance
        // too — onAppear alone doesn't fire reliably on TabView tab switches.
        .onChange(of: gated, initial: true) { _, isGated in chrome?.vaultGated = isGated }
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
        .onChange(of: isActive) { _, active in
            // Re-lock whenever the user leaves the Vault tab → passcode/Face ID is
            // required again on every return (user preference).
            if !active { vault.lock() }
        }
    }

    private func fireUnlockInterstitial() {
        guard !PremiumGate.isPremium,
              let vc = AdHelpers.topViewController() else { return }
        AdManager.shared.showInterstitialAd(
            adUnitID: AdUnits.interGlobal,
            from: vc,
            completion: nil
        )
    }
}

#Preview {
    VaultView()
}

// Figma vault top bar (status-bar header across all vault screens): "Private
// Vault" (Inter SemiBold 20 #111827) left-aligned, optional back chevron, optional
// change-passcode (lock-rotate) icon on the right. White bg + 1px bottom border
// #B2B2B2. Custom (vs system nav bar) so there's no iOS 26 glass pill behind the
// trailing icon and the title stays left-aligned per design.
struct VaultHeader: View {
    let title: String
    var onBack: (() -> Void)? = nil
    var onChangePass: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image("Common/icon_back_vault_change_password")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .frame(width: 32, height: 32, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text(title)
                .font(.custom("Inter-SemiBold", size: 20))
                .foregroundStyle(Color(hex: 0x111827))
            Spacer(minLength: 0)
            if let onChangePass {
                Button(action: onChangePass) {
                    Image("Vault/ic_change_pass")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color(hex: 0x292D32))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(
            AppColor.surfaceBackground
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(hex: 0xB2B2B2)).frame(height: 1)
                }
        )
    }
}
