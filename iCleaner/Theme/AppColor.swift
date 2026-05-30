//
//  AppColor.swift
//  QRCode
//

import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum AppColor {
    // Brand — gradient blue 600 → purple 600 at 135°.
    // `brandPrimary` is the gradient start (solid use where gradients aren't supported);
    // `brandGradient` is the canonical brand fill for active states / CTAs.
    static let brandPrimary = Color(hex: 0x155DFC)
    static let brandPurple  = Color(hex: 0x9810FA)
    static let brandAccent  = Color(hex: 0x10A2F7)
    static let linkPrimary  = Color(hex: 0x135BEC)

    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0x155DFC), Color(hex: 0x9810FA)],
        startPoint: .top,
        endPoint: .bottom
    )

    // Text
    static let textPrimary   = Color(hex: 0x0F172A)  // Slate-900 — page title
    static let textBody      = Color(hex: 0x1E293B)  // Slate-800 — list row body
    static let textSecondary = Color(hex: 0x64748B)  // Slate-500 — section labels
    static let textMuted     = Color(hex: 0x94A3B8)  // Slate-400 — version value
    static let chevron       = Color(hex: 0xCBD5E1)  // Slate-300 — chevron right
    static let textOnBrand   = Color(hex: 0xFFFFFF)
    static let textBlack     = Color(hex: 0x000000)

    // Surface
    static let surfaceBackground = Color(hex: 0xFFFFFF)
    static let surfaceCard       = Color(hex: 0xF8FAFC)
    static let surfaceMuted      = Color(hex: 0xF7F5F8)
    static let surfaceDark       = Color(hex: 0x444444)

    // Border
    static let borderLight  = Color(hex: 0xE2E8F0)
    static let borderSubtle = Color(hex: 0xF1F5F9)
    static let borderGray   = Color(hex: 0xEEEEEE)

    // Status
    static let success = Color(hex: 0x4BC539)

    // Tinted backgrounds
    static let brandTintedBg = Color(hex: 0x155DFC, alpha: 0.1)

    // Glass / overlay
    static let glassFill    = Color(hex: 0xFFFFFF, alpha: 0.2)
    static let glassBorder  = Color(hex: 0xFFFFFF, alpha: 0.1)
    static let glassSurface = Color(hex: 0xFFFFFF, alpha: 0.5)
    static let overlayDim   = Color(hex: 0x000000, alpha: 0.5)

    // Tab pill active state (non-Scan tabs) — subtle gray pill on white container, no stroke.
    static let tabPillActiveFill   = Color(hex: 0xE5E7EB)
    static let tabPillActiveStroke = Color.clear
}
