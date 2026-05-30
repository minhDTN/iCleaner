import SwiftUI
import Contacts

// Figma `2012:4832` (All Contacts). A-Z sectioned list with search bar at top
// and avatar circle per row. Tap → CNContactViewController.
struct ContactsAllView: View {
    @Bindable var service: ContactsService

    @State private var contacts: [CNContact] = []
    @State private var query: String = ""
    @State private var loading: Bool = true
    @State private var editingID: String?

    private var grouped: [(letter: String, items: [CNContact])] {
        let filtered: [CNContact]
        if query.isEmpty {
            filtered = contacts
        } else {
            let q = query.lowercased()
            filtered = contacts.filter { c in
                ContactsService.displayName(for: c).lowercased().contains(q)
                || c.phoneNumbers.contains(where: { $0.value.stringValue.contains(query) })
            }
        }
        var buckets: [String: [CNContact]] = [:]
        for c in filtered {
            let name = ContactsService.displayName(for: c)
            let key = String(name.prefix(1)).uppercased()
            let letter = key.range(of: "[A-Z]", options: .regularExpression) != nil ? key : "#"
            buckets[letter, default: []].append(c)
        }
        return buckets.keys.sorted().map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()
            if loading {
                ProgressView().tint(AppColor.brandPrimary)
            } else {
                List {
                    ForEach(grouped, id: \.letter) { section in
                        Section(header: sectionHeader(section.letter)) {
                            ForEach(section.items, id: \.identifier) { contact in
                                row(contact)
                                    .listRowBackground(AppColor.surfaceBackground)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search contacts")
            }
        }
        .navigationTitle("All contacts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            contacts = await service.fetchAllContacts()
            loading = false
        }
        .sheet(item: Binding(
            get: { editingID.flatMap { id in contacts.first(where: { $0.identifier == id }) }.map { Box(c: $0) } },
            set: { editingID = $0?.c.identifier }
        )) { box in
            ContactReadOnly(contact: box.c) { editingID = nil }
        }
    }

    private func sectionHeader(_ letter: String) -> some View {
        Text(letter)
            .font(.custom("Inter-Bold", size: 13))
            .foregroundStyle(AppColor.textMuted)
    }

    private func row(_ contact: CNContact) -> some View {
        let name = ContactsService.displayName(for: contact)
        let phone = contact.phoneNumbers.first?.value.stringValue ?? "—"
        return Button(action: { editingID = contact.identifier }) {
            HStack(spacing: 12) {
                avatar(for: contact, name: name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.custom("Inter-SemiBold", size: 15))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(phone)
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func avatar(for contact: CNContact, name: String) -> some View {
        let initials = name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return Group {
            if contact.imageDataAvailable, let data = contact.thumbnailImageData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(AppColor.brandPrimary.opacity(0.15))
                    Text(initials.isEmpty ? "?" : initials)
                        .font(.custom("Inter-SemiBold", size: 13))
                        .foregroundStyle(AppColor.brandPrimary)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}

private struct Box: Identifiable {
    let c: CNContact
    var id: String { c.identifier }
}

// Read-only contact view (no edit). Used when tapping in All — keeps the
// destructive editor reserved for the Incomplete flow.
import ContactsUI
private struct ContactReadOnly: UIViewControllerRepresentable {
    let contact: CNContact
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CNContactViewController(for: contact)
        vc.allowsEditing = false
        vc.allowsActions = true
        vc.delegate = context.coordinator
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        var onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onDismiss()
        }
    }
}
