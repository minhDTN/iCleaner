//
//  AppFont.swift
//  QRCode
//

import SwiftUI

enum AppFont {
    // Splash title — "QR & Barcode Scanner"
    static let displayLargeBold = Font.custom("Montserrat-Bold", size: 25)

    // Page title — e.g. "Setting"
    static let titleLarge = Font.custom("Inter-SemiBold", size: 18)

    // Section label (use with .textCase(.uppercase)) — e.g. "GENERAL", "ACTIONS"
    static let sectionLabel = Font.custom("Inter-SemiBold", size: 13)

    // Row label / list button — e.g. "Restore Purchases"
    static let bodyLarge = Font.custom("Inter-SemiBold", size: 17)

    // Settings row body — e.g. "Vibrate after scanning"
    static let rowText = Font.custom("Inter-Medium", size: 17)

    // Plain body — e.g. version value "1.3.4"
    static let bodySmall = Font.custom("Inter-Regular", size: 16)

    // Primary CTA button — e.g. "Upgrade Now"
    static let buttonPrimary = Font.custom("PublicSans-Bold", size: 16)

    // Tab bar
    static let tabLabel       = Font.system(size: 12, weight: .regular, design: .default)
    static let tabLabelActive = Font.system(size: 12, weight: .bold,    design: .default)
}

enum AppTracking {
    static let tight: CGFloat       = -0.025
    static let normal: CGFloat      = 0
    static let tabLabel: CGFloat    = 0.0049
}

extension Text {
    func appTitleLarge() -> some View {
        font(AppFont.titleLarge)
            .tracking(18 * AppTracking.tight)
            .foregroundStyle(AppColor.textPrimary)
    }

    func appSectionLabel() -> some View {
        font(AppFont.sectionLabel)
            .tracking(13 * AppTracking.tight)
            .textCase(.uppercase)
            .foregroundStyle(AppColor.textSecondary)
    }

    func appBodyLarge(color: Color = AppColor.linkPrimary) -> some View {
        font(AppFont.bodyLarge)
            .foregroundStyle(color)
    }

    func appButtonPrimary() -> some View {
        font(AppFont.buttonPrimary)
            .foregroundStyle(AppColor.textOnBrand)
    }
}
