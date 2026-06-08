import SwiftUI
import Contacts
import ContactsUI
import LibEarnMoneyIOS

// Figma `2012:4832` (All Contacts). Header = back + "All Contacts" + "N contacts"
// + "Select all". Custom search field (#F2F3FF), then A-Z section cards (each a
// white rounded card with hairline-divided rows). Row = colourful avatar + name
// (Regular 17) + phone/email (Regular 15) + chevron. Tap a row → contact detail.
// "Select all" enters a selection mode (checkboxes + Delete bar), matching the
// other contact screens.
struct ContactsAllView: View {
    @Bindable var service: ContactsService

    @State private var contacts: [CNContact] = []
    @State private var query: String = ""
    @State private var loading: Bool = true
    @State private var editingID: String?
    @State private var selection: Set<String> = []
    @State private var deleting: Bool = false
    @State private var actionError: String?
    @State private var showPaywall: Bool = false

    private var selectionMode: Bool { !selection.isEmpty }

    private var filtered: [CNContact] {
        guard !query.isEmpty else { return contacts }
        let q = query.lowercased()
        return contacts.filter { c in
            ContactsService.displayName(for: c).lowercased().contains(q)
            || c.phoneNumbers.contains { $0.value.stringValue.contains(query) }
            || c.emailAddresses.contains { String($0.value).lowercased().contains(q) }
        }
    }

    private var grouped: [(letter: String, items: [CNContact])] {
        var buckets: [String: [CNContact]] = [:]
        for c in filtered {
            let name = ContactsService.displayName(for: c)
            let key = String(name.prefix(1)).uppercased()
            let letter = key.range(of: "[A-Z]", options: .regularExpression) != nil ? key : "#"
            buckets[letter, default: []].append(c)
        }
        return buckets.keys.sorted().map { ($0, buckets[$0] ?? []) }
    }

    private var isAllSelected: Bool { !contacts.isEmpty && selection.count == contacts.count }

    var body: some View {
        VStack(spacing: 0) {
            ContactsDetailHeader(title: L("contacts.all.title"), subtitle: L("contacts.count", contacts.count)) {
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
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                            searchBar
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                            ForEach(grouped, id: \.letter) { section in
                                sectionView(section)
                                    .padding(.horizontal, 20)
                            }
                        }
                        .padding(.bottom, selectionMode ? 110 : 24)
                    }
                }

                if selectionMode { deleteBar }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .task {
            FlowGate.showStartAd()   // ad on feature entry (free users)
            contacts = await service.fetchAllContacts()
            loading = false
        }
        // Push the device's native contact card (CNContactViewController) onto the
        // nav stack — a full-screen detail with a system back button — instead of
        // a modal sheet over the list.
        .navigationDestination(item: Binding(
            get: { editingID.flatMap { id in contacts.first(where: { $0.identifier == id }) }.map { Box(c: $0) } },
            set: { editingID = $0?.c.identifier }
        )) { box in
            // Hide SwiftUI's nav bar so only the contact card's own bar (with a
            // single back button) shows — otherwise there are TWO back buttons.
            SystemContactView(contact: box.c, onClose: { editingID = nil })
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarBackButtonHidden(true)
        }
        .alert(L("flow.deleteErrorTitle"), isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(hex: 0x737686))
            TextField("", text: $query, prompt: Text(L("contacts.all.search"))
                .foregroundColor(Color(hex: 0xC3C6D7)))
                .font(.custom("Inter-Regular", size: 16))
                .foregroundStyle(Color(hex: 0x131B2E))
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(hex: 0xC3C6D7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: 0xF2F3FF))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: 0xC3C6D7), lineWidth: 1)
        )
    }

    // MARK: - Section

    private func sectionView(_ section: (letter: String, items: [CNContact])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.letter)
                .font(.custom("Inter-SemiBold", size: 13))
                .tracking(13 * 0.05)
                .foregroundStyle(Color(hex: 0x434655))
                .padding(.vertical, 8)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.identifier) { idx, contact in
                    row(contact, isLast: idx == section.items.count - 1)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.surfaceBackground)
                    .shadow(color: Color(hex: 0x0F172A, alpha: 0.02), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xC3C6D7), lineWidth: 1)
            )
        }
    }

    private func row(_ contact: CNContact, isLast: Bool) -> some View {
        let name = ContactsService.displayName(for: contact)
        let sub = contact.phoneNumbers.first?.value.stringValue
            ?? contact.emailAddresses.first.map { String($0.value) }
            ?? "—"
        let selected = selection.contains(contact.identifier)
        return HStack(spacing: 16) {
            avatar(for: contact, name: name)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(.custom("Inter-Regular", size: 17))
                            .foregroundStyle(Color(hex: 0x131B2E))
                            .lineLimit(1)
                        Text(sub)
                            .font(.custom("Inter-Regular", size: 15))
                            .foregroundStyle(Color(hex: 0x434655))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if selectionMode {
                        ContactSelectRadio(isSelected: selected)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xC3C6D7))
                    }
                }
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    if !isLast {
                        Rectangle().fill(Color(hex: 0xC3C6D7)).frame(height: 1)
                    }
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectionMode { toggle(contact) }
            else { editingID = contact.identifier }
        }
    }

    // Colourful avatar palette cycled deterministically per contact (Figma).
    private static let avatarPalette: [(bg: UInt32, fg: UInt32)] = [
        (0xD0E1FB, 0x54647A),
        (0x0D7FF2, 0xFFFFFF),
        (0xCF2C30, 0xFFECEA),
        (0xDAE2FD, 0x434655),
        (0xD3E4FE, 0x0B1C30),
    ]

    private func avatar(for contact: CNContact, name: String) -> some View {
        let initials = name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        let hash = contact.identifier.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let pal = Self.avatarPalette[hash % Self.avatarPalette.count]
        return Group {
            if contact.imageDataAvailable, let data = contact.thumbnailImageData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color(hex: pal.bg))
                    Text(initials.isEmpty ? "#" : initials)
                        .font(.custom("Inter-SemiBold", size: 18))
                        .foregroundStyle(Color(hex: pal.fg))
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    // MARK: - Delete bar

    private var deleteBar: some View {
        ContactActionButton(title: L("contacts.deleteN", selection.count), iconAsset: "Contacts/ic_trash",
                             iconSize: CGSize(width: 14, height: 15),
                             style: .destructive, enabled: !deleting) {
            Task { await performDelete() }
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
        if FlowGate.requiresPaywall { showPaywall = true; return }   // final step → paywall for free
        deleting = true
        defer { deleting = false }
        let toDelete = contacts.filter { selection.contains($0.identifier) }
        do {
            try await service.delete(contacts: toDelete)
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

private struct Box: Identifiable, Hashable {
    let c: CNContact
    var id: String { c.identifier }
    static func == (lhs: Box, rhs: Box) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// The device's native contact card. Wrapped in its OWN UINavigationController so
// it shows a single nav bar with one back button (SwiftUI's bar is hidden on this
// destination). Re-fetches with the VC's required keys, else CNContactViewController
// crashes (CNPropertyNotFetchedException) on a contact fetched with a key subset.
private struct SystemContactView: UIViewControllerRepresentable {
    let contact: CNContact
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let keys: [CNKeyDescriptor] = [CNContactViewController.descriptorForRequiredKeys()]
        let display = (try? CNContactStore().unifiedContact(withIdentifier: contact.identifier,
                                                            keysToFetch: keys)) ?? contact
        let vc = CNContactViewController(for: display)
        vc.allowsEditing = false
        vc.allowsActions = true
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain, target: context.coordinator, action: #selector(Coordinator.close))
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        @objc func close() { onClose() }
    }
}
