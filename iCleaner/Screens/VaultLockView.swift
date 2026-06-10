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
    @State private var didAutoPromptBiometry: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            VaultHeader(title: L("vault.title"))

            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0xFAF8FF), Color(hex: 0xFFFFFF)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 32) {
                    Spacer()

                    lockGlyph

                VStack(spacing: 12) {
                    Text(L("vault.lockedTitle"))
                        .font(.custom("Inter-Bold", size: 34))
                        .tracking(34 * -0.02)
                        .foregroundStyle(Color(hex: 0x191B23))
                        .multilineTextAlignment(.center)

                    Text(L("vault.lockedBody"))
                        .font(.custom("Inter-Regular", size: 17))
                        .foregroundStyle(Color(hex: 0x434655))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                primaryActions
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 48)

            if showPasscode {
                passcodeOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            }
        }
        .bottomChromeInset()   // keep content above the now-visible tab bar
        .alert(L("vault.authFailTitle"), isPresented: Binding(
            get: { biometryError != nil },
            set: { if !$0 { biometryError = nil } }
        )) {
            Button("OK", role: .cancel) { biometryError = nil }
            Button(L("passcode.usePasscode")) { showPasscode = true }
        } message: {
            Text(biometryError ?? "")
        }
        .task {
            // Auto-prompt Face ID on appear, one-shot. `.task` can re-fire
            // (system alerts or interstitials hopping on top) which would
            // stack biometry prompts — guard with `didAutoPromptBiometry`.
            guard !didAutoPromptBiometry else { return }
            didAutoPromptBiometry = true
            if vault.canUseBiometry { await tryBiometry() }
        }
        .animation(.easeInOut(duration: 0.25), value: showPasscode)
    }

    // Figma `2008:31953` central glyph: the iOS Face ID (or Touch ID) mark in
    // black; falls back to a lock when no biometry is enrolled.
    private var lockGlyph: some View {
        let symbol: String = vault.canUseBiometry
            ? (vault.biometryName == "Face ID" ? "faceid" : "touchid")
            : "lock.fill"
        return Image(systemName: symbol)
            .font(.system(size: 104, weight: .regular))
            .foregroundStyle(Color(hex: 0x191B23))
            .frame(width: 160, height: 160)
    }

    private var primaryActions: some View {
        VStack(spacing: 16) {
            if vault.canUseBiometry {
                Button(action: { Task { await tryBiometry() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: vault.biometryName == "Face ID" ? "faceid" : "touchid")
                            .font(.system(size: 20))
                        Text(L("vault.unlockFaceID", vault.biometryName))
                            .font(.custom("Inter-SemiBold", size: 17))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColor.brandPrimary)
                            .shadow(color: Color(hex: 0x004AC6).opacity(0.25), radius: 24, x: 0, y: 8)
                    )
                }
                .buttonStyle(.plain)
            }

            Button(action: { showPasscode = true }) {
                Text(L("passcode.usePasscode"))
                    .font(.custom("Inter-SemiBold", size: 17))
                    .foregroundStyle(AppColor.brandPrimary)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    // Full-screen passcode entry — SAME layout as Create/Change Passcode (glass
    // icon + Inter-Bold 24 title + subtitle + keypad) so the three passcode
    // screens look identical (was a small dimmed modal card → inconsistent).
    private var passcodeOverlay: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                glassIcon
                    .padding(.bottom, 32)

                Text(L("passcode.enterTitle"))
                    .font(.custom("Inter-Bold", size: 24))
                    .tracking(24 * -0.01)
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)

                Text(L("passcode.enterSub"))
                    .font(.custom("Inter-Regular", size: 16))
                    .foregroundStyle(Color(hex: 0x334155))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 32)

                if passcodeError {
                    Text(L("passcode.wrong"))
                        .font(.custom("Inter-Medium", size: 14))
                        .foregroundStyle(AppColor.danger)
                        .padding(.bottom, 16)
                }

                PasscodeKeypad(entry: $passcodeEntry, onComplete: tryPasscode)

                Spacer()

                Button(action: { showPasscode = false; passcodeEntry = ""; passcodeError = false }) {
                    Text(L("common.cancel"))
                        .font(.custom("Inter-SemiBold", size: 16))
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // Matches the glass shield icon used by Create/Change Passcode.
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
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 4)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.brandPrimary)
        }
    }

    private func tryBiometry() async {
        do {
            try await vault.unlockWithBiometry(reason: L("vault.unlockReason"))
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
