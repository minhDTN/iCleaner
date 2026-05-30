import SwiftUI

// Figma `2008:31885` (face ID). Gradient bg #FAF8FF→#FFFFFF, central glass
// shield icon (160×160), "Private Vault is Locked" Inter Bold 34/41 -2%,
// "Unlock with Face ID" CTA brand-blue 56h with shadow + "Use Passcode" fallback.
struct VaultLockView: View {
    @Bindable var vault: VaultService
    @State private var showPasscode: Bool = false
    @State private var passcodeEntry: String = ""
    @State private var passcodeError: Bool = false
    @State private var biometryError: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xFAF8FF), Color(hex: 0xFFFFFF)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                shieldIllustration

                VStack(spacing: 12) {
                    Text("Private Vault is\nLocked")
                        .font(.custom("Inter-Bold", size: 34))
                        .tracking(34 * -0.02)
                        .foregroundStyle(Color(hex: 0x191B23))
                        .multilineTextAlignment(.center)

                    Text("Your photos are encrypted and protected.")
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                primaryActions
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 64)

            if showPasscode {
                passcodeOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Couldn't authenticate", isPresented: Binding(
            get: { biometryError != nil },
            set: { if !$0 { biometryError = nil } }
        )) {
            Button("OK", role: .cancel) { biometryError = nil }
            Button("Use Passcode") { showPasscode = true }
        } message: {
            Text(biometryError ?? "")
        }
        .task {
            // Auto-prompt Face ID on appear if available.
            if vault.canUseBiometry { await tryBiometry() }
        }
        .animation(.easeInOut(duration: 0.25), value: showPasscode)
    }

    private var shieldIllustration: some View {
        ZStack {
            Circle()
                .fill(AppColor.brandPrimary.opacity(0.10))
                .frame(width: 160, height: 160)
                .blur(radius: 24)

            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 144, height: 144)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.8), lineWidth: 2)
                )
                .shadow(color: Color(hex: 0x004AC6).opacity(0.15), radius: 24, x: 0, y: 12)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.brandPrimary)
        }
        .frame(width: 160, height: 192)
    }

    private var primaryActions: some View {
        VStack(spacing: 16) {
            if vault.canUseBiometry {
                Button(action: { Task { await tryBiometry() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: vault.biometryName == "Face ID" ? "faceid" : "touchid")
                            .font(.system(size: 20))
                        Text("Unlock with \(vault.biometryName)")
                            .font(.custom("Inter-SemiBold", size: 17))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColor.brandPrimary)
                            .shadow(color: Color(hex: 0x004AC6).opacity(0.25), radius: 12, x: 0, y: 8)
                    )
                }
                .buttonStyle(.plain)
            }

            Button(action: { showPasscode = true }) {
                Text("Use Passcode")
                    .font(.custom("Inter-SemiBold", size: 17))
                    .foregroundStyle(AppColor.brandPrimary)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var passcodeOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture {
                    showPasscode = false
                    passcodeEntry = ""
                }

            VStack(spacing: 24) {
                Text("Enter Passcode")
                    .font(.custom("Inter-Bold", size: 22))
                    .foregroundStyle(Color(hex: 0x0F172A))

                if passcodeError {
                    Text("Wrong passcode — try again")
                        .font(.custom("Inter-Medium", size: 13))
                        .foregroundStyle(AppColor.danger)
                }

                PasscodeKeypad(entry: $passcodeEntry, onComplete: tryPasscode)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppColor.surfaceBackground)
            )
            .padding(20)
        }
    }

    private func tryBiometry() async {
        do {
            try await vault.unlockWithBiometry(reason: "Unlock your private vault")
        } catch {
            // Don't pop a noisy alert when user cancels biometry — only when
            // there's a real failure (lockout, no biometry enrolled, etc).
            // LAError.userCancel and .userFallback go silent.
            if let lae = error as? LAError, lae.code == .userCancel || lae.code == .userFallback {
                return
            }
            biometryError = error.localizedDescription
        }
    }

    private func tryPasscode(_ code: String) {
        if vault.verifyPasscode(code) {
            showPasscode = false
        } else {
            passcodeError = true
            passcodeEntry = ""
        }
    }
}

// Imported for LAError.code; LocalAuthentication is fine to import here.
import LocalAuthentication

#Preview {
    VaultLockView(vault: VaultService())
}
