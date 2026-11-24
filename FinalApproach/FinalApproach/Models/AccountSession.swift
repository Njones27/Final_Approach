import FinalApproachCore
import Foundation
import Observation

/// Whether someone is signed in, and the token their requests carry.
///
/// The sign in is kept in the Keychain between launches. The access token
/// works for a short time, and this type trades the refresh token for a new
/// one when it is about to run out. Many requests can ask for a token at
/// once, and they share one refresh.
@Observable
final class AccountSession {
    enum State: Equatable {
        case signedOut
        case signedIn(userID: String)
    }

    private(set) var state: State = .signedOut

    @ObservationIgnored private let identity: (any IdentityService)?
    @ObservationIgnored private let store: any SessionStore
    @ObservationIgnored private let now: () -> Date
    /// An access token with less than this long left is replaced before use,
    /// so it cannot run out on its way to the backend.
    @ObservationIgnored private let refreshMargin: TimeInterval
    @ObservationIgnored private var stored: StoredSession?
    @ObservationIgnored private var refreshing: Task<SessionTokens, any Error>?

    /// Pass no identity service for a build that has no backend. Such a
    /// build cannot sign in.
    init(
        identity: (any IdentityService)?,
        store: any SessionStore,
        refreshMargin: TimeInterval = 120,
        now: @escaping () -> Date = { Date() }
    ) {
        self.identity = identity
        self.store = store
        self.refreshMargin = refreshMargin
        self.now = now
        // With no backend there is nothing a saved sign in could be used for.
        if identity != nil, let saved = try? store.load() {
            stored = saved
            state = .signedIn(userID: saved.userID)
        }
    }

    /// False in a build with no backend, where signing in is not offered.
    var canSignIn: Bool { identity != nil }

    var isSignedIn: Bool { stored != nil }

    /// Signs in with the identity token from Sign in with Apple.
    ///
    /// The user's id is read from the token, and the backend checks that the
    /// token is real. The sign in is saved before it counts, so the app never
    /// shows a signed in user it would forget on the next launch.
    func signIn(identityToken: String) async throws {
        guard let identity else { throw PhotoBackendError.notSignedIn }
        guard let userID = IdentityToken.subject(of: identityToken) else {
            throw IdentityError.tokenRefused
        }
        let tokens = try await identity.signIn(userID: userID, identityToken: identityToken)
        let session = StoredSession(userID: userID, tokens: tokens)
        try store.save(session)
        stored = session
        state = .signedIn(userID: userID)
    }

    /// Signs out on this device at once, and then tells the backend so the
    /// refresh token stops working. The backend is told on a best effort
    /// basis, because the user must be able to sign out with no network.
    func signOut() async {
        guard let session = stored else { return }
        forget()
        do {
            try await identity?.signOut(session.tokens)
        } catch {
            #if DEBUG
            print("AccountSession: The backend was not told about the sign out. \(error)")
            #endif
        }
    }

    /// The token to send with a request to the API.
    ///
    /// It throws `PhotoBackendError.notSignedIn` when no one is signed in or
    /// the saved sign in no longer works. Any other error means the backend
    /// could not be reached, and the user stays signed in.
    func accessToken() async throws -> String {
        guard let session = stored else { throw PhotoBackendError.notSignedIn }
        if session.tokens.accessTokenExpiresAt.timeIntervalSince(now()) > refreshMargin {
            return session.tokens.accessToken
        }
        return try await refreshed(session).accessToken
    }

    // MARK: Refreshing

    /// One refresh, shared by every caller that asks while it runs.
    private func refreshed(_ session: StoredSession) async throws -> SessionTokens {
        if let refreshing {
            return try await refreshing.value
        }
        let task = Task { () throws -> SessionTokens in
            defer { self.refreshing = nil }
            guard let identity = self.identity else { throw PhotoBackendError.notSignedIn }
            let tokens: SessionTokens
            do {
                tokens = try await identity.refresh(session.tokens)
            } catch IdentityError.sessionEnded {
                // The user signed out elsewhere, or the account is gone.
                if self.stored == session { self.forget() }
                throw PhotoBackendError.notSignedIn
            }
            // The user may have signed out, or signed in again, while the
            // refresh was on its way. Their change stands.
            guard self.stored == session else { throw PhotoBackendError.notSignedIn }
            let renewed = StoredSession(userID: session.userID, tokens: tokens)
            self.stored = renewed
            // A failed save costs one more refresh on the next launch.
            try? self.store.save(renewed)
            return tokens
        }
        refreshing = task
        return try await task.value
    }

    private func forget() {
        stored = nil
        state = .signedOut
        do {
            try store.clear()
        } catch {
            #if DEBUG
            print("AccountSession: The saved sign in could not be removed. \(error)")
            #endif
        }
    }
}
