import Foundation
import Contacts
import UIKit
import Observation

// Read + write wrapper around CNContactStore.
//
// READ: dashboard counts (refresh), full lists for detail screens
// (fetchDuplicateGroups / fetchIncompleteContacts / fetchAllContacts),
// backup file enumeration (fetchBackups).
// WRITE: merge a duplicate group into one contact, delete contacts,
// create a vCard backup, restore from a backup file.
//
// All heavy work runs on Task.detached. Mutating methods refresh counts
// after success so the dashboard cards update automatically.
@MainActor
@Observable
final class ContactsService {
    enum AuthStatus: Equatable {
        case notDetermined, denied, restricted, authorized, limited

        init(_ raw: CNAuthorizationStatus) {
            switch raw {
            case .notDetermined: self = .notDetermined
            case .restricted:    self = .restricted
            case .denied:        self = .denied
            case .authorized:    self = .authorized
            case .limited:       self = .limited
            @unknown default:    self = .denied
            }
        }

        var canRead: Bool { self == .authorized || self == .limited }
    }

    private(set) var authStatus: AuthStatus
    private(set) var totalCount: Int = 0
    private(set) var duplicateGroupCount: Int = 0
    private(set) var incompleteCount: Int = 0
    private(set) var backupCount: Int = 0
    private(set) var isRefreshing: Bool = false
    private(set) var lastRefreshed: Date?

    private let store = CNContactStore()

    init() {
        self.authStatus = AuthStatus(CNContactStore.authorizationStatus(for: .contacts))
        self.backupCount = Self.countBackups()
    }

    @discardableResult
    func requestAccess() async -> AuthStatus {
        do {
            try await store.requestAccess(for: .contacts)
        } catch {
            // ignore
        }
        let new = AuthStatus(CNContactStore.authorizationStatus(for: .contacts))
        authStatus = new
        return new
    }

    func refresh() async {
        guard authStatus.canRead, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefreshed = .init() }

        let snapshot = await Task.detached(priority: .userInitiated) { [store] in
            return Self.scan(store: store)
        }.value

        totalCount = snapshot.total
        duplicateGroupCount = snapshot.duplicateGroups
        incompleteCount = snapshot.incomplete
        backupCount = Self.countBackups()
    }

    func opensSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Detail fetches

    func fetchDuplicateGroups() async -> [DuplicateGroup] {
        guard authStatus.canRead else { return [] }
        return await Task.detached(priority: .userInitiated) { [store] in
            Self.scanForGroups(store: store)
        }.value
    }

    func fetchIncompleteContacts() async -> [CNContact] {
        guard authStatus.canRead else { return [] }
        return await Task.detached(priority: .userInitiated) { [store] in
            Self.fetchAll(store: store).filter { contact in
                let hasName = !(contact.givenName + contact.familyName).trimmingCharacters(in: .whitespaces).isEmpty
                    || !contact.organizationName.isEmpty
                let hasPhone = !contact.phoneNumbers.isEmpty
                return !hasName || !hasPhone
            }
        }.value
    }

    func fetchAllContacts() async -> [CNContact] {
        guard authStatus.canRead else { return [] }
        return await Task.detached(priority: .userInitiated) { [store] in
            Self.fetchAll(store: store)
                .sorted { Self.sortKey($0) < Self.sortKey($1) }
        }.value
    }

    func fetchBackups() -> [BackupFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.backupsDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "vcf" }
            .compactMap { url -> BackupFile? in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                guard let created = values?.creationDate else { return nil }
                let bytes = values?.fileSize ?? 0
                return BackupFile(url: url, createdAt: created, sizeBytes: bytes,
                                  contactCount: Self.countContacts(in: url))
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Mutations

    @discardableResult
    func merge(group: DuplicateGroup) async throws -> String {
        try await mergeContacts(group.contacts)
    }

    // Union-merge an arbitrary set of contacts into the first, delete the rest.
    // Returns the display name of the resulting merged contact (for the UI toast).
    @discardableResult
    func mergeContacts(_ contacts: [CNContact]) async throws -> String {
        guard authStatus.canRead, contacts.count >= 2 else { return "" }
        let name = try await Task.detached(priority: .userInitiated) { [store] in
            try Self.performMerge(contacts: contacts, store: store)
        }.value
        await refresh()
        return name
    }

    func delete(contacts: [CNContact]) async throws {
        guard authStatus.canRead, !contacts.isEmpty else { return }
        try await Task.detached(priority: .userInitiated) { [store] in
            let req = CNSaveRequest()
            for c in contacts {
                if let mut = c.mutableCopy() as? CNMutableContact {
                    req.delete(mut)
                }
            }
            try store.execute(req)
        }.value
        await refresh()
    }

    // Writes every contact (vCard) into ContactBackups/<timestamp>.vcf.
    @discardableResult
    func createBackup() async throws -> BackupFile {
        guard authStatus.canRead else { throw NSError(domain: "iCleaner", code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Contacts access required."]) }
        let url = try await Task.detached(priority: .userInitiated) { [store] in
            try Self.performBackup(store: store)
        }.value
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        await refresh()
        return BackupFile(
            url: url,
            createdAt: values?.creationDate ?? Date(),
            sizeBytes: values?.fileSize ?? 0,
            contactCount: Self.countContacts(in: url)
        )
    }

    // Count vCard entries cheaply by scanning for BEGIN:VCARD markers.
    nonisolated private static func countContacts(in url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.components(separatedBy: "BEGIN:VCARD").count - 1
    }

    @discardableResult
    func restore(from file: BackupFile) async throws -> Int {
        guard authStatus.canRead else { return 0 }
        let count = try await Task.detached(priority: .userInitiated) { [store] in
            try Self.performRestore(file: file, store: store)
        }.value
        await refresh()
        return count
    }

    func deleteBackup(_ file: BackupFile) {
        try? FileManager.default.removeItem(at: file.url)
        backupCount = Self.countBackups()
    }

    // MARK: - Backups dir

    nonisolated static let backupsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ContactBackups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    private static func countBackups() -> Int {
        let items = (try? FileManager.default.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension.lowercased() == "vcf" }.count
    }

    // MARK: - Scan implementations (nonisolated, run on detached tasks)

    nonisolated private static let detailKeys: [CNKeyDescriptor] = [
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactMiddleNameKey,
        CNContactOrganizationNameKey,
        CNContactPhoneNumbersKey,
        CNContactEmailAddressesKey,
        CNContactPostalAddressesKey,
        CNContactImageDataKey,
        CNContactImageDataAvailableKey,
        CNContactThumbnailImageDataKey,
    ] as [CNKeyDescriptor]

    nonisolated private static func scan(store: CNContactStore) -> Snapshot {
        let keys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey,
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var total = 0
        var incomplete = 0
        var phoneBuckets: [String: Int] = [:]
        var nameBuckets: [String: Int] = [:]

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                total += 1
                let name = ((contact.givenName + " " + contact.familyName)
                    .trimmingCharacters(in: .whitespaces))
                let hasName = !name.isEmpty || !contact.organizationName.isEmpty
                let hasPhone = !contact.phoneNumbers.isEmpty
                if !hasName || !hasPhone { incomplete += 1 }
                for ph in contact.phoneNumbers {
                    let digits = ph.value.stringValue.filter(\.isNumber)
                    guard digits.count >= 6 else { continue }
                    let key = String(digits.suffix(9))
                    phoneBuckets[key, default: 0] += 1
                }
                if !hasPhone, !name.isEmpty {
                    nameBuckets[name.lowercased(), default: 0] += 1
                }
            }
        } catch {}

        let duplicateGroups =
            phoneBuckets.values.filter { $0 >= 2 }.count +
            nameBuckets.values.filter  { $0 >= 2 }.count

        return Snapshot(total: total, duplicateGroups: duplicateGroups, incomplete: incomplete)
    }

    nonisolated private static func fetchAll(store: CNContactStore) -> [CNContact] {
        let request = CNContactFetchRequest(keysToFetch: detailKeys)
        var result: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                result.append(contact)
            }
        } catch {}
        return result
    }

    nonisolated private static func scanForGroups(store: CNContactStore) -> [DuplicateGroup] {
        let all = fetchAll(store: store)
        // phone-based bucketing primary
        var byPhone: [String: [CNContact]] = [:]
        for c in all {
            for ph in c.phoneNumbers {
                let digits = ph.value.stringValue.filter(\.isNumber)
                guard digits.count >= 6 else { continue }
                let key = String(digits.suffix(9))
                byPhone[key, default: []].append(c)
            }
        }
        // name-fallback bucketing for phone-less contacts
        var seenIDs = Set<String>()
        var groups: [DuplicateGroup] = []
        for (_, list) in byPhone where list.count >= 2 {
            // dedupe within bucket — a single contact may appear twice if it has the same phone twice
            var unique: [CNContact] = []
            var ids = Set<String>()
            for c in list where !ids.contains(c.identifier) {
                ids.insert(c.identifier); unique.append(c)
            }
            guard unique.count >= 2 else { continue }
            unique.forEach { seenIDs.insert($0.identifier) }
            groups.append(DuplicateGroup(title: bestTitle(for: unique), contacts: unique))
        }
        var byName: [String: [CNContact]] = [:]
        for c in all where !seenIDs.contains(c.identifier) && c.phoneNumbers.isEmpty {
            let name = (c.givenName + " " + c.familyName).trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty else { continue }
            byName[name, default: []].append(c)
        }
        for (_, list) in byName where list.count >= 2 {
            groups.append(DuplicateGroup(title: bestTitle(for: list), contacts: list))
        }
        return groups.sorted { $0.contacts.count > $1.contacts.count }
    }

    nonisolated private static func bestTitle(for contacts: [CNContact]) -> String {
        for c in contacts {
            let n = (c.givenName + " " + c.familyName).trimmingCharacters(in: .whitespaces)
            if !n.isEmpty { return n }
            if !c.organizationName.isEmpty { return c.organizationName }
        }
        return contacts.first?.phoneNumbers.first?.value.stringValue ?? "Unknown"
    }

    nonisolated private static func sortKey(_ c: CNContact) -> String {
        let raw = (c.familyName + c.givenName + c.organizationName)
            .trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? "~" : raw.lowercased()
    }

    // MARK: - Mutation implementations

    @discardableResult
    nonisolated private static func performMerge(contacts: [CNContact], store: CNContactStore) throws -> String {
        guard let firstID = contacts.first?.identifier else { return "" }
        // Re-fetch with all keys (the snapshot lists fetched only basic keys).
        let predicate = CNContact.predicateForContacts(withIdentifiers: contacts.map(\.identifier))
        let fetched = (try? store.unifiedContacts(matching: predicate, keysToFetch: detailKeys)) ?? []
        guard let primaryFetched = fetched.first(where: { $0.identifier == firstID }) else { return "" }
        guard let primary = primaryFetched.mutableCopy() as? CNMutableContact else { return "" }

        var seenPhones = Set<String>(primary.phoneNumbers.map { Self.phoneKey($0.value.stringValue) })
        var seenEmails = Set<String>(primary.emailAddresses.map { String($0.value).lowercased() })

        for c in fetched where c.identifier != firstID {
            for ph in c.phoneNumbers {
                let key = Self.phoneKey(ph.value.stringValue)
                guard !key.isEmpty, !seenPhones.contains(key) else { continue }
                seenPhones.insert(key)
                primary.phoneNumbers.append(ph)
            }
            for em in c.emailAddresses {
                let key = String(em.value).lowercased()
                guard !seenEmails.contains(key) else { continue }
                seenEmails.insert(key)
                primary.emailAddresses.append(em)
            }
            // pick up name fields if primary lacks them
            if primary.givenName.isEmpty   { primary.givenName   = c.givenName }
            if primary.familyName.isEmpty  { primary.familyName  = c.familyName }
            if primary.organizationName.isEmpty { primary.organizationName = c.organizationName }
        }

        let req = CNSaveRequest()
        req.update(primary)
        for c in fetched where c.identifier != firstID {
            if let mut = c.mutableCopy() as? CNMutableContact {
                req.delete(mut)
            }
        }
        try store.execute(req)

        // Name of the surviving merged contact, for the success toast.
        let merged = (primary.givenName + " " + primary.familyName).trimmingCharacters(in: .whitespaces)
        if !merged.isEmpty { return merged }
        if !primary.organizationName.isEmpty { return primary.organizationName }
        return primary.phoneNumbers.first?.value.stringValue ?? ""
    }

    nonisolated private static func phoneKey(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 6 else { return "" }
        return String(digits.suffix(9))
    }

    nonisolated private static func performBackup(store: CNContactStore) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupsDirectory.appendingPathComponent("backup-\(stamp).vcf")
        try writeAllContacts(to: url, store: store)
        return url
    }

    /// Serializes EVERY device contact to `url` as a vCard. Shared by the manual
    /// backup and the auto session backup. vCard serialization REQUIRES contacts
    /// fetched with its own descriptor — our detailKeys subset makes data(with:)
    /// throw, which is why the backup failed before.
    nonisolated static func writeAllContacts(to url: URL, store: CNContactStore) throws {
        let request = CNContactFetchRequest(keysToFetch: [CNContactVCardSerialization.descriptorForRequiredKeys()])
        var all: [CNContact] = []
        try store.enumerateContacts(with: request) { contact, _ in all.append(contact) }
        let data = try CNContactVCardSerialization.data(with: all)
        try data.write(to: url, options: .atomic)
    }

    nonisolated private static func performRestore(file: BackupFile, store: CNContactStore) throws -> Int {
        let data = try Data(contentsOf: file.url)
        let contacts = try CNContactVCardSerialization.contacts(with: data)
        let req = CNSaveRequest()
        for c in contacts {
            if let mut = c.mutableCopy() as? CNMutableContact {
                req.add(mut, toContainerWithIdentifier: nil)
            }
        }
        try store.execute(req)
        return contacts.count
    }

    struct Snapshot { let total: Int; let duplicateGroups: Int; let incomplete: Int }
}

// MARK: - Models

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let title: String
    let contacts: [CNContact]
    var phoneCount: Int { Set(contacts.flatMap { $0.phoneNumbers.map { $0.value.stringValue } }).count }
}

struct BackupFile: Identifiable {
    let url: URL
    let createdAt: Date
    let sizeBytes: Int
    let contactCount: Int
    var id: URL { url }
}
