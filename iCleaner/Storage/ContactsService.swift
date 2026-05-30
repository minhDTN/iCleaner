import Foundation
import Contacts
import Observation

// Read-side wrapper around CNContactStore. Detects duplicate clusters
// (by normalized phone number primary, fallback to lowercased full name) and
// incomplete contacts (missing both name and phone). Counts feed the
// ContactsDashboardView cards; full lists are pulled lazily by the detail
// screens in Phase 7 Part B.
//
// Backups are vCard files written to Documents/ContactBackups/*.vcf — listed
// here so the dashboard can show a count without scanning on every refresh.
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
            // Ignore — re-read the status below either way.
        }
        let new = AuthStatus(CNContactStore.authorizationStatus(for: .contacts))
        authStatus = new
        return new
    }

    // Walks every contact once, populates the dashboard counts. Off main thread.
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

    // MARK: - Backups (vCard) dir helpers

    static let backupsDirectory: URL = {
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

    // MARK: - Scan implementation

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
        // group key → count (for dup detection)
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

                // bucket by normalized phone number (strip non-digits) primary
                for ph in contact.phoneNumbers {
                    let digits = ph.value.stringValue.filter(\.isNumber)
                    guard digits.count >= 6 else { continue }
                    // last 9 digits — collapses +1, +84, etc.
                    let key = String(digits.suffix(9))
                    phoneBuckets[key, default: 0] += 1
                }
                // fallback: bucket by lowercased name if no phones
                if !hasPhone, !name.isEmpty {
                    let key = name.lowercased()
                    nameBuckets[key, default: 0] += 1
                }
            }
        } catch {
            // Permission revoked mid-scan or other failure — just return what we have.
        }

        let duplicateGroups =
            phoneBuckets.values.filter { $0 >= 2 }.count +
            nameBuckets.values.filter  { $0 >= 2 }.count

        return Snapshot(total: total, duplicateGroups: duplicateGroups, incomplete: incomplete)
    }

    struct Snapshot { let total: Int; let duplicateGroups: Int; let incomplete: Int }
}

import UIKit  // openSettingsURLString
