import SwiftUI

// Figma `2005:23337` (popup delete image). Modal over the review screen.
// Backdrop rgba(0,0,0,0.5). Card 326 wide, white bg, stroke #3B82F6 1px,
// radius 24, padding 24. Stacked layout: Title (Inter Bold 20/28 #0F172A)
// + body (Inter Regular 14/22.75 #64748B 2 lines) + Delete (red #EF4444,
// Inter Bold 16/24 white, padding 16/0, radius 16) + Cancel (text only).
struct SimilarDeleteConfirm: View {
    let photoCount: Int
    let sizeMB: Int
    var onCancel: () -> Void
    var onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 6.9) {
                Text("Delete \(photoCount) Photos?")
                    .font(.custom("Inter-Bold", size: 20))
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .multilineTextAlignment(.center)

                Text("These \(sizeMB) MB of photos will be\npermanently removed.")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color(hex: 0x64748B))
                    .multilineTextAlignment(.center)
                    .lineSpacing(22.75 - 14)

                VStack(spacing: 12) {
                    Button(action: onDelete) {
                        Text("Delete")
                            .font(.custom("Inter-Bold", size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppColor.danger)
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
                    .stroke(Color(hex: 0x3B82F6), lineWidth: 1)
            )
        }
    }
}

#Preview {
    SimilarDeleteConfirm(photoCount: 5, sizeMB: 12, onCancel: {}, onDelete: {})
}
