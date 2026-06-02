import SwiftUI
import StoreKit
import LibEarnMoneyIOS

// Figma `2005:24603` (Setting). Sections:
//   • Premium banner "Cleaner Ultimate" with 3 feature bullets + Get Premium CTA.
//     Brand gradient (blue → teal), white text. Hides reactively when premium.
//   • Stay in Touch: Share Cleanup + Language (right value).
//   • Support: FAQ + Restore Purchase + Privacy Policy + Contact Us (extra row).
//
// Entry: gear icon on Home top bar → fullScreenCover. Internal navigation via
// NavigationStack — FAQ/Contact push, Paywall/Language present as cover.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var observedPremium = PermissionManager.shared.isPremium
    @AppStorage(PremiumGate.forcePremiumKey) private var forcePremium: Bool = false
    @AppStorage("app.languageCode") private var languageCode = "en-gb"
    @State private var showPaywall = false
    @State private var showLanguage = false
    @State private var showShareSheet = false
    @State private var restoreMessage: String?

    private var isPremium: Bool {
        #if DEBUG
        return observedPremium || forcePremium
        #else
        return observedPremium
        #endif
    }

    private var selectedLanguageName: String {
        Language.mock.first(where: { $0.code == languageCode })?.englishName ?? "English"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if !isPremium {
                        premiumBanner
                    }
                    stayInTouchSection
                    supportSection
                    #if DEBUG
                    developerSection
                    #endif
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.surfaceBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0F172A))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.custom("Inter-Bold", size: 20))
                        .tracking(20 * -0.025)
                        .foregroundStyle(Color(hex: 0x0F172A))
                }
            }
            .safeAreaInset(edge: .bottom) { BannerAdView(adUnitID: AdUnits.bannerSetting) }
        }
        .onReceive(PermissionManager.shared.$isPremium) { observedPremium = $0 }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .fullScreenCover(isPresented: $showLanguage) {
            LanguageView(initialCode: languageCode, showBack: true,
                         onStart: { code in languageCode = code; showLanguage = false },
                         onBack: { showLanguage = false })
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: ["Cleaner — keep your photo library tidy. https://apps.apple.com/app/id\(AppInfo.bundleID)"])
        }
        .alert("Restore Purchase", isPresented: Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button("OK", role: .cancel) { restoreMessage = nil }
        } message: { Text(restoreMessage ?? "") }
    }

    // MARK: - Developer section (DEBUG only)

    #if DEBUG
    private var developerSection: some View {
        SettingsSection(title: "Developer (DEBUG)") {
            HStack(spacing: 16) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColor.premiumGold)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Force Premium")
                        .font(.custom("Inter-Regular", size: 16))
                        .foregroundStyle(Color(hex: 0x0F172A))
                    Text("Bypass ads, paywall, quotas")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(Color(hex: 0x64748B))
                }
                Spacer()
                Toggle("", isOn: $forcePremium)
                    .labelsHidden()
                    .tint(AppColor.brandPrimary)
            }
            .padding(16)
        }
    }
    #endif

    // MARK: - Premium banner

    private var premiumBanner: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cleaner Ultimate")
                .font(.custom("Inter-Bold", size: 24))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                bullet("Instantly Detect Similar Photos")
                bullet("No Ads and Limits")
                bullet("Save Both Storage & Time")
            }

            Button(action: { showPaywall = true }) {
                Text("Get Premium")
                    .font(.custom("Inter-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppColor.brandPrimary)
                            .shadow(color: Color(hex: 0xBFDBFE), radius: 6, x: 0, y: 4)
                            .shadow(color: Color(hex: 0xBFDBFE), radius: 15, x: 0, y: 10)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Decorative cleaning illustration behind the text (Figma, 50% opacity).
        .background(alignment: .topTrailing) {
            Image("Settings/banner_clean")
                .resizable()
                .scaledToFit()
                .frame(width: 140)
                .opacity(0.5)
                .allowsHitTesting(false)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: 0x216FFC), Color(hex: 0x11C195)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColor.brandPrimary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image("Settings/ic_check")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(.white)
            Text(text)
                .font(.custom("Inter-Medium", size: 14))
                .foregroundStyle(Color(hex: 0xFDFDFD))
        }
    }

    // MARK: - Sections

    private var stayInTouchSection: some View {
        SettingsSection(title: "Stay in Touch") {
            SettingsRow(assetIcon: "Settings/ic_share", title: "Share Cleanup", action: { showShareSheet = true })
            divider
            SettingsRow(assetIcon: "Settings/ic_rate", title: "Rate Us", action: { requestReview() })
            divider
            SettingsRow(assetIcon: "Settings/ic_language", title: "Language", trailing: selectedLanguageName, action: { showLanguage = true })
        }
    }

    private var supportSection: some View {
        // FAQ / Terms / Privacy open their web pages IN-APP (WebViewScreen pushed
        // here), not in Safari. Order matches Figma 336:4696.
        SettingsSection(title: "Support") {
            NavigationLink(destination: WebViewScreen(title: "FAQ", url: AppInfo.faqURL)) {
                SettingsRowChrome(assetIcon: "Settings/ic_faq", title: "FAQ")
            }
            divider
            NavigationLink(destination: ContactView()) {
                SettingsRowChrome(assetIcon: "Settings/ic_contact", title: "Contact Us")
            }
            divider
            SettingsRow(assetIcon: "Settings/ic_restore", title: "Restore Purchase", action: restorePurchases)
            divider
            NavigationLink(destination: WebViewScreen(title: "Terms of Service", url: AppInfo.termsURL)) {
                SettingsRowChrome(assetIcon: "Settings/ic_terms", title: "Terms of Service")
            }
            divider
            NavigationLink(destination: WebViewScreen(title: "Privacy Policy", url: AppInfo.privacyURL)) {
                SettingsRowChrome(assetIcon: "Settings/ic_privacy", title: "Privacy Policy")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(hex: 0xF1F5F9))
            .frame(height: 1)
            .padding(.leading, 56)  // align past icon
    }

    // MARK: - Actions

    private func restorePurchases() {
        Task {
            await InAppService.shared.restore()
            await MainActor.run {
                restoreMessage = PremiumGate.isPremium
                    ? "Premium restored successfully."
                    : "No purchases to restore."
            }
        }
    }
}

// MARK: - Section + Row primitives

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("Inter-Bold", size: 12))
                .tracking(12 * 0.05)
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: 0x94A3B8))
            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppColor.surfaceBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: 0xE2E8F0), lineWidth: 1)
                )
        }
    }
}

private struct SettingsRow: View {
    var icon: String? = nil          // SF Symbol fallback
    var assetIcon: String? = nil     // Figma SVG/PNG from Assets.xcassets
    let title: String
    var trailing: String? = nil
    var tint: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowChrome(icon: icon, assetIcon: assetIcon, title: title, trailing: trailing, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRowChrome: View {
    var icon: String? = nil
    var assetIcon: String? = nil
    let title: String
    var trailing: String? = nil
    var tint: Color? = nil

    @ViewBuilder
    private var iconView: some View {
        if let assetIcon {
            // Template-render so the SVG fills the row tint (matches design).
            Image(assetIcon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        } else if let icon {
            Image(systemName: icon).font(.system(size: 18))
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            iconView
                .foregroundStyle(tint ?? Color(hex: 0x64748B))
                .frame(width: 24, height: 24)
            Text(title)
                .font(.custom("Inter-Regular", size: 16))
                .foregroundStyle(tint ?? Color(hex: 0x0F172A))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color(hex: 0x94A3B8))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0xCBD5E1))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - ShareSheet bridge

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
}
