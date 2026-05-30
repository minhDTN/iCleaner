import SwiftUI
import Contacts
import ContactsUI
import LibEarnMoneyIOS

// Figma `2012:4274` (Incomplete Contacts). List with per-row badges
// ("Missing contact name" / "Missing phone number"). Tap → CNContactViewController
// (system editor) so user can fix in place. Multi-select + Delete selected.
struct ContactsIncompleteView: View {
    @Bindable var service: ContactsService

    @State private var contacts: [CNContact] = []
    @State private var loading: Bool = true
    @State private var selection: Set<String> = []
    @State private var editingID: String?
    @State private var actionError: String?
    @State private var deleting: Bool = false

    private var selectedContacts: [CNContact] {
        contacts.filter { selection.contains($0.identifier) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surfaceBackground.ignoresSafeArea()

            if loading {
                ProgressView().tint(AppColor.brandPrimary)
            } else if contacts.isEmpty {
                emptyView
            } else {
                List {
                    Section {
                        ForEach(contacts, id: \.identifier) { contact in
                            row(contact)
                                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
                .padding(.bottom, selection.isEmpty ? 0 : 88)
            }

            if !selection.isEmpty {
                deleteBar
            }
        }
        .navigationTitle("Incomplete")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleSelectAll) {
                    Text(selection.count == contacts.count ? "Deselect" : "Select all")
                        .font(.custom("Inter-SemiBold", size: 14))
                        .foregroundStyle(AppColor.brandPrimary)
                }
                .disabled(contacts.isEmpty)
            }
        }
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
        .alert("Couldn't delete", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private func row(_ contact: CNContact) -> some View {
        let isSelected = selection.contains(contact.identifier)
        let name = ContactsService.displayName(for: contact)
        return HStack(spacing: 12) {
            Button(action: { toggle(contact) }) {
                ZStack {
                    Circle().strokeBorder(isSelected ? AppColor.brandPrimary : Color(hex: 0xCBD5E1), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(AppColor.brandPrimary).frame(width: 14, height: 14)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.custom("Inter-SemiBold", size: 15))
                    .foregroundStyle(AppColor.textPrimary)
                badges(for: contact)
            }

            Spacer()

            Button(action: { editingID = contact.identifier }) {
                Text("Edit")
                    .font(.custom("Inter-SemiBold", size: 13))
                    .foregroundStyle(AppColor.brandPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(AppColor.brandPrimary.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func badges(for contact: CNContact) -> some View {
        let nameMissing = ContactsService.isNameMissing(contact)
        let phoneMissing = contact.phoneNumbers.isEmpty
        HStack(spacing: 6) {
            if nameMissing  { badge("Missing contact name") }
            if phoneMissing { badge("Missing phone number") }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.custom("Inter-Medium", size: 11))
            .foregroundStyle(AppColor.danger)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppColor.danger.opacity(0.10)))
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.success)
            Text("All contacts look complete")
                .font(.custom("Inter-Bold", size: 20))
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    private var deleteBar: some View {
        Button(action: { Task { await performDelete() } }) {
            HStack(spacing: 8) {
                if deleting { ProgressView().tint(.white) }
                Image(systemName: "trash")
                Text("Delete \(selection.count) selected")
            }
            .font(.custom("Inter-Bold", size: 15))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.danger)
                    .shadow(color: AppColor.danger.opacity(0.2), radius: 10, x: 0, y: 6)
            )
        }
        .disabled(deleting)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Actions

    private func toggle(_ contact: CNContact) {
        if selection.contains(contact.identifier) {
            selection.remove(contact.identifier)
        } else {
            selection.insert(contact.identifier)
        }
    }

    private func toggleSelectAll() {
        if selection.count == contacts.count {
            selection.removeAll()
        } else {
            selection = Set(contacts.map(\.identifier))
        }
    }

    private func performDelete() async {
        deleting = true
        defer { deleting = false }
        do {
            try await service.delete(contacts: selectedContacts)
            contacts.removeAll { selection.contains($0.identifier) }
            selection.removeAll()
            if !PermissionManager.shared.isPremium, let vc = AdHelpers.topViewController() {
                AdManager.shared.showInterstitialAd(
                    adUnitID: AdUnits.interContactsAction,
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
