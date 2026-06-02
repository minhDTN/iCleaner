import Foundation
import Observation

// Runtime, in-app localization that switches the UI language from the in-app
// Language picker (app.languageCode) — independent of the iOS system language.
//
// Views read strings via the global `L("key")`, which reads `Localizer.shared.code`;
// because Localizer is @Observable, changing the language re-renders every view that
// shows a localized string. Unknown keys/languages fall back to English then the key,
// so partial translations never break the UI.
@MainActor
@Observable
final class Localizer {
    static let shared = Localizer()
    static let storageKey = "app.languageCode"

    var code: String

    private init() {
        code = UserDefaults.standard.string(forKey: Self.storageKey) ?? "en-gb"
    }

    func setLanguage(_ newCode: String) {
        code = newCode
        UserDefaults.standard.set(newCode, forKey: Self.storageKey)
    }

    func string(_ key: String) -> String {
        let lang = Self.langKey(for: code)   // reading `code` registers the SwiftUI dependency
        return LocalizedStrings.table[lang]?[key]
            ?? LocalizedStrings2.table[lang]?[key]
            ?? LocalizedStrings3.table[lang]?[key]
            ?? LocalizedStrings.table["en"]?[key]
            ?? LocalizedStrings2.table["en"]?[key]
            ?? LocalizedStrings3.table["en"]?[key]
            ?? key
    }

    /// Maps an app language code (en-gb, es-mx, pt-br, zh-cn…) to a translation set.
    static func langKey(for code: String) -> String {
        switch code {
        case "en-gb", "en-us", "en-au", "en-ca", "en-in": return "en"
        case "es", "es-mx":                                return "es"
        case "pt", "pt-br":                                return "pt"
        case "zh-cn":                                      return "zh-Hans"
        case "zh-tw":                                      return "zh-Hant"
        default:                                           return code
        }
    }
}

/// Localized lookup for the current in-app language. Use everywhere a UI string shows.
@MainActor
func L(_ key: String) -> String { Localizer.shared.string(key) }

/// Localized + `String(format:)` for strings with placeholders (e.g. "%d Videos").
@MainActor
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localizer.shared.string(key), arguments: args)
}
