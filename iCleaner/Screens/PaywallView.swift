import SwiftUI

// Figma: `2005:22730` / `2005:22823` / `2005:22916` (three IAP variants — likely
// trial-off / trial-on / monthly-highlighted). Layout: Unlock More Storage hero
// → Photos / Drive source pills → storage usage bar → Cleaner Pro premium card
// ($1.99/week) → Enable Free Trial toggle → Monthly $4.99 → Continue CTA.
struct PaywallView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Cleaner Pro",
            subtitle: "$1.99/week · 3-day free trial · $4.99/month"
        )
    }
}

#Preview {
    PaywallView()
}
