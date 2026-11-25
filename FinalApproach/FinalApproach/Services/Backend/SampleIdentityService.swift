import Foundation

/// An identity service that keeps everything in memory. It is for previews
/// and tests, and follows the real one's rules. A signed out session cannot
/// be refreshed.
final class SampleIdentityService: IdentityService {
    /// The users who have signed in at least once.
    private(set) var userIDs: Set<String> = []
    /// The refresh tokens that still work.
    private(set) var liveRefreshTokens: Set<String> = []
    private(set) var signInCount = 0
    /// The test accounts that exist, each with its password.
    var testAccounts: [String: String] = [:]
    /// The test accounts whose password was never set for good.
    var unreadyTestAccounts: Set<String> = []
    private(set) var refreshCount = 0
    private var issued = 0

    /// How long an access token works.
    var accessTokenLifetime: TimeInterval = 3600
    var now: () -> Date = { Date() }
    /// Set to make the next calls fail the way the real one can.
    var failure: IdentityError?
    /// Runs while a refresh is on its way, so a test can act in the middle.
    var duringRefresh: (() async -> Void)?

    func signIn(userID: String, identityToken: String) async throws -> SessionTokens {
        if let failure { throw failure }
        guard !identityToken.isEmpty else { throw IdentityError.tokenRefused }
        signInCount += 1
        userIDs.insert(userID)
        issued += 1
        let refreshToken = "sample-refresh-\(issued)"
        liveRefreshTokens.insert(refreshToken)
        return tokens(refreshToken: refreshToken)
    }

    func signIn(testAccount name: String, password: String) async throws -> SessionTokens {
        if let failure { throw failure }
        guard let expected = testAccounts[name], expected == password else {
            throw IdentityError.credentialsRefused
        }
        guard !unreadyTestAccounts.contains(name) else { throw IdentityError.testAccountNotReady }
        signInCount += 1
        userIDs.insert(name)
        issued += 1
        let refreshToken = "sample-refresh-\(issued)"
        liveRefreshTokens.insert(refreshToken)
        return tokens(refreshToken: refreshToken)
    }

    func refresh(_ tokens: SessionTokens) async throws -> SessionTokens {
        refreshCount += 1
        await duringRefresh?()
        if let failure { throw failure }
        guard liveRefreshTokens.contains(tokens.refreshToken) else { throw IdentityError.sessionEnded }
        issued += 1
        return self.tokens(refreshToken: tokens.refreshToken)
    }

    func signOut(_ tokens: SessionTokens) async throws {
        if let failure { throw failure }
        liveRefreshTokens.remove(tokens.refreshToken)
    }

    /// Ends a session from the backend's side, as a delete of the account
    /// on another device would.
    func endSession(refreshToken: String) {
        liveRefreshTokens.remove(refreshToken)
    }

    private func tokens(refreshToken: String) -> SessionTokens {
        SessionTokens(
            accessToken: "sample-access-\(issued)",
            refreshToken: refreshToken,
            accessTokenExpiresAt: now().addingTimeInterval(accessTokenLifetime)
        )
    }
}
