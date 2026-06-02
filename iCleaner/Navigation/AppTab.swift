import Foundation

// Order here drives the tab bar order: Home / Vault / Contacts / Compress.
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case vault
    case contacts
    case compress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:     return "Home"
        case .contacts: return "Contacts"
        case .vault:    return "Vault"
        case .compress: return "Compress"
        }
    }

    // Localization key (resolved at render time so the tab bar follows the in-app language).
    var titleKey: String {
        switch self {
        case .home:     return "tab.home"
        case .contacts: return "tab.contacts"
        case .vault:    return "tab.vault"
        case .compress: return "tab.compress"
        }
    }

    var iconAssetName: String {
        switch self {
        case .home:     return "TabBar/tab_home"
        case .contacts: return "TabBar/tab_contacts"
        case .vault:    return "TabBar/tab_vault"
        case .compress: return "TabBar/tab_compress"
        }
    }
}
