import Foundation
import Security

/// The sign in the app keeps between launches.
struct StoredSession: Codable, Equatable {
    /// Apple's id for the user, which is also their name on the backend.
    var userID: String
    var tokens: SessionTokens
    /// True from the moment the user asks to delete their account until the
    /// backend confirms it. It is saved with the tokens the delete needs, so
    /// a delete that could not be sent is still owed after the app closes.
    var isAccountDeleteOwed = false

    init(userID: String, tokens: SessionTokens, isAccountDeleteOwed: Bool = false) {
        self.userID = userID
        self.tokens = tokens
        self.isAccountDeleteOwed = isAccountDeleteOwed
    }

    private enum CodingKeys: String, CodingKey {
        case userID, tokens, isAccountDeleteOwed
    }

    /// A sign in saved before a delete could be owed still opens.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userID = try values.decode(String.self, forKey: .userID)
        tokens = try values.decode(SessionTokens.self, forKey: .tokens)
        isAccountDeleteOwed = try values.decodeIfPresent(Bool.self, forKey: .isAccountDeleteOwed) ?? false
    }
}

/// Why the saved sign in could not be read or written.
enum SessionStoreError: Error, Equatable {
    case keychain(status: Int32)
}

/// Where the saved sign in lives. It sits behind a protocol so tests and
/// previews do not touch the Keychain.
protocol SessionStore {
    func load() throws -> StoredSession?
    func save(_ session: StoredSession) throws
    func clear() throws
}

/// Keeps the sign in in the Keychain.
///
/// The item can be read after the first unlock, so a sync can run while the
/// phone is locked. It stays on this device. It is not copied to another
/// device through a backup or iCloud Keychain.
struct KeychainSessionStore: SessionStore {
    /// The name the item is filed under. Each build environment gets its
    /// own, so a beta sign in is never sent to prod.
    let service: String

    private static let account = "session"

    /// The store the app uses. The name carries the build's environment.
    static var forThisBuild: KeychainSessionStore {
        KeychainSessionStore(service: "com.finalapproach.app.session.\(AppEnvironment.current.rawValue)")
    }

    private var item: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func load() throws -> StoredSession? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = found as? Data else {
            throw SessionStoreError.keychain(status: status)
        }
        // A sign in this version cannot read counts as none, and the user
        // signs in again.
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        let updated = SecItemUpdate(item as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else {
            throw SessionStoreError.keychain(status: updated)
        }
        var new = item
        new[kSecValueData as String] = data
        new[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(new as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw SessionStoreError.keychain(status: added)
        }
    }

    func clear() throws {
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionStoreError.keychain(status: status)
        }
    }
}

/// Keeps the sign in in memory, for previews and tests.
final class MemorySessionStore: SessionStore {
    private(set) var session: StoredSession?
    private(set) var saveCount = 0
    /// Set to make saving fail, as a locked Keychain would.
    var failsSaves = false

    init(_ session: StoredSession? = nil) {
        self.session = session
    }

    func load() throws -> StoredSession? { session }

    func save(_ session: StoredSession) throws {
        if failsSaves { throw SessionStoreError.keychain(status: errSecInteractionNotAllowed) }
        saveCount += 1
        self.session = session
    }

    func clear() throws {
        session = nil
    }
}
