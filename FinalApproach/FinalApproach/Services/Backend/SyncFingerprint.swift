import CryptoKit
import Foundation

extension SpottedPhoto {
    /// A value that changes whenever the saved record changes, so a sync can
    /// tell an edited photo from an untouched one without keeping a second
    /// copy of it. It is a hash, so it gives nothing of the record away.
    func syncFingerprint() throws -> String {
        let encoder = JSONEncoder()
        // Sorted keys make the same record give the same bytes every time.
        encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(self))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
