//
//  PlaceholderScreen.swift
//  QRCode
//

import SwiftUI

struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(title)
                .appTitleLarge()
            Text("Coming soon")
                .font(AppFont.bodyLarge)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    PlaceholderScreen(title: "Scan")
}
