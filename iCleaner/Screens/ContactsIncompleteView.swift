import SwiftUI
import Contacts
import ContactsUI
import LibEarnMoneyIOS

// Figma `2012:4274` (Incomplete Contacts). Header = back + centered title +
// "N contacts" subtitle + "Select all". Each contact is a white card (blue 1px
// stroke, radius 12): name (SemiBold 17) + a red warning-icon badge
// ("Missing contact name" / "Missing phone number", slate text) + checkbox.
// Bottom bar: "Edit contacts" (blue) + "Delete selected" (#FFDAD6 / #BA1A1A).
struct ContactsIncompleteView: View {
    @Bindable var service: ContactsService

    @State private var contacts: [CNContact] = []
    @State private var loading: Bool = true
    @State private var selection: Set<String> = []
    @State private var editingID: String?
    @State private var actionError: String?
    @State private var deleting: Bool = false

    private var isAllSelected: Bool { !contacts.isEmpty && selection.count == contacts.count }
    private var selectedContacts: [CNContact] {
        contacts.filter { selection.contains($0.identifier) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ContactsDetailHeader(title: L("contacts.inc.title"), subtitle: L("contacts.count", contacts.count)) {
                if !contacts.isEmpty {
                    ContactsLinkButton(title: isAllSelected ? L("contacts.deselectAll") : L("contacts.selectAll")) {
                        toggleSelectAll()
                    }
                }
            }
            ZStack(alignment: .bottom) {
                AppColor.surfaceBackground.ignoresSafeArea(edges: .bottom)

                if loading {
                    ProgressView().tint(AppColor.brandPrimary)
                } else if contacts.isEmpty {
                    emptyView
                } else {
                    list
                    actionBar
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            contacts = await service.fetchIncompleteContacts()
            loading = false
        }
        .sheet(item: Binding(
            get: { editingID.flatMap { id in contacts.first(where: { $0.identifier == id }) }.map { ContactBox(contact: $0) } },
            set: { editingID = $0?.contact.identifier }
        )) { box in
            ContactEditor(contact: box.contact) { updated in
                editingID = nil
                if let updated, let idx = contacts.firstIndex(where: { $0.identifier == updated.identifier }) {
                    contacts[idx] = updated
                }
                Task { await service.refresh() }
            }
        }
        .alert(L("flow.deleteErrorTitle"), isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(contacts, id: \.identifier) { contact in
                    row(contact)
                }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 110)  // room for the action bar
        }
    }

    private func row(_ contact: CNContact) -> some View {
        let selected = selection.contains(contact.identifier)
        let hasName = !ContactsService.isNameMissing(contact)
        let title = hasName ? ContactsService.displayName(for: contact) : L("contacts.noName")
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Inter-SemiBold", size: 17))
                    .foregroundStyle(Color(hex: 0x131B2E))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image("Contacts/ic_warning")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Color(hex: 0xBA1A1A))
                    Text(missingText(for: contact))
                        .font(.custom("Inter-Regular", size: 15))
                        .foregroundStyle(Color(hex: 0x505F76))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ContactSelectRadio(isSelected: selected)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.brandPrimary, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { toggle(contact) }
    }

    private func missingText(for contact: CNContact) -> String {
        let nameMissing = ContactsService.isNameMissing(contact)
        let phoneMissing = contact.phoneNumbers.isEmpty
        if nameMissing && phoneMissing { return L("contacts.inc.missingBoth") }
        if nameMissing { return L("contacts.inc.missingName") }
        return L("contacts.inc.missingPhone")
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.success)
            Text(L("contacts.inc.emptyTitle"))
                .font(.custom("Inter-Bold", size: 20))
                .foregroundStyle(AppColor.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            ContactActionButton(title: L("contacts.inc.edit"), iconAsset: "Contacts/ic_edit",
                                 iconSize: CGSize(width: 17, height: 17),
                                 style: .primary, enabled: !selection.isEmpty && !deleting) {
                editingID = selectedContacts.first?.identifier
            }
            ContactActionButton(title: L("contacts.deleteSelected"), iconAsset: "Contacts/ic_trash",
                                 iconSize: CGSize(width: 14, height: 15),
                                 style: .destructive, enabled: !selection.isEmpty && !deleting) {
                Task { await performDelete() }
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

    // MARK: - Actions

    private func toggle(_ contact: CNContact) {
        if selection.contains(contact.identifier) { selection.remove(contact.identifier) }
        else { selection.insert(contact.identifier) }
    }

    private func toggleSelectAll() {
        if isAllSelected { selection.removeAll() }
        else { selection = Set(contacts.map(\.identifier)) }
    }

    private func performDelete() async {
        deleting = true
        defer { deleting = false }
        do {
            try await service.delete(contacts: selectedContacts)
            contacts.removeAll { selection.contains($0.identifier) }
            selection.removeAll()
            if !PremiumGate.isPremium, let vc = AdHelpers.topViewController() {
                AdManager.shared.showInterstitialAd(
                    adUnitID: AdUnits.interGlobal,
                    from: vc,
                    completion: nil
                )
            }
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }
}

// MARK: - Helpers

extension ContactsService {
    nonisolated static func displayName(for contact: CNContact) -> String {
        let full = (contact.givenName + " " + contact.familyName).trimmingCharacters(in: .whitespaces)
        if !full.isEmpty { return full }
        if !contact.organizationName.isEmpty { return contact.organizationName }
        if let firstPhone = contact.phoneNumbers.first?.value.stringValue { return firstPhone }
        return "Unnamed contact"
    }

    nonisolated static func isNameMissing(_ contact: CNContact) -> Bool {
        (contact.givenName + contact.familyName).trimmingCharacters(in: .whitespaces).isEmpty
        && contact.organizationName.isEmpty
    }
}

// CNContact isn't Hashable/Identifiable conformant for SwiftUI .sheet(item:);
// box it so the binding works.
private struct ContactBox: Identifiable {
    let contact: CNContact
    var id: String { contact.identifier }
}

// MARK: - System contact editor bridge

private struct ContactEditor: UIViewControllerRepresentable {
    let contact: CNContact
    var onFinish: (CNContact?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CNContactViewController(for: contact)
        vc.allowsEditing = true
        vc.delegate = context.coordinator
        let nav = UINavigationController(rootViewController: vc)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        var onFinish: (CNContact?) -> Void
        init(onFinish: @escaping (CNContact?) -> Void) { self.onFinish = onFinish }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onFinish(contact)
        }
    }
}
