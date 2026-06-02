import SwiftUI
import Contacts

// Shared building blocks for the contact list screens (Duplicates / Incomplete /
// All) so avatars, selection radios and row text stay identical to Figma
// (nodes 2012:3978 / 2012:4274 / 2012:4832).

// Title / subtitle / avatar rules derived from the Figma rows:
//   • has name        → title = name,  subtitle = phone ?? "No number"
//   • no name + phone → title = phone, subtitle = "No name"  (red avatar)
//   • nothing         → title = "Unknown", subtitle = "No name" (red avatar)
struct ContactRowInfo {
    let title: String
    let subtitle: String
    let nameMissing: Bool

    init(_ c: CNContact) {
        let name = (c.givenName + " " + c.familyName).trimmingCharacters(in: .whitespaces)
        let display = !name.isEmpty ? name : (!c.organizationName.isEmpty ? c.organizationName : "")
        let phone = c.phoneNumbers.first?.value.stringValue
        nameMissing = display.isEmpty
        if !display.isEmpty {
            title = display
            subtitle = phone ?? "No number"
        } else if let phone {
            title = phone
            subtitle = "No name"
        } else {
            title = "Unknown"
            subtitle = "No name"
        }
    }

    // Localized title/subtitle: real names/phones pass through; the fallback
    // labels get translated. Resolved on the main actor (the view), since L() is.
    @MainActor var locTitle: String { Self.loc(title) }
    @MainActor var locSubtitle: String { Self.loc(subtitle) }
    @MainActor private static func loc(_ s: String) -> String {
        switch s {
        case "No number": return L("contacts.noNumber")
        case "No name":   return L("contacts.noName")
        case "Unknown":   return L("contacts.unknown")
        default:          return s
        }
    }
}

// 40×40 circle. Light-blue (#D0E1FB / #54647A) normally, red (#CF2C30 / #FFECEA)
// when the contact has no name. Shows the contact thumbnail when available.
struct ContactAvatar: View {
    let contact: CNContact
    let info: ContactRowInfo
    var size: CGFloat = 40

    private var letter: String {
        String(info.title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        Group {
            if contact.imageDataAvailable, let data = contact.thumbnailImageData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(info.nameMissing ? Color(hex: 0xCF2C30) : Color(hex: 0xD0E1FB))
                    Text(letter.isEmpty ? "?" : letter)
                        .font(.custom("Inter-SemiBold", size: size * 0.5))
                        .foregroundStyle(info.nameMissing ? Color(hex: 0xFFECEA) : Color(hex: 0x54647A))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// 24×24 selection circle. Unselected = white + #C3C6D7 1px stroke,
// selected = brand-blue fill + white check (Figma "Label → Input").
struct ContactSelectRadio: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? AppColor.brandPrimary : Color.white)
            Circle()
                .strokeBorder(isSelected ? AppColor.brandPrimary : Color(hex: 0xC3C6D7), lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
    }
}

// Bottom action button used by the detail screens (Merge / Delete / Edit).
// `style` picks the Figma fill + text colour. Icon is a template-rendered asset.
struct ContactActionButton: View {
    enum Style { case primary, destructive }
    let title: String
    let iconAsset: String
    var iconSize: CGSize = CGSize(width: 15, height: 15)
    let style: Style
    var enabled: Bool = true
    let action: () -> Void

    private var bg: Color {
        switch style {
        case .primary:     return AppColor.brandPrimary
        case .destructive: return Color(hex: 0xFFDAD6)
        }
    }
    private var fg: Color {
        switch style {
        case .primary:     return .white
        case .destructive: return Color(hex: 0xBA1A1A)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(iconAsset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize.width, height: iconSize.height)
                Text(title)
                    .font(.custom("Inter-SemiBold", size: 13))
                    .tracking(13 * 0.05)
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(bg))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }
}

// Centered two-line nav title (title + count subtitle) used by detail screens.
struct ContactsNavTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.custom("Inter-Bold", size: 18))
                .foregroundStyle(Color(hex: 0x131B2E))
            Text(subtitle)
                .font(.custom("Inter-Medium", size: 11))
                .foregroundStyle(Color(hex: 0x434655))
        }
    }
}

// Custom detail-screen top bar (Figma "Header - TopAppBar"): blue back chevron +
// centered title/subtitle + optional trailing action. Built custom (vs. the
// system toolbar) so the trailing "Select all" is plain text with NO glass pill
// background — iOS 26 auto-adds a Liquid Glass pill behind toolbar bar buttons.
struct ContactsDetailHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss

    init(title: String, subtitle: String,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            ContactsNavTitle(title: title, subtitle: subtitle)
            HStack(spacing: 0) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColor.brandPrimary)
                        .frame(width: 40, height: 40, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                trailing()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(
            AppColor.surfaceBackground
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(hex: 0xC3C6D7)).frame(height: 1)
                }
        )
    }
}

// "Select all" / "Select group" trailing text button (Figma blue link).
struct ContactsLinkButton: View {
    let title: String
    var size: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(size >= 13 ? "Inter-SemiBold" : "Inter-Medium", size: size))
                .tracking(size >= 13 ? size * 0.05 : 0)
                .foregroundStyle(AppColor.brandPrimary)
        }
        .buttonStyle(.plain)
    }
}
