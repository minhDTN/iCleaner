import SwiftUI

// Figma: picker `2005:22138` → confirm `2005:22335` → progress `2005:23000`
// → result `2005:22563` (Replace / Keep Both). Daily free-tier quota 2/day,
// resets at local midnight (TODO: wire RemoteConfig `compress_daily_limit`).
struct CompressView: View {
    var body: some View {
        PlaceholderScreen(title: "Compress", subtitle: "Best · Balanced · Maximum Savings")
    }
}

#Preview {
    CompressView()
}
