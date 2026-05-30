import Foundation
import Security

// Minimal Keychain wrapper. Used by VaultService for:
//   • the user's 6-digit passcode (string)
//   • the AES-256-GCM symmetric key for vault encryption (Data)
//
// Items are kept private to this app, accessibleAfterFirstUnlock so the keychain
// is available after a reboot once the device has been unlocked once.
enum Keychain {
    enum Error: Swift.Error { case notFound, status(OSStatus) }

    static func set(_ data: Data, forKey key: String) throws {
        let attrs: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(attrs as CFDictionary)  // upsert
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.status(status) }
    }

    static func data(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // String convenience
    static func setString(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else { throw Error.notFound }
        try set(data, forKey: key)
    }

    static func string(forKey key: String) -> String? {
        guard let data = data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
