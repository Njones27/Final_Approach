import Foundation

/// The backend's own tokens for one signed in user.
struct SessionTokens: Codable, Equatable {
    /// Sent with every request to the API. It works for a short time.
    var accessToken: String
    /// Trades for a new access token, so Apple's sheet is not shown again
    /// until the user signs out.
    var refreshToken: String
    var accessTokenExpiresAt: Date
}

/// Why signing in, or staying signed in, did not work.
enum IdentityError: Error, Equatable {
    /// The backend did not accept the identity token from Apple.
    case tokenRefused
    /// The saved sign in no longer works, so the user must sign in again.
    case sessionEnded
    /// The backend refused for a reason the app does not act on. The name
    /// is for logs and is never shown to the user.
    case refused(status: Int, name: String)
    /// The backend failed. The same request may work later.
    case unavailable(status: Int)
    /// The answer was not in the form the app expects.
    case unreadableAnswer
}

/// Signs a user in to the backend with the identity token from Sign in with
/// Apple. It sits behind a protocol so the app can be previewed and tested
/// with no backend.
protocol IdentityService {
    /// Signs in the user Apple named. A first sign in also makes their
    /// account.
    func signIn(userID: String, identityToken: String) async throws -> SessionTokens
    /// Trades the refresh token for a new access token.
    func refresh(_ tokens: SessionTokens) async throws -> SessionTokens
    /// Ends the session on the backend, so its refresh token stops working.
    func signOut(_ tokens: SessionTokens) async throws
}
