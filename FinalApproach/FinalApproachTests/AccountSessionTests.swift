import Foundation
import Testing

@testable import FinalApproach

/// A clock a test can move.
@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

/// Who is signed in, and the token their requests carry.
@MainActor
struct AccountSessionTests {
    private let clock = TestClock()
    private let identity = SampleIdentityService()

    /// An identity token whose payload names the given user. Nothing in the
    /// app checks the other two parts.
    private func appleToken(for userID: String = "apple-user-1") -> String {
        let payload = Data(#"{"sub":"\#(userID)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    private func session(
        store: MemorySessionStore = MemorySessionStore(),
        withBackend: Bool = true
    ) -> AccountSession {
        let clock = self.clock
        identity.now = { clock.now }
        return AccountSession(
            identity: withBackend ? identity : nil,
            store: store,
            refreshMargin: 120,
            now: { clock.now }
        )
    }

    // MARK: Signing in

    @Test func noOneIsSignedInAtFirst() async throws {
        let account = session()

        #expect(account.state == .signedOut)
        #expect(!account.isSignedIn)
        #expect(account.canSignIn)
        await #expect(throws: PhotoBackendError.notSignedIn) {
            try await account.accessToken()
        }
    }

    @Test func signingInSavesTheSessionUnderTheUserAppleNamed() async throws {
        let store = MemorySessionStore()
        let account = session(store: store)

        try await account.signIn(identityToken: appleToken(for: "apple-user-7"))

        #expect(account.state == .signedIn(userID: "apple-user-7"))
        #expect(identity.userIDs == ["apple-user-7"])
        #expect(store.session?.userID == "apple-user-7")
        let token = try await account.accessToken()
        #expect(token == store.session?.tokens.accessToken)
    }

    @Test func aSavedSessionIsStillSignedInOnTheNextLaunch() async throws {
        let store = MemorySessionStore()
        try await session(store: store).signIn(identityToken: appleToken())

        let relaunched = session(store: store)

        #expect(relaunched.state == .signedIn(userID: "apple-user-1"))
        let token = try await relaunched.accessToken()
        #expect(token == "sample-access-1")
        #expect(identity.signInCount == 1)
    }

    @Test func textThatIsNotATokenIsRefusedBeforeAnythingIsSent() async throws {
        let account = session()

        await #expect(throws: IdentityError.tokenRefused) {
            try await account.signIn(identityToken: "not a token")
        }
        #expect(identity.signInCount == 0)
        #expect(account.state == .signedOut)
    }

    @Test func aTokenTheBackendRefusesLeavesNoOneSignedIn() async throws {
        let store = MemorySessionStore()
        let account = session(store: store)
        identity.failure = .tokenRefused

        await #expect(throws: IdentityError.tokenRefused) {
            try await account.signIn(identityToken: appleToken())
        }
        #expect(account.state == .signedOut)
        #expect(store.session == nil)
    }

    @Test func aSignInThatCannotBeSavedDoesNotCount() async throws {
        let store = MemorySessionStore()
        store.failsSaves = true
        let account = session(store: store)

        await #expect(throws: SessionStoreError.self) {
            try await account.signIn(identityToken: appleToken())
        }
        #expect(account.state == .signedOut)
        #expect(!account.isSignedIn)
    }

    @Test func aBuildWithNoBackendCannotSignInAndIgnoresASavedSession() async throws {
        let store = MemorySessionStore()
        try await session(store: store).signIn(identityToken: appleToken())

        let account = session(store: store, withBackend: false)

        #expect(!account.canSignIn)
        #expect(account.state == .signedOut)
        await #expect(throws: PhotoBackendError.notSignedIn) {
            try await account.signIn(identityToken: appleToken())
        }
    }

    // MARK: The access token

    @Test func aFreshTokenIsUsedAsItIs() async throws {
        let account = session()
        try await account.signIn(identityToken: appleToken())

        clock.now += 3600 - 121
        let token = try await account.accessToken()
        #expect(token == "sample-access-1")
        #expect(identity.refreshCount == 0)
    }

    @Test func aTokenAboutToRunOutIsReplacedAndTheNewOneIsSaved() async throws {
        let store = MemorySessionStore()
        let account = session(store: store)
        try await account.signIn(identityToken: appleToken())

        clock.now += 3600 - 120
        let token = try await account.accessToken()

        #expect(token == "sample-access-2")
        #expect(identity.refreshCount == 1)
        #expect(store.session?.tokens.accessToken == "sample-access-2")
        #expect(store.session?.tokens.refreshToken == "sample-refresh-1")
        // The new token is fresh, so the next request does not refresh again.
        let again = try await account.accessToken()
        #expect(again == "sample-access-2")
        #expect(identity.refreshCount == 1)
    }

    @Test func requestsThatAskAtOnceShareOneRefresh() async throws {
        let account = session()
        try await account.signIn(identityToken: appleToken())
        clock.now += 3600

        // Each refresh pauses for a moment, so the three requests overlap.
        identity.duringRefresh = {
            for _ in 0..<5 { await Task.yield() }
        }

        async let first = account.accessToken()
        async let second = account.accessToken()
        async let third = account.accessToken()
        let tokens = try await [first, second, third]

        #expect(tokens == ["sample-access-2", "sample-access-2", "sample-access-2"])
        #expect(identity.refreshCount == 1)
    }

    @Test func aSessionTheBackendEndedSignsTheUserOut() async throws {
        let store = MemorySessionStore()
        let account = session(store: store)
        try await account.signIn(identityToken: appleToken())
        identity.endSession(refreshToken: "sample-refresh-1")
        clock.now += 3600

        await #expect(throws: PhotoBackendError.notSignedIn) {
            try await account.accessToken()
        }
        #expect(account.state == .signedOut)
        #expect(store.session == nil)
    }

    @Test func aBackendFailureDuringARefreshKeepsTheUserSignedIn() async throws {
        let store = MemorySessionStore()
        let account = session(store: store)
        try await account.signIn(identityToken: appleToken())
        clock.now += 3600
        identity.failure = .unavailable(status: 503)

        await #expect(throws: IdentityError.unavailable(status: 503)) {
            try await account.accessToken()
        }
        #expect(account.state == .signedIn(userID: "apple-user-1"))
        #expect(store.session != nil)

        // The next request tries again and works.
        identity.failure = nil
        let retried = try await account.accessToken()
        #expect(retried == "sample-access-2")
    }

    @Test func aRefreshThatCannotBeSavedStillGivesTheToken() async throws {
        let store = MemorySessionStore()
        let account = session(store: store)
        try await account.signIn(identityToken: appleToken())
        clock.now += 3600
        store.failsSaves = true

        let token = try await account.accessToken()
        #expect(token == "sample-access-2")
        #expect(store.session?.tokens.accessToken == "sample-access-1")
        #expect(account.state == .signedIn(userID: "apple-user-1"))
    }

    // MARK: Signing out

    @Test func signingOutForgetsTheSessionAndEndsItOnTheBackend() async throws {
        let store = MemorySessionStore()
        let account = session(store: store)
        try await account.signIn(identityToken: appleToken())

        await account.signOut()

        #expect(account.state == .signedOut)
        #expect(store.session == nil)
        #expect(identity.liveRefreshTokens.isEmpty)
        await #expect(throws: PhotoBackendError.notSignedIn) {
            try await account.accessToken()
        }
    }

    @Test func signingOutWorksWhenTheBackendCannotBeReached() async throws {
        let store = MemorySessionStore()
        let account = session(store: store)
        try await account.signIn(identityToken: appleToken())
        identity.failure = .unavailable(status: 503)

        await account.signOut()

        #expect(account.state == .signedOut)
        #expect(store.session == nil)
    }

    @Test func aSignOutDuringARefreshStands() async throws {
        let store = MemorySessionStore()
        let account = session(store: store)
        try await account.signIn(identityToken: appleToken())
        clock.now += 3600
        identity.duringRefresh = { await account.signOut() }

        await #expect(throws: PhotoBackendError.notSignedIn) {
            try await account.accessToken()
        }
        #expect(account.state == .signedOut)
        #expect(store.session == nil)
    }
}

/// The Keychain, on the simulator.
@MainActor
struct KeychainSessionStoreTests {
    private let session = StoredSession(
        userID: "apple-user-1",
        tokens: SessionTokens(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        )
    )

    @Test func aSessionIsSavedReplacedAndCleared() throws {
        // Its own name, so a test never touches a real sign in.
        let store = KeychainSessionStore(service: "com.finalapproach.app.tests.\(UUID().uuidString)")
        defer { try? store.clear() }

        #expect(try store.load() == nil)

        try store.save(session)
        #expect(try store.load() == session)

        var renewed = session
        renewed.tokens.accessToken = "access-2"
        try store.save(renewed)
        #expect(try store.load() == renewed)

        try store.clear()
        #expect(try store.load() == nil)
        // Clearing an empty store is not an error.
        try store.clear()
    }

    @Test func storesWithDifferentNamesDoNotShare() throws {
        let beta = KeychainSessionStore(service: "com.finalapproach.app.tests.\(UUID().uuidString)")
        let prod = KeychainSessionStore(service: "com.finalapproach.app.tests.\(UUID().uuidString)")
        defer {
            try? beta.clear()
            try? prod.clear()
        }

        try beta.save(session)

        #expect(try prod.load() == nil)
        #expect(try beta.load() == session)
    }
}
