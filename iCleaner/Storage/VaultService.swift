import Foundation
import CryptoKit
import Observation
import LocalAuthentication

// One-stop service for the Private Vault.
//   • Passcode lifecycle (set / verify / change / has-passcode)
//   • AES-256-GCM encrypt/decrypt of image blobs
//   • File-system storage at Documents/Vault/<id>.dat
//   • Face ID / Touch ID via LAContext
//
// Encryption key is generated once per install and lives in Keychain alongside
// the passcode. The passcode is a UX gate — it does NOT derive the encryption
// key, so forgetting the passcode would still need a separate reset flow to
// destroy the key (Part B handles that with an explicit "Erase Vault" action
// in Settings if needed).
@MainActor
@Observable
final class VaultService {
    enum AuthError: Error { case biometryUnavailable, biometryFailed, passcodeMismatch }

    private enum KCKey {
        static let passcode      = "icleaner.vault.passcode"
        static let encryptionKey = "icleaner.vault.encryptionKey"
    }

    private(set) var isUnlocked: Bool = false

    var hasPasscode: Bool { Keychain.data(forKey: KCKey.passcode) != nil }
    var canUseBiometry: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return "Biometrics"
        }
    }

    // MARK: - Passcode

    func setPasscode(_ code: String) throws {
        try Keychain.setString(code, forKey: KCKey.passcode)
        // Provision an encryption key the first time a passcode is set.
        if Keychain.data(forKey: KCKey.encryptionKey) == nil {
            let key = SymmetricKey(size: .bits256)
            try Keychain.set(key.withUnsafeBytes { Data($0) }, forKey: KCKey.encryptionKey)
        }
    }

    func verifyPasscode(_ code: String) -> Bool {
        guard let stored = Keychain.string(forKey: KCKey.passcode) else { return false }
        let match = stored == code
        if match { isUnlocked = true }
        return match
    }

    func changePasscode(old: String, new: String) throws {
        guard verifyPasscode(old) else { throw AuthError.passcodeMismatch }
        try Keychain.setString(new, forKey: KCKey.passcode)
    }

    func lock() { isUnlocked = false }

    // MARK: - Biometric unlock

    func unlockWithBiometry(reason: String = "Unlock your private vault") async throws {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw AuthError.biometryUnavailable
        }
        let success: Bool = try await withCheckedThrowingContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: ok)
            }
        }
        guard success else { throw AuthError.biometryFailed }
        isUnlocked = true
    }

    // MARK: - Encryption
    // These are `nonisolated` so VaultGridView / VaultPreviewView can offload
    // decrypt to a detached task without an actor hop. They don't touch
    // `isUnlocked` or any other actor-isolated state — they only read from the
    // Keychain (thread-safe) and the file system.

    nonisolated private func key() throws -> SymmetricKey {
        guard let data = Keychain.data(forKey: KCKey.encryptionKey) else {
            throw AuthError.passcodeMismatch
        }
        return SymmetricKey(data: data)
    }

    nonisolated func encrypt(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: try key())
        guard let combined = sealed.combined else { throw AuthError.passcodeMismatch }
        return combined
    }

    nonisolated func decrypt(_ ciphertext: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: try key())
    }

    // MARK: - File storage

    nonisolated static let vaultDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Vault", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    nonisolated func encryptedURL(for itemID: UUID) -> URL {
        Self.vaultDirectory.appendingPathComponent("\(itemID.uuidString).dat")
    }

    nonisolated func writeEncrypted(_ plaintext: Data, for itemID: UUID) throws {
        let cipher = try encrypt(plaintext)
        try cipher.write(to: encryptedURL(for: itemID), options: .atomic)
    }

    nonisolated func readDecrypted(for itemID: UUID) throws -> Data {
        let cipher = try Data(contentsOf: encryptedURL(for: itemID))
        return try decrypt(cipher)
    }

    nonisolated func deleteFile(for itemID: UUID) {
        try? FileManager.default.removeItem(at: encryptedURL(for: itemID))
    }
}
