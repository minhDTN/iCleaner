import SwiftUI

// Figma: `2005:24774` (Splash) — centered `iCLENER` wordmark + 8 loading dots
// alternating brand blue/grey + footnote "This action can contain ads".
// Note: the lib's own SplashConfig handles the actual cold-start splash via
// `Splash/splash_logo` asset; this view is only used for in-app re-entry / preview.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("iCLENER")
                .font(AppFont.titleLarge)
                .foregroundStyle(AppColor.brandPrimary)
            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { idx in
                    Circle()
                        .fill(idx.isMultiple(of: 2) ? AppColor.brandPrimary : AppColor.borderLight)
                        .frame(width: 8, height: 8)
                }
            }
            Spacer()
            Text("This action can contain ads")
                .appCaption()
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surfaceBackground)
    }
}

#Preview {
    SplashView()
}
