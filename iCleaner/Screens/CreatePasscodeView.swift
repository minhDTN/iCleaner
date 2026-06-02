import SwiftUI

// Figma `2010:2243` (create pass). 2-step flow:
//   Step 1: choose a new 6-digit code
//   Step 2: re-enter to confirm
// On match → vault.setPasscode + auto-unlock. On mismatch → reset to step 1.
struct CreatePasscodeView: View {
    @Bindable var vault: VaultService

    @State private var step: Step = .choose
    @State private var firstEntry: String = ""
    @State private var secondEntry: String = ""
    @State private var mismatch: Bool = false
    @State private var saveError: String?

    private enum Step { case choose, confirm }

    var body: some View {
        VStack(spacing: 0) {
            VaultHeader(title: L("vault.title"))

            ZStack {
                AppColor.surfaceBackground.ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    glassIcon
                        .padding(.bottom, 32)

                Text(step == .choose ? L("passcode.create") : L("passcode.reenter"))
                    .font(.custom("Inter-Bold", size: 24))
                    .tracking(24 * -0.01)
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)

                Text(step == .choose ? L("passcode.createSub") : L("passcode.confirmSub"))
                    .font(.custom("Inter-Regular", size: 16))
                    .foregroundStyle(Color(hex: 0x334155))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 32)

                if mismatch {
                    Text(L("passcode.mismatch"))
                        .font(.custom("Inter-Medium", size: 14))
                        .foregroundStyle(AppColor.danger)
                        .padding(.bottom, 16)
                }

                PasscodeKeypad(
                    entry: step == .choose ? $firstEntry : $secondEntry,
                    onComplete: handleComplete
                )

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .alert(L("passcode.saveErrorTitle"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
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
                .overlay(
                    Circle().stroke(Color(hex: 0xE2E8F0), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 4)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.brandPrimary)
        }
    }

    private func handleComplete(_ code: String) {
        switch step {
        case .choose:
            // small delay so user sees the 6th dot fill before screen swaps
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                step = .confirm
                mismatch = false
            }
        case .confirm:
            if secondEntry == firstEntry {
                do {
                    try vault.setPasscode(firstEntry)
                    _ = vault.verifyPasscode(firstEntry)  // sets isUnlocked = true
                } catch {
                    saveError = L("passcode.saveErrorBody")
                }
            } else {
                mismatch = true
                firstEntry = ""
                secondEntry = ""
                step = .choose
            }
        }
    }
}

#Preview {
    CreatePasscodeView(vault: VaultService())
}
