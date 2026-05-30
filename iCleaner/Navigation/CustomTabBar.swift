//
//  CustomTabBar.swift
//  QRCode
//
//  Pill-style tab bar matching Figma node 20:321 (Setting → TabBar).
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selection: AppTab
    /// When true, the container becomes glass material (for screens with dark/photo
    /// backgrounds, e.g. Scan). When false, container is solid white (default light screens).
    var transparent: Bool = false

    var body: some View {
        HStack(spacing: -9.78) {
            ForEach(AppTab.allCases) { tab in
                tabItem(tab)
                    .zIndex(selection == tab ? 1 : 0)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(containerBackground)
        .padding(.horizontal, 16)
        .padding(.top, 15.64)
        .padding(.bottom, 23.46)
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let isActive = (selection == tab)

        VStack(spacing: isActive ? 4 : 1.96) {
            icon(tab, isActive: isActive)
            label(tab, isActive: isActive)
        }
        .padding(.vertical, isActive ? 11 : 7.82)
        .padding(.horizontal, isActive ? 14 : 7.82)
        .frame(maxWidth: .infinity)
        .background(activeBackground(isActive: isActive))
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            var txn = Transaction()
            txn.disablesAnimations = true
            withTransaction(txn) {
                selection = tab
            }
        }
    }

    @ViewBuilder
    private func icon(_ tab: AppTab, isActive: Bool) -> some View {
        let base = Image(tab.iconAssetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 20.83, height: 20.83)
        if isActive {
            base.foregroundStyle(AppColor.brandGradient)
        } else {
            base.foregroundStyle(inactiveTint)
        }
    }

    @ViewBuilder
    private func label(_ tab: AppTab, isActive: Bool) -> some View {
        let base = Text(tab.title)
            .font(isActive ? AppFont.tabLabelActive : AppFont.tabLabel)
            .tracking(12 * AppTracking.tabLabel)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        if isActive {
            base.foregroundStyle(AppColor.brandGradient)
        } else {
            base.foregroundStyle(inactiveTint)
        }
    }

    private var inactiveTint: Color {
        transparent ? Color.white : AppColor.textBlack
    }

    @ViewBuilder
    private var containerBackground: some View {
        if transparent {
            // iOS 26 Liquid Glass; thinner material fallback for older systems.
            if #available(iOS 26.0, *) {
                Capsule(style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(.clear, in: Capsule(style: .continuous))
                    .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 6)
            } else {
                // Pre-iOS 26 fallback. We deliberately avoid `.ultraThinMaterial`
                // here because this capsule sits over the live camera preview on
                // the Scan tab — material would re-blur on every frame.
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 6)
            }
        } else {
            Capsule(style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 6)
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
    }

    @ViewBuilder
    private func activeBackground(isActive: Bool) -> some View {
        if isActive {
            if transparent {
                // Opaque milky-white pill — explicit color (not .regularMaterial)
                // because Material auto-adapts to dark against camera preview.
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.4))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
            } else {
                Capsule(style: .continuous)
                    .fill(AppColor.tabPillActiveFill)
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
            }
        }
    }
}

#Preview("Tab bar over white") {
    @Previewable @State var selection: AppTab = .settings
    return ZStack(alignment: .bottom) {
        AppColor.surfaceBackground.ignoresSafeArea()
        CustomTabBar(selection: $selection)
    }
}

#Preview("Tab bar over image (sees glass)") {
    @Previewable @State var selection: AppTab = .settings
    return ZStack(alignment: .bottom) {
        LinearGradient(
            colors: [Color(hex: 0x3A3A3A), Color(hex: 0x6E6E6E)],
            startPoint: .top, endPoint: .bottom
        ).ignoresSafeArea()
        CustomTabBar(selection: $selection)
    }
}
