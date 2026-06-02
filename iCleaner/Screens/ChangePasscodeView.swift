import SwiftUI

// Figma `2010:2463` (change pass). 3-step flow:
//   Step 1: enter current passcode for verification
//   Step 2: choose new 6-digit code
//   Step 3: re-enter to confirm
// Wrong current → red error, reset to step 1.
// Mismatch on confirm → red error, reset to step 2.
// Reached from Settings → Vault → Change Passcode (Phase 9 polish).
struct ChangePasscodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TabChrome.self) private var chrome: TabChrome?
    @Bindable var vault: VaultService

    @State private var step: Step = .verify
    @State private var verifyEntry: String = ""
    @State private var newEntry: String = ""
    @State private var confirmEntry: String = ""
    @State private var wrongOld: Bool = false
    @State private var mismatch: Bool = false
    @State private var saveError: String?

    private enum Step { case verify, choose, confirm }

    var body: some View {
        VStack(spacing: 0) {
            VaultHeader(title: "Private Vault", onBack: { dismiss() })

            ZStack {
                AppColor.surfaceBackground.ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    glassIcon
                        .padding(.bottom, 32)

                Text(title)
                    .font(.custom("Inter-Bold", size: 24))
                    .tracking(24 * -0.01)
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)

                Text(subtitle)
                    .font(.custom("Inter-Regular", size: 16))
                    .foregroundStyle(Color(hex: 0x334155))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 32)

                if wrongOld {
                    errorRow("That passcode doesn't match — try again")
                }
                if mismatch {
                    errorRow("Codes don't match — start over")
                }

                    PasscodeKeypad(entry: currentEntry, onComplete: handleComplete)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Full-screen gate while pushed → hide the tab bar + banner so the keypad
        // isn't covered. Push/pop fire onAppear/onDisappear reliably.
        .onAppear { if let chrome { chrome.vaultDepth += 1 } }
        .onDisappear { if let chrome { chrome.vaultDepth = max(0, chrome.vaultDepth - 1) } }
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private var currentEntry: Binding<String> {
        switch step {
        case .verify:  return $verifyEntry
        case .choose:  return $newEntry
        case .confirm: return $confirmEntry
        }
    }

    private var title: String {
        switch step {
        case .verify:  return "Change Passcode"
        case .choose:  return "New Passcode"
        case .confirm: return "Re-enter Passcode"
        }
    }

    private var subtitle: String {
        switch step {
        case .verify:  return "Enter your current 6-digit passcode to\nverify your identity."
        case .choose:  return "Choose a new 6-digit code for your\nprivate vault."
        case .confirm: return "Enter the same 6 digits again to\nconfirm your new passcode."
        }
    }

    private var glassIcon: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xDBEAFE).opacity(0.5))
                .frame(width: 76, height: 76)
                .blur(radius: 24)
            Circle()
                .fill(Color.white)
                .frame(width: 80, height: 80)
                .overlay(Circle().stroke(Color(hex: 0xE2E8F0), lineWidth: 2))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            Image(systemName: step == .verify ? "lock.fill" : "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.brandPrimary)
        }
    }

    private func errorRow(_ text: String) -> some View {
        Text(text)
            .font(.custom("Inter-Medium", size: 14))
            .foregroundStyle(AppColor.danger)
            .padding(.bottom, 16)
    }

    private func handleComplete(_ code: String) {
        switch step {
        case .verify:
            if vault.verifyPasscode(code) {
                wrongOld = false
                // small delay so user sees the 6th dot fill
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    step = .choose
                }
            } else {
                wrongOld = true
                verifyEntry = ""
            }
        case .choose:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                mismatch = false
                step = .confirm
            }
        case .confirm:
            if confirmEntry == newEntry {
                do {
                    // setPasscode overwrites the existing one. We've already
                    // verified the user knows the current passcode in step 1.
                    try vault.setPasscode(newEntry)
                    dismiss()
                } catch {
                    saveError = "Failed to save new passcode. Please try again."
                }
            } else {
                mismatch = true
                newEntry = ""
                confirmEntry = ""
                step = .choose
            }
        }
    }
}

#Preview {
    NavigationStack { ChangePasscodeView(vault: VaultService()) }
}
