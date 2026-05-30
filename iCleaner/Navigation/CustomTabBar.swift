import SwiftUI

// Placeholder pill-style bottom tab bar. Re-skin against Figma node `2012:10599`
// (Home → Bottom Bars) once SVG icons are downloaded into TabBar/.
struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabItem(tab)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColor.surfaceBackground)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: -2)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let isActive = (selection == tab)
        VStack(spacing: 4) {
            Image(systemName: tab.systemImageName)
                .font(.system(size: 20, weight: isActive ? .semibold : .regular))
            Text(tab.title)
                .font(AppFont.tabLabel)
        }
        .foregroundStyle(isActive ? AppColor.tabActive : AppColor.tabInactive)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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

// Preview helper — pulled out to keep #Preview compact.
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content
    init(_ value: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: value)
        self.content = content
    }
    var body: some View { content($value) }
}
