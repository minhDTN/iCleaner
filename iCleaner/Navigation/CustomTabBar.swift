import SwiftUI

// Figma `2012:10599` (Bottom Bars).
// Bg #FFFFFF, top stroke 1px #B2B2B2, padding 10px vertical / 20px horizontal,
// 25px gap between items. Each tab: 36×36 icon + label below (2px gap),
// active = brand blue + Inter Bold 10, inactive = #9E9E9E + Inter Medium 10.
// SVGs are template-rendered so the same asset serves both states.
struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(alignment: .center, spacing: 25) {
            ForEach(AppTab.allCases) { tab in
                tabItem(tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            AppColor.surfaceBackground
                .overlay(
                    Rectangle()
                        .fill(Color(hex: 0xB2B2B2))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let isActive = (selection == tab)
        let tint: Color = isActive ? AppColor.brandPrimary : Color(hex: 0x9E9E9E)

        VStack(spacing: 2) {
            Image(tab.iconAssetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .foregroundStyle(tint)
            Text(tab.title)
                .font(.custom(isActive ? "Inter-Bold" : "Inter-Medium", size: 10))
                .foregroundStyle(tint)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            var txn = Transaction()
            txn.disablesAnimations = true
            withTransaction(txn) { selection = tab }
        }
    }
}

#Preview {
    StatefulPreviewWrapper(AppTab.home) { binding in
        CustomTabBar(selection: binding)
    }
}

struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content
    init(_ value: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: value)
        self.content = content
    }
    var body: some View { content($value) }
}
