import SwiftUI

// Generic scaffold for screens that aren't built yet. Replace per-tab as Figma screens land.
struct PlaceholderScreen: View {
    let title: String
    var subtitle: String = "Coming soon"

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(title)
                .appTitleLarge()
            Text(subtitle)
                .font(AppFont.bodyLarge)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surfaceBackground)
    }
}

#Preview {
    PlaceholderScreen(title: "Home")
}
