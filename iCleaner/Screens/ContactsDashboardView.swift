import SwiftUI

// Figma `2012:3559` (Contacts dashboard). White bg. Left-aligned title "Contacts"
// (Inter SemiBold 20 #111827) in the top bar — NO total counter, NO reload button.
// Just 4 stacked cards (gap 16, padding 20):
//   • Duplicates   — pastel red bucket, red count
//   • Incomplete   — pastel indigo bucket, slate count
//   • Backup       — light indigo bucket, brand-blue count
//   • All contacts — light blue bucket, dark count
// Each card: 48×48 icon-bucket (circle) + title (SemiBold 20 #131B2E) +
// count line (SemiBold 13, 5% tracking, colour per card) + static description
// (Regular 15 #434655) + chevron-right (#C3C6D7). Card chrome: white bg +
// brand-blue 1px stroke + radius 16.
struct ContactsDashboardView: View {
    @Bindable var service: ContactsService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("tab.contacts"))
                    .font(.custom("Inter-SemiBold", size: 20))
                    .foregroundStyle(Color(hex: 0x111827))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                ForEach(ContactsCategory.allCases) { cat in
                    NavigationLink(value: cat) {
                        DashboardCard(category: cat, count: count(for: cat))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(AppColor.surfaceBackground)
        .bottomChromeInset()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: ContactsCategory.self) { cat in
            switch cat {
            case .duplicates: ContactsDuplicatesView(service: service)
            case .incomplete: ContactsIncompleteView(service: service)
            case .all:        ContactsAllView(service: service)
            case .backups:    ContactsBackupsView(service: service)
            }
        }
        .task {
            if service.lastRefreshed == nil { await service.refresh() }
        }
    }

    private func count(for cat: ContactsCategory) -> Int {
        switch cat {
        case .duplicates: return service.duplicateGroupCount
        case .incomplete: return service.incompleteCount
        case .backups:    return service.backupCount
        case .all:        return service.totalCount
        }
    }
}

// MARK: - Category model

enum ContactsCategory: String, Identifiable, CaseIterable, Hashable {
    case duplicates, incomplete, backups, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicates: return "Duplicates"
        case .incomplete: return "Incomplete contacts"
        case .backups:    return "Backup"
        case .all:        return "All contacts"
        }
    }

    // Template-rendered SVGs downloaded from Figma (node 2012:3559 buckets).
    var iconAsset: String {
        switch self {
        case .duplicates: return "Contacts/ic_duplicates"
        case .incomplete: return "Contacts/ic_incomplete"
        case .backups:    return "Contacts/ic_backup"
        case .all:        return "Contacts/ic_all"
        }
    }

    var iconSize: CGSize {
        switch self {
        case .duplicates: return CGSize(width: 18, height: 21)
        case .incomplete: return CGSize(width: 19, height: 19)
        case .backups:    return CGSize(width: 21, height: 15)
        case .all:        return CGSize(width: 21, height: 15)
        }
    }

    var bucketTint: Color {
        switch self {
        case .duplicates: return Color(hex: 0xFFDAD6, alpha: 0.5)  // pastel red
        case .incomplete: return Color(hex: 0xDAE2FD, alpha: 0.5)  // pastel indigo
        case .backups:    return Color(hex: 0xDBE1FF)              // light indigo
        case .all:        return Color(hex: 0xD3E4FE)              // light blue
        }
    }

    var iconTint: Color {
        switch self {
        case .duplicates: return Color(hex: 0xBA1A1A)
        case .incomplete: return Color(hex: 0x434655)
        case .backups:    return Color(hex: 0x0D7FF2)
        case .all:        return Color(hex: 0x505F76)
        }
    }

    // Colour of the dynamic count line (matches Figma per card).
    var countTint: Color {
        switch self {
        case .duplicates: return Color(hex: 0xBA1A1A)
        case .incomplete: return Color(hex: 0x505F76)
        case .backups:    return Color(hex: 0x0D7FF2)
        case .all:        return Color(hex: 0x131B2E)
        }
    }

    func countLine(_ count: Int) -> String {
        switch self {
        case .duplicates: return "\(count) duplicate \(count == 1 ? "group" : "groups")"
        case .incomplete: return "\(count) contact\(count == 1 ? "" : "s") to check"
        case .backups:    return "\(count) backup\(count == 1 ? "" : "s")"
        case .all:        return "\(count) contacts"
        }
    }

    // Static description (the dynamic number lives in `countLine`).
    var descriptionLine: String {
        switch self {
        case .duplicates: return "Merge or delete duplicate…"
        case .incomplete: return "Contacts missing name, phone…"
        case .backups:    return "Save and restore contacts when…"
        case .all:        return "View all contacts on device."
        }
    }

    // Localization keys (resolved in the view so they follow the in-app language).
    var titleKey: String {
        switch self {
        case .duplicates: return "contacts.card.duplicates"; case .incomplete: return "contacts.card.incomplete"
        case .backups: return "contacts.card.backup"; case .all: return "contacts.card.all"
        }
    }
    var descKey: String {
        switch self {
        case .duplicates: return "contacts.desc.duplicates"; case .incomplete: return "contacts.desc.incomplete"
        case .backups: return "contacts.desc.backup"; case .all: return "contacts.desc.all"
        }
    }
    var countKey: String {
        switch self {
        case .duplicates: return "contacts.count.duplicates"; case .incomplete: return "contacts.count.incomplete"
        case .backups: return "contacts.count.backups"; case .all: return "contacts.count"
        }
    }
}

// MARK: - Card

private struct DashboardCard: View {
    let category: ContactsCategory
    let count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(category.iconAsset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: category.iconSize.width, height: category.iconSize.height)
                .foregroundStyle(category.iconTint)
                .frame(width: 48, height: 48)
                .background(Circle().fill(category.bucketTint))

            VStack(alignment: .leading, spacing: 4) {
                Text(L(category.titleKey))
                    .font(.custom("Inter-SemiBold", size: 20))
                    .foregroundStyle(Color(hex: 0x131B2E))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L(category.countKey, count))
                        .font(.custom("Inter-SemiBold", size: 13))
                        .tracking(13 * 0.05)
                        .foregroundStyle(category.countTint)
                    Text(L(category.descKey))
                        .font(.custom("Inter-Regular", size: 15))
                        .foregroundStyle(Color(hex: 0x434655))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0xC3C6D7))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColor.brandPrimary, lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        ContactsDashboardView(service: ContactsService())
    }
}
