import SwiftUI

// Figma: dashboard `2012:3559` + sub-screens for Duplicates (`2012:3978`),
// Incomplete (`2012:4274`), All Contacts (`2012:4832`), Backups (`2012:4599`).
struct ContactsView: View {
    var body: some View {
        PlaceholderScreen(title: "Contacts", subtitle: "Duplicates · Incomplete · Backup")
    }
}

#Preview {
    ContactsView()
}
