import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case contacts
    case vault
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

    // SF Symbol fallback — swap to asset-catalog Figma icons (TabBar/ic_tab_*) when downloaded.
    var systemImageName: String {
        switch self {
        case .home:     return "house.fill"
        case .contacts: return "person.crop.circle"
        case .vault:    return "lock.shield.fill"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        }
    }
}
