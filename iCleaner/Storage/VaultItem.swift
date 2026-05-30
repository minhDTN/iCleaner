import Foundation
import SwiftData

// Metadata row for an encrypted item stored in the private vault.
// The actual encrypted payload lives at `Documents/Vault/<id>.dat`.
// Decryption happens through VaultService — see vault.encryptedURL(for:).
@Model
final class VaultItem {
    @Attribute(.unique) var id: UUID
    var addedAt: Date
    var sizeBytes: Int
    var fileName: String  // original PHAsset filename (e.g. "IMG_9842.HEIC") or generated "Photo-{date}"
    var mimeType: String  // "image/jpeg" | "image/heic" | "image/png" — drives display
    var pixelWidth: Int
    var pixelHeight: Int

    init(id: UUID = UUID(),
         addedAt: Date = Date(),
         sizeBytes: Int,
         fileName: String,
         mimeType: String,
         pixelWidth: Int,
         pixelHeight: Int) {
        self.id = id
        self.addedAt = addedAt
        self.sizeBytes = sizeBytes
        self.fileName = fileName
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}
