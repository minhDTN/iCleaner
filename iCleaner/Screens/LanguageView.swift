import SwiftUI

// Figma `2005:23857` (language).
// Bg #F3F4F6. Top: status bar + nav row (back + title). Search input white bg with
// brand-blue stroke. Two sections: "Selected" + "All language" (Inter Medium 14/150%
// #6D7E95). Bottom: orange `Let's Start` CTA (#FF7D37, Inter Bold 14 white).
//
// MVP scope: 10 languages with downloaded flag PNGs. The full 25-language list +
// search filter + locale switching wiring lands when localization ships. Back arrow
// and search magnifier are SF Symbols until specific assets are downloaded.
struct LanguageView: View {
    @State private var selectedCode: String = "en-gb"
    @State private var query: String = ""
    var onStart: () -> Void = {}
    var onBack: () -> Void = {}

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
                            section(title: "Selected") {
                                row(language: sel, isSelected: true)
                            }
                        }
                        section(title: "All language") {
                            VStack(spacing: 0) {
                                ForEach(filteredAll) { lang in
                                    row(language: lang, isSelected: false)
                                        .onTapGesture { selectedCode = lang.code }
                                }
                            }
                        }
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
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 24, height: 24)
            }
            Text("Language")
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.brandPrimary)
                .frame(width: 20, height: 20)
            TextField("Enter name of Language...", text: $query)
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
            Button(action: onStart) {
                Text("Let’s Start")
                    .font(.custom("Inter-Bold", size: 14))
                    .foregroundStyle(Color(hex: 0xEAF4FC))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: 0xFF7D37))
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

    // Subset of design's full list. Expand when localization ships.
    static let mock: [Language] = [
        .init(code: "en-gb", englishName: "English",     nativeName: "English – UK / System Default", flagAssetName: "Flags/flag_gb"),
        .init(code: "en-us", englishName: "English (US)", nativeName: "English – United States",      flagAssetName: "Flags/flag_us"),
        .init(code: "vi",    englishName: "Vietnamese",   nativeName: "Tiếng Việt",                   flagAssetName: "Flags/flag_vn"),
        .init(code: "es",    englishName: "Spanish",      nativeName: "Español",                       flagAssetName: "Flags/flag_es"),
        .init(code: "fr",    englishName: "French",       nativeName: "Français",                      flagAssetName: "Flags/flag_fr"),
        .init(code: "de",    englishName: "German",       nativeName: "Deutsch",                       flagAssetName: "Flags/flag_de"),
        .init(code: "ja",    englishName: "Japanese",     nativeName: "日本語",                         flagAssetName: "Flags/flag_jp"),
        .init(code: "ko",    englishName: "Korean",       nativeName: "한국어",                         flagAssetName: "Flags/flag_kr"),
        .init(code: "zh",    englishName: "Chinese",      nativeName: "中文",                           flagAssetName: "Flags/flag_cn"),
        .init(code: "id",    englishName: "Indonesian",   nativeName: "Bahasa Indonesia",              flagAssetName: "Flags/flag_id"),
    ]
}

#Preview {
    LanguageView()
}
