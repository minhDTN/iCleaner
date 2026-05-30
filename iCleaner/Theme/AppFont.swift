import SwiftUI

// Inter is the design system font (every Figma text node uses it).
// Tracking values from Figma are percent-of-font-size — apply as `tracking(size * pct)`.
// `Inter-Black` weight is referenced for the paywall headline but is not bundled yet;
// callers should fall back to `displayBold` until Inter-Black.ttf is added.
enum AppFont {
    // Display / hero numbers (e.g. "320 MB Total Cleaned" stat tile)
    static let displayLarge   = Font.custom("Inter-Bold", size: 28)

    // Screen titles (e.g. "Similar / 15 Photos / 48MB")
    static let titleLarge     = Font.custom("Inter-Bold", size: 20)
    static let titleMedium    = Font.custom("Inter-Bold", size: 18)

    // Section / card headers (e.g. "Similar", "Cleaner Pro")
    static let headlineLarge  = Font.custom("Inter-SemiBold", size: 20)
    static let headline       = Font.custom("Inter-SemiBold", size: 16)
    static let headlineSmall  = Font.custom("Inter-SemiBold", size: 14)

    // Body / list rows
    static let bodyLarge      = Font.custom("Inter-Regular", size: 16)
    static let body           = Font.custom("Inter-Regular", size: 14)
    static let bodyMedium     = Font.custom("Inter-Medium", size: 14)

    // Buttons
    static let buttonLarge    = Font.custom("Inter-SemiBold", size: 16)
    static let buttonMedium   = Font.custom("Inter-Medium", size: 14)

    // Captions / meta
    static let caption        = Font.custom("Inter-Regular", size: 12)
    static let captionMedium  = Font.custom("Inter-Medium", size: 12)
    static let captionBold    = Font.custom("Inter-Bold", size: 12)

    // Tab bar (Inter Medium 10/15)
    static let tabLabel       = Font.custom("Inter-Medium", size: 10)

    // ALL-CAPS overlay tags ("BEST MATCH", 5% tracking)
    static let overlineBold   = Font.custom("Inter-Bold", size: 10)
}

enum AppTracking {
    static let tight: CGFloat   = -0.025
    static let normal: CGFloat  = 0
    static let caps: CGFloat    = 0.05  // ALL-CAPS overlays in Figma
}

extension Text {
    func appTitleLarge() -> some View {
        font(AppFont.titleLarge)
            .tracking(20 * AppTracking.tight)
            .foregroundStyle(AppColor.textPrimary)
    }

    func appHeadline() -> some View {
        font(AppFont.headline)
            .tracking(16 * AppTracking.tight)
            .foregroundStyle(AppColor.textPrimary)
    }

    func appBody(color: Color = AppColor.textBody) -> some View {
        font(AppFont.body)
            .foregroundStyle(color)
    }

    func appCaption(color: Color = AppColor.textSecondary) -> some View {
        font(AppFont.caption)
            .foregroundStyle(color)
    }

    func appButtonPrimary() -> some View {
        font(AppFont.buttonLarge)
            .foregroundStyle(AppColor.textOnBrand)
    }

    func appOverlineCaps(color: Color = AppColor.textOnBrand) -> some View {
        font(AppFont.overlineBold)
            .tracking(10 * AppTracking.caps)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
