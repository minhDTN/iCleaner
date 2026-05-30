import SwiftUI
import Contacts
import LibEarnMoneyIOS

// Figma `2012:3978` (Duplicate Contacts). List of groups, each row shows the
// canonical name + N contacts + the distinct phone numbers found across the
// group. Per-row Merge action union-merges (phones/emails) + deletes extras.
// Per-row delete keeps the first contact + deletes the rest (no merge).
struct ContactsDuplicatesView: View {
    @Bindable var service: ContactsService

    @State private var groups: [DuplicateGroup] = []
    @State private var loading: Bool = true
    @State private var actionError: String?
    @State private var actionInProgress: UUID?

    var body: some View {
        Group {
            if loading {
                loadingView
            } else if groups.isEmpty {
                emptyView
            } else {
                groupList
            }
        }
        .background(AppColor.surfaceBackground)
        .navigationTitle("Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            groups = await service.fetchDuplicateGroups()
            loading = false
        }
        .alert("Couldn't merge", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(AppColor.brandPrimary).scaleEffect(1.2)
            Text("Scanning for duplicates…")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.success)
            Text("No duplicates found")
                .font(.custom("Inter-Bold", size: 20))
                .foregroundStyle(AppColor.textPrimary)
            Text("Your contacts look clean.")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupList: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryHeader
                ForEach(groups) { group in
                    DuplicateGroupCard(
                        group: group,
                        busy: actionInProgress == group.id,
                        onMerge: { Task { await performMerge(group) } },
                        onDelete: { Task { await performDeleteExtras(group) } }
                    )
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private var summaryHeader: some View {
        let total = groups.reduce(0) { $0 + $1.contacts.count }
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(groups.count) duplicate \(groups.count == 1 ? "group" : "groups")")
                    .font(.custom("Inter-Bold", size: 18))
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(total) contacts can be cleaned up")
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func performMerge(_ group: DuplicateGroup) async {
        actionInProgress = group.id
        defer { actionInProgress = nil }
        do {
            try await service.merge(group: group)
            groups.removeAll { $0.id == group.id }
            fireActionInterstitial()
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    private func performDeleteExtras(_ group: DuplicateGroup) async {
        actionInProgress = group.id
        defer { actionInProgress = nil }
        do {
            // Keep first contact, delete the rest.
            try await service.delete(contacts: Array(group.contacts.dropFirst()))
            groups.removeAll { $0.id == group.id }
            fireActionInterstitial()
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    private func fireActionInterstitial() {
        guard !PremiumGate.isPremium,
              let vc = AdHelpers.topViewController() else { return }
        AdManager.shared.showInterstitialAd(
            adUnitID: AdUnits.interContactsAction,
            from: vc,
            completion: nil
        )
    }
}

private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let busy: Bool
    var onMerge: () -> Void
    var onDelete: () -> Void

    private var phoneList: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for c in group.contacts {
            for ph in c.phoneNumbers {
                let formatted = ph.value.stringValue
                if !seen.contains(formatted) {
                    seen.insert(formatted)
                    out.append(formatted)
                }
                if out.count >= 4 { break }
            }
            if out.count >= 4 { break }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.crop.square.stack.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColor.danger)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(hex: 0xFFDAD6).opacity(0.5)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.custom("Inter-SemiBold", size: 16))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text("\(group.contacts.count) contacts")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
            }

            if !phoneList.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(phoneList, id: \.self) { phone in
                        Text(phone)
                            .font(.custom("Inter-Regular", size: 13))
                            .foregroundStyle(Color(hex: 0x475569))
                    }
                }
                .padding(.leading, 56)
            }

            HStack(spacing: 12) {
                Button(action: onMerge) {
                    HStack(spacing: 6) {
                        if busy { ProgressView().scaleEffect(0.7).tint(.white) }
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge")
                    }
                    .font(.custom("Inter-SemiBold", size: 14))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppColor.brandPrimary)
                    )
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Button(action: onDelete) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete extras")
                    }
                    .font(.custom("Inter-SemiBold", size: 14))
                    .foregroundStyle(AppColor.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColor.danger.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xE2E8F0), lineWidth: 1)
        )
    }
}
