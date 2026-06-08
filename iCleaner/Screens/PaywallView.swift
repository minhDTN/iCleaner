import SwiftUI
import LibEarnMoneyIOS

// Figma `2005:22730` (IAP).
// Layout: top bar (Restore left + close right) → "Unlock More Storage" hero
// → 2 source pills (Photos / Drive) decorative → storage usage bar (real device
// stats) → Cleaner Pro card (blue stroke 2px, "$1.99 /week" + Premium pill)
// → "Enable Free Trial" toggle row (slate-50 bg) → Monthly card ($4.99/month)
// → bottom bar with Continue CTA + Terms/Privacy footer links.
//
// Selected plan:
//   • .weekly  + trial OFF → product = MyProduct.weekly
//   • .weekly  + trial ON  → product = MyProduct.weeklyTrial
//   • .monthly             → product = MyProduct.monthly
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: Plan = .weekly
    @State private var trialEnabled: Bool = true
    @State private var isPurchasing: Bool = false
    @State private var purchaseError: String?
    @State private var storage: (used: Double, total: Double, free: Double)?

    private enum Plan { case weekly, monthly }

    private var selectedProductID: String {
        switch selectedPlan {
        case .weekly:  return trialEnabled ? MyProduct.weeklyTrial.id : MyProduct.weekly.id
        case .monthly: return MyProduct.monthly.id
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surfaceBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    topBar
                    heading
                    sourcePills
                    storageBar
                    pricingCards
                    Spacer(minLength: 120)  // room for sticky Continue bar
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .scrollIndicators(.hidden)

            stickyBottomBar
        }
        .alert(L("paywall.purchaseFailTitle"), isPresented: Binding(
            get: { purchaseError != nil },
            set: { if !$0 { purchaseError = nil } }
        )) {
            Button("OK", role: .cancel) { purchaseError = nil }
        } message: { Text(purchaseError ?? "") }
        .task {
            storage = DeviceStorage.snapshot()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: restore) {
                Text(L("paywall.restore"))
                    .font(.custom("Inter-Medium", size: 14))
                    .foregroundStyle(Color(hex: 0x94A3B8))
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(hex: 0xF1F5F9)))
            }
        }
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(spacing: 8) {
            Text(L("paywall.unlockStorage"))
                .font(.custom("Inter-Bold", size: 30))
                .tracking(30 * -0.025)
                .foregroundStyle(Color(hex: 0x0F172A))
                .multilineTextAlignment(.center)

            Text(L("paywall.subtitle"))
                .font(.custom("Inter-Medium", size: 14))
                .foregroundStyle(Color(hex: 0x64748B))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Source pills

    private var sourcePills: some View {
        HStack(spacing: 48) {
            // Figma icon frames differ in size on purpose: Photos glyph fills its
            // canvas edge-to-edge (48pt) while the Drive logo has built-in
            // whitespace, so it's drawn at 68pt to look visually balanced.
            sourcePill(label: L("paywall.photos"), assetIcon: "Paywall/ic_source_photos", iconSize: 48)
            sourcePill(label: L("paywall.drive"),  assetIcon: "Paywall/ic_source_drive",  iconSize: 68)
        }
        .frame(maxWidth: .infinity)
    }

    private func sourcePill(label: String, assetIcon: String, iconSize: CGFloat) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColor.surfaceBackground)
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: 0xF8FAFC), lineWidth: 1)
                    )
                Image(assetIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            }
            Text(label)
                .font(.custom("Inter-SemiBold", size: 14))
                .foregroundStyle(Color(hex: 0x475569))
        }
    }

    // MARK: - Storage usage bar

    // Figma `2005:22774`: a progress bar (NOT a text capsule). Track #F1F5F9 +
    // #E2E8F0 1px stroke, pill, 32h; red used-fill #F63B3B (30h, 1px inset, pill)
    // sized to used/total with a blue glow; text below in plain (no border):
    // used=red, total=blue, rest grey, Inter Bold 18/20 centered. 12pt gap.
    private var storageBar: some View {
        let total = storage?.total ?? 64
        let used  = storage?.used  ?? 0
        let fraction = total > 0 ? min(1, max(0, used / total)) : 0
        let usedStr  = String(format: "%.0f GB", used)
        let totalStr = String(format: "%.0f GB", total)

        return VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color(hex: 0xF1F5F9))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color(hex: 0xE2E8F0), lineWidth: 1)
                        )
                    Capsule(style: .continuous)
                        .fill(Color(hex: 0xF63B3B))
                        .frame(width: max(0, (geo.size.width - 2) * fraction), height: 30)
                        // Figma effect_RY2C1I — 0 0 15 rgba(59,130,246,0.4) blue glow.
                        .shadow(color: Color(hex: 0x3B82F6).opacity(0.4), radius: 7.5)
                        .padding(.leading, 1)
                }
            }
            .frame(height: 32)

            (Text(usedStr).foregroundStyle(Color(hex: 0xF63B3B))
             + Text(L("paywall.of")).foregroundStyle(Color(hex: 0x64748B))
             + Text(totalStr).foregroundStyle(Color(hex: 0x3B82F6))
             + Text(L("paywall.used")).foregroundStyle(Color(hex: 0x64748B)))
                .font(.custom("Inter-Bold", size: 18))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Pricing

    private var pricingCards: some View {
        VStack(spacing: 16) {
            weeklyCard
            trialToggleRow
            monthlyCard
        }
    }

    private var weeklyCard: some View {
        Button(action: { selectedPlan = .weekly }) {
            VStack(alignment: .leading, spacing: 10.9) {
                HStack {
                    Text(L("paywall.proTitle"))
                        .font(.custom("Inter-Bold", size: 20))
                        .foregroundStyle(Color(hex: 0x0F172A))
                    Spacer()
                    Text(L("paywall.premium"))
                        .font(.custom("Inter-Bold", size: 10))
                        .tracking(10 * 0.05)
                        .textCase(.uppercase)
                        .foregroundStyle(Color(hex: 0x3B82F6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color(hex: 0x3B82F6).opacity(0.1))
                        )
                }

                Text(L("paywall.features"))
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color(hex: 0x475569))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text("$1.99")
                        .font(.custom("Inter-Bold", size: 20))
                        .foregroundStyle(Color(hex: 0x0F172A))
                    Text(L("paywall.perWeek"))
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(Color(hex: 0x64748B))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColor.surfaceBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selectedPlan == .weekly ? Color(hex: 0x3B82F6) : Color(hex: 0xE5E7EB),
                        lineWidth: selectedPlan == .weekly ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var trialToggleRow: some View {
        HStack(spacing: 12) {
            Image("Paywall/ic_gift")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            Text(L("paywall.enableTrial"))
                .font(.custom("Inter-SemiBold", size: 16))
                .foregroundStyle(Color(hex: 0x334155))
            Spacer()
            Toggle("", isOn: $trialEnabled)
                .labelsHidden()
                .tint(Color(hex: 0x3B82F6))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: 0xF8FAFC))
        )
        .disabled(selectedPlan != .weekly)
        .opacity(selectedPlan == .weekly ? 1 : 0.5)
    }

    private var monthlyCard: some View {
        Button(action: { selectedPlan = .monthly }) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("paywall.monthly"))
                        .font(.custom("Inter-Bold", size: 16))
                        .foregroundStyle(Color(hex: 0x0F172A))
                    Text(L("paywall.monthlyDesc"))
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(Color(hex: 0x64748B))
                }
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text("$4.99")
                        .font(.custom("Inter-Bold", size: 20))
                        .foregroundStyle(Color(hex: 0x0F172A))
                    Text("/month")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(Color(hex: 0x64748B))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColor.surfaceBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selectedPlan == .monthly ? Color(hex: 0x3B82F6) : Color(hex: 0xE5E7EB),
                        lineWidth: selectedPlan == .monthly ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sticky bottom bar

    private var stickyBottomBar: some View {
        VStack(spacing: 10) {
            Button(action: subscribe) {
                ZStack {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(L("paywall.continue"))
                            .font(.custom("Inter-Bold", size: 16))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: 0x3B82F6))
                        .shadow(color: Color(hex: 0x3B82F6).opacity(0.25), radius: 6, x: 0, y: 4)
                        .shadow(color: Color(hex: 0x3B82F6).opacity(0.25), radius: 15, x: 0, y: 10)
                )
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)

            HStack {
                Link(L("paywall.terms"), destination: AppInfo.termsURL)
                Spacer()
                Link(L("paywall.privacy"), destination: AppInfo.privacyURL)
            }
            .font(.custom("Inter-Medium", size: 11))
            .foregroundStyle(Color(hex: 0x94A3B8))
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(
            AppColor.surfaceBackground
                .overlay(
                    Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Purchase

    private func subscribe() {
        guard let cfg = LibEarnMoneyIOS.shared.config,
              let product = cfg.products.first(where: { $0.id == selectedProductID }) else {
            purchaseError = L("paywall.unavailable")
            return
        }
        isPurchasing = true
        Task {
            defer { Task { @MainActor in isPurchasing = false } }
            do {
                _ = try await InAppService.shared.purchase(product)
                AnalyticsManager.shared.logStoreKit2Transaction(productId: product.id)
                await MainActor.run { dismiss() }
            } catch InAppError.userCancelled {
                // user cancelled — no-op
            } catch {
                await MainActor.run { purchaseError = error.localizedDescription }
            }
        }
    }

    private func restore() {
        Task {
            await InAppService.shared.restore()
            await MainActor.run {
                if PermissionManager.shared.isPremium {
                    dismiss()
                } else {
                    purchaseError = L("paywall.noRestore")
                }
            }
        }
    }
}

#Preview {
    PaywallView()
}
