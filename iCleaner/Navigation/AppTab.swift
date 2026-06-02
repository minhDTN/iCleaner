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

    var iconAssetName: String {
        switch self {
        case .home:     return "TabBar/tab_home"
        case .contacts: return "TabBar/tab_contacts"
        case .vault:    return "TabBar/tab_vault"
        case .compress: return "TabBar/tab_compress"
        }
    }
}
