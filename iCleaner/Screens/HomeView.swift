import SwiftUI

// Figma: node `2005:21769` (home — populated state) / `2005:22671` (empty state).
// Layout: "Your Storage" header → Quick Clean CTA → 8 category section cards
// (Similar, Duplicates, Similar Screenshots, Similar Videos, Other Screenshots,
// Chat Photos, Videos Organizer, Other) → 4-tab bottom bar (rendered by RootView).
struct HomeView: View {
    var body: some View {
        PlaceholderScreen(title: "Home", subtitle: "Your storage dashboard — coming next")
    }
}

#Preview {
    HomeView()
}
