import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// All tokens hex-pulled from Figma file `yVC01XIRPo28KmyMUXV5Et` (Cleaner-IOS).
// Hardcode RGB so dark mode can't override the design (see playbook §7).
enum AppColor {
    // Brand
    static let brandPrimary  = Color(hex: 0x0D7FF2)  // CTA, active tab, links
    static let brandSoft     = Color(hex: 0x0D7FF2, alpha: 0.10)
    static let brandSubtle   = Color(hex: 0x0D7FF2, alpha: 0.20)
    static let brandMid      = Color(hex: 0x0D7FF2, alpha: 0.40)
    static let brandDeep     = Color(hex: 0x004AC6)  // gradient end / paywall accent

    // Status
    static let success       = Color(hex: 0x10B981)  // success badges / cleaned indicator
    static let warning       = Color(hex: 0xFFB04C)  // storage warning, premium-required
    static let danger        = Color(hex: 0xEF4444)  // delete buttons / destructive
    static let dangerSoft    = Color(hex: 0xFEF2F2)  // destructive tinted bg
    static let premiumGold   = Color(hex: 0xECBA16)  // "Premium" pill on paywall card

    // Text
    static let textPrimary   = Color(hex: 0x0F172A)  // titles
    static let textBody      = Color(hex: 0x1E293B)  // body
    static let textStrong    = Color(hex: 0x334155)
    static let textSecondary = Color(hex: 0x64748B)  // captions, secondary
    static let textMuted     = Color(hex: 0x94A3B8)  // disabled, placeholder
    static let chevron       = Color(hex: 0xCBD5E1)
    static let textOnBrand   = Color(hex: 0xFFFFFF)
    static let textBlack     = Color(hex: 0x000000)

    // Surfaces
    static let surfaceBackground = Color(hex: 0xFFFFFF)
    static let surfaceCard       = Color(hex: 0xF8FAFC)
    static let surfaceMuted      = Color(hex: 0xF1F5F9)

    // Tinted card backgrounds (category icon tiles on home, paywall source pills)
    static let tintBlueSoft    = Color(hex: 0xDBEAFE)
    static let tintBlueLighter = Color(hex: 0xE4F1FF)
    static let tintIndigoSoft  = Color(hex: 0xDAE2FD)
    static let tintLavender    = Color(hex: 0xEDEDF9)
    static let tintGreenSoft   = Color(hex: 0xE6F3EC)
    static let tintRedSoft     = Color(hex: 0xFFECEA)
    static let tintYellowSoft  = Color(hex: 0xFDF7CD)

    // Borders
    static let borderLight   = Color(hex: 0xE2E8F0)
    static let borderSubtle  = Color(hex: 0xF1F5F9)
    static let borderNeutral = Color(hex: 0xCBD5E1)

    // Glass / overlays
    static let glassFill20   = Color(hex: 0xFFFFFF, alpha: 0.20)
    static let glassFill60   = Color(hex: 0xFFFFFF, alpha: 0.60)
    static let glassFill90   = Color(hex: 0xFFFFFF, alpha: 0.90)
    static let overlayDimLight  = Color(hex: 0x000000, alpha: 0.30)  // modal dim
    static let overlayDimStrong = Color(hex: 0x000000, alpha: 0.50)  // photo viewer dim

    // Tab bar
    static let tabInactive = Color(hex: 0x9E9E9E)
    static let tabActive   = brandPrimary
}
