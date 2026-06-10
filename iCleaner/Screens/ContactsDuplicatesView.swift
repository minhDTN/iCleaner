import SwiftUI
import Contacts
import LibEarnMoneyIOS

// Figma `2012:3978` (Duplicate Contacts). Header = back + centered title +
// "N contacts" subtitle + "Select all". Each duplicate cluster is a white card
// (blue 1px stroke, radius 20) headed "N duplicate contacts" + "Select group",
// listing each contact as avatar + name + phone/"No name"/"No number" + radio.
// Bottom bar: "Merge contacts" (blue) + "Delete selected" (#FFDAD6 / #BA1A1A).
struct ContactsDuplicatesView: View {
    @Bindable var service: ContactsService

    @State private var groups: [DuplicateGroup] = []
    @State private var loading: Bool = true
    @State private var selection: Set<String> = []
    @State private var busy: Bool = false
    @State private var actionError: String?
    @State private var mergeResult: String?
    @State private var showPaywall: Bool = false

    private var allIDs: [String] { groups.flatMap { $0.contacts.map(\.identifier) } }
    private var totalContacts: Int { allIDs.count }
    private var isAllSelected: Bool { !allIDs.isEmpty && selection.count == allIDs.count }
    private var canMerge: Bool {
        groups.contains { g in g.contacts.filter { selection.contains($0.identifier) }.count >= 2 }
    }
    private var selectedContacts: [CNContact] {
        groups.flatMap { $0.contacts }.filter { selection.contains($0.identifier) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ContactsDetailHeader(title: L("contacts.dup.title"), subtitle: L("contacts.count", totalContacts)) {
                if !groups.isEmpty {
                    ContactsLinkButton(title: isAllSelected ? L("contacts.deselectAll") : L("contacts.selectAll")) {
                        toggleSelectAll()
                    }
                }
            }
            ZStack(alignment: .bottom) {
                AppColor.surfaceBackground.ignoresSafeArea(edges: .bottom)

                if loading {
                    loadingView
                } else if groups.isEmpty {
                    emptyView
                } else {
                    groupList
                    actionBar
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .task {
            FlowGate.showStartAd()   // ad on feature entry (free users)
            groups = await service.fetchDuplicateGroups()
            loading = false
        }
        .alert(L("contacts.somethingWrong"), isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .alert(L("contacts.merged.title"), isPresented: Binding(
            get: { mergeResult != nil },
            set: { if !$0 { mergeResult = nil } }
        )) {
            Button("OK", role: .cancel) { mergeResult = nil }
        } message: { Text(mergeResult ?? "") }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(AppColor.brandPrimary).scaleEffect(1.2)
            Text(L("contacts.dup.scanning"))
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
            Text(L("contacts.dup.emptyTitle"))
                .font(.custom("Inter-Bold", size: 20))
                .foregroundStyle(AppColor.textPrimary)
            Text(L("contacts.dup.emptyBody"))
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupList: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(groups) { group in
                    groupCard(group)
                }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 110)  // room for the action bar
        }
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("contacts.dup.groupCount", group.contacts.count))
                    .font(.custom("Inter-SemiBold", size: 13))
                    .tracking(13 * 0.05)
                    .foregroundStyle(Color(hex: 0x131B2E))
                Spacer()
                ContactsLinkButton(title: L("contacts.selectGroup"), size: 11) { toggleGroup(group) }
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(hex: 0xC3C6D7)).frame(height: 1)
            }

            VStack(spacing: 8) {
                ForEach(group.contacts, id: \.identifier) { contact in
                    contactRow(contact)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColor.surfaceBackground)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColor.brandPrimary, lineWidth: 1)
        )
    }

    private func contactRow(_ contact: CNContact) -> some View {
        let info = ContactRowInfo(contact)
        let selected = selection.contains(contact.identifier)
        return HStack(spacing: 16) {
            ContactAvatar(contact: contact, info: info)
            VStack(alignment: .leading, spacing: 0) {
                Text(info.locTitle)
                    .font(.custom("Inter-Regular", size: 17))
                    .foregroundStyle(Color(hex: 0x131B2E))
                    .lineLimit(1)
                Text(info.locSubtitle)
                    .font(.custom("Inter-Regular", size: 15))
                    .foregroundStyle(Color(hex: 0x434655))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ContactSelectRadio(isSelected: selected)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { toggle(contact) }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            ContactActionButton(title: L("contacts.dup.merge"), iconAsset: "Contacts/ic_merge",
                                 iconSize: CGSize(width: 12, height: 15),
                                 style: .primary, enabled: canMerge && !busy) {
                Task { await performMergeSelected() }
            }
            ContactActionButton(title: L("contacts.deleteSelected"), iconAsset: "Contacts/ic_trash",
                                 iconSize: CGSize(width: 14, height: 15),
                                 style: .destructive, enabled: !selection.isEmpty && !busy) {
                Task { await performDeleteSelected() }
            }
        }
        .padding(16)
        .background(
            AppColor.surfaceBackground
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(hex: 0xC3C6D7)).frame(height: 1)
                }
        )
    }

    // MARK: - Selection

    private func toggle(_ contact: CNContact) {
        if selection.contains(contact.identifier) { selection.remove(contact.identifier) }
        else { selection.insert(contact.identifier) }
    }

    private func toggleGroup(_ group: DuplicateGroup) {
        let ids = group.contacts.map(\.identifier)
        if ids.allSatisfy({ selection.contains($0) }) {
            ids.forEach { selection.remove($0) }
        } else {
            ids.forEach { selection.insert($0) }
        }
    }

    private func toggleSelectAll() {
        if isAllSelected { selection.removeAll() }
        else { selection = Set(allIDs) }
    }

    // MARK: - Actions

    private func performMergeSelected() async {
        if FlowGate.requiresPaywall { showPaywall = true; return }   // final step → paywall for free
        busy = true
        defer { busy = false }
        do {
            var names: [String] = []
            for group in groups {
                let sel = group.contacts.filter { selection.contains($0.identifier) }
                if sel.count >= 2 {
                    let name = try await service.mergeContacts(sel)
                    if !name.isEmpty { names.append(name) }
                }
            }
            selection.removeAll()
            groups = await service.fetchDuplicateGroups()
            // Tell the user what name the merged contact(s) ended up with.
            if names.count == 1 {
                mergeResult = L("contacts.merged.one", names[0])
            } else if names.count > 1 {
                mergeResult = L("contacts.merged.many", names.joined(separator: ", "))
            }
            fireActionInterstitial()
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    private func performDeleteSelected() async {
        if FlowGate.requiresPaywall { showPaywall = true; return }   // final step → paywall for free
        busy = true
        defer { busy = false }
        do {
            try await service.delete(contacts: selectedContacts)
            selection.removeAll()
            groups = await service.fetchDuplicateGroups()
            fireActionInterstitial()
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    private func fireActionInterstitial() {
        FlowGate.showInterstitial()   // only if cached — never block on a loading spinner
    }
}
