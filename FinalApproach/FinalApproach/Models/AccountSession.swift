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
        /// The user asked to delete their account and the backend has not
        /// confirmed it yet. Nothing is synced in this state.
        case deletingAccount(userID: String)
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
            state = Self.state(of: saved)
        }
    }

    /// False in a build with no backend, where signing in is not offered.
    var canSignIn: Bool { identity != nil }

    /// True while someone is signed in and their account is not on its way
    /// out.
    var isSignedIn: Bool {
        if case .signedIn = state { true } else { false }
    }

    /// True while a delete of the account is owed to the backend.
    var isAccountDeleteOwed: Bool { stored?.isAccountDeleteOwed == true }

    /// True while a test account is the one signed in.
    var isTestAccount: Bool { stored?.isTestAccount == true }

    /// Signs in with the identity token from Sign in with Apple.
    ///
    /// The user's id is read from the token, and the backend checks that the
    /// token is real. The sign in is saved before it counts, so the app never
    /// shows a signed in user it would forget on the next launch.
    func signIn(identityToken: String) async throws {
        guard let identity else { throw PhotoBackendError.notSignedIn }
        // A new sign in would replace the tokens the delete still needs.
        guard !isAccountDeleteOwed else { throw PhotoBackendError.accountDeleted }
        guard let userID = IdentityToken.subject(of: identityToken) else {
            throw IdentityError.tokenRefused
        }
        let tokens = try await identity.signIn(userID: userID, identityToken: identityToken)
        let session = StoredSession(userID: userID, tokens: tokens)
        try store.save(session)
        stored = session
        state = .signedIn(userID: userID)
    }

    /// Signs in a test account with its name and password.
    ///
    /// Spaces around the name are dropped, because a keyboard adds one after
    /// a suggestion. The password is sent as typed and is kept nowhere.
    func signIn(testAccount name: String, password: String) async throws {
        guard let identity else { throw PhotoBackendError.notSignedIn }
        // A new sign in would replace the tokens the delete still needs.
        guard !isAccountDeleteOwed else { throw PhotoBackendError.accountDeleted }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else { throw IdentityError.credentialsRefused }
        let tokens = try await identity.signIn(testAccount: name, password: password)
        let session = StoredSession(userID: name, tokens: tokens, isTestAccount: true)
        try store.save(session)
        stored = session
        state = .signedIn(userID: name)
    }

    /// Signs out on this device at once, and then tells the backend so the
    /// refresh token stops working. The backend is told on a best effort
    /// basis, because the user must be able to sign out with no network.
    ///
    /// It does nothing while a delete of the account is owed, because the
    /// delete needs the sign in to finish.
    func signOut() async {
        guard let session = stored, !session.isAccountDeleteOwed else { return }
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

    // MARK: Deleting the account

    /// Records that the user asked to delete their account.
    ///
    /// The request is saved before anything is removed. If the app closes or
    /// the network is down, the delete is still owed the next time the app
    /// opens. It throws when the request cannot be saved, and then nothing
    /// has changed.
    func beginAccountDelete() throws {
        guard var session = stored else { throw PhotoBackendError.notSignedIn }
        guard !session.isAccountDeleteOwed else { return }
        session.isAccountDeleteOwed = true
        try store.save(session)
        stored = session
        state = Self.state(of: session)
    }

    /// Call when the backend confirmed that the account is deleted. The
    /// sign in is forgotten. The backend is not told to end it, because the
    /// account and its tokens are already gone.
    func finishAccountDelete() {
        guard isAccountDeleteOwed else { return }
        forget()
    }

    private static func state(of session: StoredSession) -> State {
        session.isAccountDeleteOwed
            ? .deletingAccount(userID: session.userID)
            : .signedIn(userID: session.userID)
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
                if self.holds(session) { self.forget() }
                throw PhotoBackendError.notSignedIn
            }
            // The user may have signed out, or signed in again, while the
            // refresh was on its way. Their change stands.
            guard self.holds(session), var renewed = self.stored else {
                throw PhotoBackendError.notSignedIn
            }
            renewed.tokens = tokens
            self.stored = renewed
            // A failed save costs one more refresh on the next launch.
            try? self.store.save(renewed)
            return tokens
        }
        refreshing = task
        return try await task.value
    }

    /// True while the saved sign in is still the one a refresh started
    /// from. Asking to delete the account in the meantime does not change
    /// that, so the new tokens are kept for the delete to use.
    private func holds(_ session: StoredSession) -> Bool {
        stored?.userID == session.userID && stored?.tokens == session.tokens
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
