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
        .alert("Purchase failed", isPresented: Binding(
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
                Text("Restore")
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
            Text("Unlock More Storage")
                .font(.custom("Inter-Bold", size: 30))
                .tracking(30 * -0.025)
                .foregroundStyle(Color(hex: 0x0F172A))
                .multilineTextAlignment(.center)

            Text("Keep what you want, remove the unnecessary!")
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
            sourcePill(label: "Photos", assetIcon: "Paywall/ic_source_photos", iconSize: 48)
            sourcePill(label: "Drive",  assetIcon: "Paywall/ic_source_drive",  iconSize: 68)
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

    private var storageBar: some View {
        let total = storage?.total ?? 64
        let used  = storage?.used  ?? 0
        let usedStr  = String(format: "%.0f GB", used)
        let totalStr = String(format: "%.0f GB", total)

        // Figma text style: '{used red} of {total blue} used' — the total volume
        // uses brand-blue-500 (#3B82F6), not muted grey.
        return HStack {
            (Text(usedStr).foregroundStyle(Color(hex: 0xF63B3B))
             + Text(" of ").foregroundStyle(Color(hex: 0x64748B))
             + Text(totalStr).foregroundStyle(Color(hex: 0x3B82F6))
             + Text(" used").foregroundStyle(Color(hex: 0x64748B)).fontWeight(.medium))
                .font(.custom("Inter-Bold", size: 18))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(
            Capsule().fill(AppColor.surfaceBackground)
        )
        .overlay(
            Capsule().stroke(Color(hex: 0xE2E8F0), lineWidth: 1)
        )
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
                    Text("Cleaner Pro")
                        .font(.custom("Inter-Bold", size: 20))
                        .foregroundStyle(Color(hex: 0x0F172A))
                    Spacer()
                    Text("Premium")
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

                Text("Smart Cleaning, VideoCompressor, No Limits.")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color(hex: 0x475569))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text("$1.99")
                        .font(.custom("Inter-Bold", size: 20))
                        .foregroundStyle(Color(hex: 0x0F172A))
                    Text("/week")
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
            Text("Enable Free Trial")
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
                    Text("Monthly")
                        .font(.custom("Inter-Bold", size: 16))
                        .foregroundStyle(Color(hex: 0x0F172A))
                    Text("Full access, cancel anytime")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(Color(hex: 0x64748B))
                }
                Spacer()
                Text("$4.99/month")
                    .font(.custom("Inter-Regular", size: 10))
                    .foregroundStyle(Color(hex: 0x94A3B8))
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
                        Text("Continue")
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
                Link("Terms of Use", destination: AppInfo.termsURL)
                Spacer()
                Link("Privacy Policy", destination: AppInfo.privacyURL)
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
            purchaseError = "Subscription product unavailable"
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
                    purchaseError = "No purchases to restore."
                }
            }
        }
    }
}

#Preview {
    PaywallView()
}
