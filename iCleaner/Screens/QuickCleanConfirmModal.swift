import SwiftUI

// Figma `2005:23105` (Quick clean popup). Same chrome as SimilarDeleteConfirm
// (white card + brand-blue stroke + shadow) but with brand-blue Clean Now CTA
// instead of destructive red Delete.
struct QuickCleanConfirmModal: View {
    let sizeMB: Int
    let photoCount: Int
    let groupCount: Int
    var onCancel: () -> Void
    var onClean: () -> Void

    var body: some View {
        VStack(spacing: 6.9) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.brandPrimary)
                .padding(.bottom, 8)

            Text("Confirm Quick Clean?")
                .font(.custom("Inter-Bold", size: 20))
                .foregroundStyle(Color(hex: 0x0F172A))
                .multilineTextAlignment(.center)

            Text("This will permanently delete \(sizeMB) MB across \(groupCount) similar groups (\(photoCount) photos).")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(Color(hex: 0x64748B))
                .multilineTextAlignment(.center)
                .lineSpacing(22.75 - 14)

            VStack(spacing: 12) {
                Button(action: onClean) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Clean Now")
                            .font(.custom("Inter-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColor.brandPrimary)
                    )
                }
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.custom("Inter-SemiBold", size: 16))
                        .foregroundStyle(Color(hex: 0x64748B))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.top, 25)
        }
        .padding(24)
        .frame(width: 326)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColor.surfaceBackground)
                .shadow(color: .black.opacity(0.25), radius: 25, x: 0, y: 25)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppColor.brandPrimary, lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.5).ignoresSafeArea()
        QuickCleanConfirmModal(sizeMB: 320, photoCount: 45, groupCount: 6, onCancel: {}, onClean: {})
    }
}
