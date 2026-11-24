import Foundation

/// Signs a user in against the backend's Cognito user pool.
///
/// The pool has no passwords in use. The app proves who the user is with
/// the identity token from Sign in with Apple, and the pool checks that
/// token itself. The steps are in `docs/backend.md`.
///
/// Nothing here is signed with AWS keys. The pool's sign in calls are open
/// to an app that knows the app client id, which ships inside the app.
struct CognitoIdentityService: IdentityService {
    /// The pool's address for this build, from `AppEnvironment`.
    let baseURL: URL
    /// The id the pool gave the app.
    let clientID: String
    let transport: any HTTPTransport
    var now: () -> Date = { Date() }

    /// The key the backend reads the identity token under at sign up.
    static let signUpTokenKey = "identityToken"
    /// The name of the one challenge the pool sets.
    static let challengeName = "CUSTOM_CHALLENGE"

    func signIn(userID: String, identityToken: String) async throws -> SessionTokens {
        try await signUp(userID: userID, identityToken: identityToken)

        let started = try await answer(to: "InitiateAuth", [
            "AuthFlow": "CUSTOM_AUTH",
            "ClientId": clientID,
            "AuthParameters": ["USERNAME": userID],
        ])
        guard started.challengeName == Self.challengeName, let session = started.session else {
            throw IdentityError.unreadableAnswer
        }

        let finished: AuthAnswer
        do {
            finished = try await answer(to: "RespondToAuthChallenge", [
                "ChallengeName": Self.challengeName,
                "ClientId": clientID,
                "Session": session,
                "ChallengeResponses": ["USERNAME": userID, "ANSWER": identityToken],
            ])
        } catch IdentityError.refused(_, let name) where name == "NotAuthorizedException" {
            throw IdentityError.tokenRefused
        }
        guard let result = finished.result, let refreshToken = result.refreshToken else {
            throw IdentityError.unreadableAnswer
        }
        return tokens(from: result, refreshToken: refreshToken)
    }

    func refresh(_ tokens: SessionTokens) async throws -> SessionTokens {
        let renewed: AuthAnswer
        do {
            renewed = try await answer(to: "InitiateAuth", [
                "AuthFlow": "REFRESH_TOKEN_AUTH",
                "ClientId": clientID,
                "AuthParameters": ["REFRESH_TOKEN": tokens.refreshToken],
            ])
        } catch IdentityError.refused(_, let name) where Self.endedSessionNames.contains(name) {
            throw IdentityError.sessionEnded
        }
        guard let result = renewed.result else { throw IdentityError.unreadableAnswer }
        // A refresh keeps the refresh token unless the pool sends a new one.
        return self.tokens(from: result, refreshToken: result.refreshToken ?? tokens.refreshToken)
    }

    func signOut(_ tokens: SessionTokens) async throws {
        _ = try await send("RevokeToken", ["ClientId": clientID, "Token": tokens.refreshToken])
    }

    // MARK: Steps

    /// Makes the user's account on a first sign in. The pool lets a new user
    /// in only with a valid token from Apple for the same user.
    private func signUp(userID: String, identityToken: String) async throws {
        do {
            _ = try await send("SignUp", [
                "ClientId": clientID,
                "Username": userID,
                "Password": Self.throwawayPassword(),
                "ValidationData": [["Name": Self.signUpTokenKey, "Value": identityToken]],
            ])
        } catch IdentityError.refused(_, let name) where name == "UsernameExistsException" {
            // The user has signed in before, so there is nothing to make.
        } catch IdentityError.refused(_, let name) where name == "UserLambdaValidationException" {
            throw IdentityError.tokenRefused
        }
    }

    /// A password the pool's rules accept. A sign up must carry one, but the
    /// app client allows no sign in by password, so it can never be used. It
    /// is made here and kept nowhere.
    static func throwawayPassword() -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let random = (0..<40).map { _ in letters.randomElement() ?? "x" }
        // The ending makes sure every kind of character the rules ask for is there.
        return String(random) + "aA1!"
    }

    private func tokens(from result: AuthAnswer.Result, refreshToken: String) -> SessionTokens {
        SessionTokens(
            accessToken: result.accessToken,
            refreshToken: refreshToken,
            accessTokenExpiresAt: now().addingTimeInterval(TimeInterval(result.expiresIn))
        )
    }

    // MARK: Sending

    /// What the pool says when a refresh token no longer works.
    private static let endedSessionNames: Set<String> = [
        "NotAuthorizedException", "UserNotFoundException", "RefreshTokenReuseException",
    ]

    private func answer(to operation: String, _ body: [String: Any]) async throws -> AuthAnswer {
        let data = try await send(operation, body)
        guard let answer = try? JSONDecoder().decode(AuthAnswer.self, from: data) else {
            throw IdentityError.unreadableAnswer
        }
        return answer
    }

    /// Sends one call. The tokens travel in the body and never in the
    /// address, so they do not end up in a log of requests.
    private func send(_ operation: String, _ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.\(operation)", forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.problem(status: response.statusCode, body: data)
        }
        return data
    }

    /// What a refusal means. The pool names each kind of refusal, and the
    /// app reads the name and never the message.
    static func problem(status: Int, body: Data) -> IdentityError {
        if status >= 500 { return .unavailable(status: status) }
        let answer = try? JSONDecoder().decode(ProblemAnswer.self, from: body)
        return .refused(status: status, name: answer?.name ?? "")
    }
}

// MARK: - What comes back over the wire

private struct AuthAnswer: Decodable {
    struct Result: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "AccessToken"
            case expiresIn = "ExpiresIn"
            case refreshToken = "RefreshToken"
        }
    }

    let challengeName: String?
    let session: String?
    let result: Result?

    private enum CodingKeys: String, CodingKey {
        case challengeName = "ChallengeName"
        case session = "Session"
        case result = "AuthenticationResult"
    }
}

private struct ProblemAnswer: Decodable {
    let type: String?

    private enum CodingKeys: String, CodingKey {
        case type = "__type"
    }

    /// The kind of refusal. The pool sometimes writes a prefix and a hash
    /// sign before the name.
    var name: String {
        guard let type else { return "" }
        return type.split(separator: "#").last.map(String.init) ?? ""
    }
}
