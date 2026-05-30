import SwiftUI
import SwiftData

// Vault tab root. State machine:
//   • No passcode set → CreatePasscodeView (onboarding)
//   • Has passcode, not unlocked → VaultLockView (Face ID / passcode)
//   • Unlocked → vault grid (Phase 6 Part B; placeholder shell for now)
//
// VaultService is @State here so unlock state persists for the lifetime of the
// tab (i.e. until the app is cold-started or the user backgrounds the app).
// Re-lock on background is a Part B concern.
struct VaultView: View {
    @State private var vault = VaultService()

    var body: some View {
        Group {
            if !vault.hasPasscode {
                CreatePasscodeView(vault: vault)
            } else if !vault.isUnlocked {
                VaultLockView(vault: vault)
            } else {
                vaultUnlockedShell
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vault.hasPasscode)
        .animation(.easeInOut(duration: 0.25), value: vault.isUnlocked)
    }

    // Placeholder until Phase 6 Part B builds the real grid / add picker / preview.
    private var vaultUnlockedShell: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColor.success)
                Text("Vault unlocked")
                    .font(.custom("Inter-Bold", size: 20))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Grid + Add from Camera/Photos + preview coming in Phase 6 Part B.")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button(action: { vault.lock() }) {
                    Text("Lock")
                        .font(.custom("Inter-SemiBold", size: 14))
                        .foregroundStyle(AppColor.brandPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(AppColor.brandPrimary.opacity(0.1))
                        )
                }
                .padding(.top, 8)
            }
        }
    }
}

#Preview {
    VaultView()
}
