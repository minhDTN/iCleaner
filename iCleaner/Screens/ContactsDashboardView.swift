import SwiftUI

// Figma `2012:3559` (Contacts dashboard). White bg. Header "362 contacts"
// total. 4 stacked cards (gap 16, padding 20):
//   • Duplicates  — pastel red bucket bg
//   • Incomplete  — pastel indigo bucket bg
//   • Backup      — light indigo bucket bg
//   • All contacts — light blue bucket bg
// Each card: 48×48 icon-bucket (capsule) + title + subtitle + chevron-right
// (#C3C6D7). Card chrome: white bg + brand-blue 1px stroke + radius 16.
struct ContactsDashboardView: View {
    @Bindable var service: ContactsService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(ContactsCategory.allCases) { cat in
                    NavigationLink(value: cat) {
                        DashboardCard(category: cat, count: count(for: cat))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(AppColor.surfaceBackground)
        .navigationTitle("Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await service.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(AppColor.brandPrimary)
                }
                .disabled(service.isRefreshing)
            }
        }
        .navigationDestination(for: ContactsCategory.self) { cat in
            // Placeholder until Phase 7 Part B builds Duplicates / Incomplete /
            // All / Backups screens. The dashboard cards already route to the
            // right enum case so wiring stays trivial later.
            PlaceholderScreen(
                title: cat.title,
                subtitle: "\(cat.title) detail screen — coming in Phase 7 Part B"
            )
            .navigationTitle(cat.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if service.lastRefreshed == nil { await service.refresh() }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 24))
                .foregroundStyle(AppColor.brandPrimary)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColor.brandPrimary.opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 4) {
                if service.isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Scanning contacts…")
                            .font(.custom("Inter-Regular", size: 14))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                } else {
                    Text("\(service.totalCount) contacts")
                        .font(.custom("Inter-Bold", size: 20))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Last scanned " + (service.lastRefreshed.map(formatRelative) ?? "—"))
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func count(for cat: ContactsCategory) -> Int {
        switch cat {
        case .duplicates: return service.duplicateGroupCount
        case .incomplete: return service.incompleteCount
        case .backups:    return service.backupCount
        case .all:        return service.totalCount
        }
    }

    private func formatRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
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

    var systemIcon: String {
        switch self {
        case .duplicates: return "person.2.crop.square.stack.fill"
        case .incomplete: return "person.crop.circle.badge.questionmark"
        case .backups:    return "externaldrive.fill"
        case .all:        return "person.crop.rectangle.stack.fill"
        }
    }

    var bucketTint: Color {
        switch self {
        case .duplicates: return Color(hex: 0xFFDAD6).opacity(0.5)  // pastel red
        case .incomplete: return Color(hex: 0xDAE2FD).opacity(0.5)  // pastel indigo
        case .backups:    return Color(hex: 0xDBE1FF)               // light indigo
        case .all:        return Color(hex: 0xD3E4FE)               // light blue
        }
    }

    var iconTint: Color {
        switch self {
        case .duplicates: return Color(hex: 0xEF4444)
        case .incomplete: return Color(hex: 0x4361EE)
        case .backups:    return Color(hex: 0x4361EE)
        case .all:        return AppColor.brandPrimary
        }
    }

    func subtitle(count: Int) -> String {
        switch self {
        case .duplicates:
            return count == 0 ? "No duplicates found"
                              : "\(count) duplicate \(count == 1 ? "group" : "groups") — Merge or delete duplicates"
        case .incomplete:
            return count == 0 ? "All contacts look complete"
                              : "\(count) contact\(count == 1 ? "" : "s") to check — Missing name, phone or both"
        case .backups:
            return count == 0 ? "No backups yet"
                              : "\(count) backup\(count == 1 ? "" : "s") — Save and restore contacts when you need to"
        case .all:
            return count == 0 ? "No contacts on device"
                              : "View all \(count) contacts on device"
        }
    }
}

// MARK: - Card

private struct DashboardCard: View {
    let category: ContactsCategory
    let count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: category.systemIcon)
                .font(.system(size: 20))
                .foregroundStyle(category.iconTint)
                .frame(width: 48, height: 48)
                .background(Circle().fill(category.bucketTint))

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.custom("Inter-SemiBold", size: 16))
                    .foregroundStyle(AppColor.textPrimary)
                Text(category.subtitle(count: count))
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
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
