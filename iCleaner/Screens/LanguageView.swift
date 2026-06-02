import SwiftUI

// Figma `2005:23857` (language).
// Bg #F3F4F6. Top: status bar + nav row (back + title). Search input white bg with
// brand-blue stroke. Two sections: "Selected" + "All language" (Inter Medium 14/150%
// #6D7E95). Bottom: brand-blue `Let's Start` CTA (Inter Bold 14 white). The chosen
// code is returned via onStart and persisted by the caller (app.languageCode).
//
// MVP scope: 10 languages with downloaded flag PNGs. The full 25-language list +
// search filter + locale switching wiring lands when localization ships. Back arrow
// and search magnifier are SF Symbols until specific assets are downloaded.
struct LanguageView: View {
    @State private var selectedCode: String
    @State private var query: String = ""
    var showBack: Bool                  // hidden on the first-launch onboarding
    var onStart: (String) -> Void
    var onBack: () -> Void

    init(initialCode: String = "en-gb",
         showBack: Bool = true,
         onStart: @escaping (String) -> Void = { _ in },
         onBack: @escaping () -> Void = {}) {
        _selectedCode = State(initialValue: initialCode)   // start on the saved language
        self.showBack = showBack
        self.onStart = onStart
        self.onBack = onBack
    }

    private var filteredAll: [Language] {
        let others = Language.mock.filter { $0.code != selectedCode }
        guard !query.isEmpty else { return others }
        let q = query.lowercased()
        return others.filter {
            $0.englishName.lowercased().contains(q) || $0.nativeName.lowercased().contains(q)
        }
    }

    private var selected: Language? {
        Language.mock.first(where: { $0.code == selectedCode })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0xF3F4F6).ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(spacing: 20) {
                        searchField
                        if let sel = selected {
                            section(title: L("lang.selected")) {
                                row(language: sel, isSelected: true)
                            }
                        }
                        section(title: L("lang.all")) {
                            VStack(spacing: 0) {
                                ForEach(filteredAll) { lang in
                                    row(language: lang, isSelected: false)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedCode = lang.code }
                                }
                            }
                        }
                        // Scenario: Language screen → native (native_language).
                        NativeAdView(adUnitID: AdUnits.nativeLanguage, height: 120)
                        Spacer(minLength: 100)  // Room for the floating Let's Start.
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }

            letsStartButton
        }
    }

    private var navBar: some View {
        HStack(spacing: 16) {
            if showBack {
                Button(action: onBack) {
                    Image("Common/ic_arrow_left")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(width: 24, height: 24)
                }
            }
            Text(L("lang.title"))
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .background(AppColor.surfaceBackground)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image("Common/ic_search")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppColor.brandPrimary)
                .frame(width: 20, height: 20)
            TextField(L("lang.search"), text: $query)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(AppColor.textPrimary)
                .tint(AppColor.brandPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppColor.surfaceBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColor.brandPrimary, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.custom("Inter-Medium", size: 14))
                .foregroundStyle(Color(hex: 0x6D7E95))
            content()
        }
    }

    private func row(language: Language, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(language.flagAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(language.englishName)
                    .font(.custom("Inter-SemiBold", size: 15))
                    .foregroundStyle(AppColor.textPrimary)
                Text(language.nativeName)
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(Color(hex: 0x6D7E95))
            }
            Spacer()
            Circle()
                .strokeBorder(
                    isSelected ? AppColor.brandPrimary : Color(hex: 0xCBD5E1),
                    lineWidth: isSelected ? 6 : 2
                )
                .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColor.surfaceBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? AppColor.brandPrimary : Color.clear, lineWidth: isSelected ? 1 : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 8)
    }

    private var letsStartButton: some View {
        VStack(spacing: 0) {
            Button(action: { Localizer.shared.setLanguage(selectedCode); onStart(selectedCode) }) {
                Text(L("lang.start"))
                    .font(.custom("Inter-Bold", size: 14))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppColor.brandPrimary)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(hex: 0xEAF4FC))
    }
}

struct Language: Identifiable {
    let code: String
    let englishName: String
    let nativeName: String
    let flagAssetName: String
    var id: String { code }

    // Full 25-language list matching Figma design. Flags @3x downloaded into
    // Assets.xcassets/Flags/ from the Figma component-set (300:993 family).
    static let mock: [Language] = [
        .init(code: "en-gb",  englishName: "English",       nativeName: "English – UK / System Default", flagAssetName: "Flags/flag_gb"),
        .init(code: "en-us",  englishName: "English (US)",  nativeName: "English – United States",       flagAssetName: "Flags/flag_us"),
        .init(code: "en-au",  englishName: "English (AU)",  nativeName: "English – Australia",           flagAssetName: "Flags/flag_au"),
        .init(code: "en-ca",  englishName: "English (CA)",  nativeName: "English – Canada",              flagAssetName: "Flags/flag_ca"),
        .init(code: "en-in",  englishName: "English (IN)",  nativeName: "English – India",               flagAssetName: "Flags/flag_in"),
        .init(code: "es",     englishName: "Spanish",       nativeName: "Español",                        flagAssetName: "Flags/flag_es"),
        .init(code: "es-mx",  englishName: "Spanish (MX)",  nativeName: "Español – México",               flagAssetName: "Flags/flag_mx"),
        .init(code: "pt",     englishName: "Portuguese",    nativeName: "Português",                      flagAssetName: "Flags/flag_pt"),
        .init(code: "pt-br",  englishName: "Portuguese (BR)", nativeName: "Português – Brasil",          flagAssetName: "Flags/flag_br"),
        .init(code: "fr",     englishName: "French",        nativeName: "Français",                       flagAssetName: "Flags/flag_fr"),
        .init(code: "de",     englishName: "German",        nativeName: "Deutsch",                        flagAssetName: "Flags/flag_de"),
        .init(code: "it",     englishName: "Italian",       nativeName: "Italiano",                       flagAssetName: "Flags/flag_it"),
        .init(code: "nl",     englishName: "Dutch",         nativeName: "Nederlands",                     flagAssetName: "Flags/flag_nl"),
        .init(code: "tr",     englishName: "Turkish",       nativeName: "Türkçe",                         flagAssetName: "Flags/flag_tr"),
        .init(code: "uk",     englishName: "Ukrainian",     nativeName: "Українська",                     flagAssetName: "Flags/flag_ua"),
        .init(code: "ru",     englishName: "Russian",       nativeName: "Русский",                        flagAssetName: "Flags/flag_ru"),
        .init(code: "he",     englishName: "Hebrew",        nativeName: "עברית",                          flagAssetName: "Flags/flag_il"),
        .init(code: "ar",     englishName: "Arabic",        nativeName: "العربية",                        flagAssetName: "Flags/flag_sa"),
        .init(code: "fa",     englishName: "Persian",       nativeName: "فارسی",                          flagAssetName: "Flags/flag_ir"),
        .init(code: "id",     englishName: "Indonesian",    nativeName: "Bahasa Indonesia",               flagAssetName: "Flags/flag_id"),
        .init(code: "vi",     englishName: "Vietnamese",    nativeName: "Tiếng Việt",                    flagAssetName: "Flags/flag_vn"),
        .init(code: "ja",     englishName: "Japanese",      nativeName: "日本語",                          flagAssetName: "Flags/flag_jp"),
        .init(code: "ko",     englishName: "Korean",        nativeName: "한국어",                          flagAssetName: "Flags/flag_kr"),
        .init(code: "zh-cn",  englishName: "Chinese",       nativeName: "简体中文",                         flagAssetName: "Flags/flag_cn"),
        .init(code: "zh-tw",  englishName: "Chinese (TW)",  nativeName: "繁體中文",                         flagAssetName: "Flags/flag_tw"),
    ]
}

#Preview {
    LanguageView()
}
