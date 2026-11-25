import Foundation
import Testing

@testable import FinalApproach

/// Signing in against the backend's user pool.
@MainActor
struct CognitoIdentityServiceTests {
    private let base = URL(string: "https://cognito-idp.example.test")!
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func service(_ transport: ScriptedTransport) -> CognitoIdentityService {
        let fixed = clock
        return CognitoIdentityService(baseURL: base, clientID: "client-1", transport: transport, now: { fixed })
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    private func object(_ data: Data?) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: try #require(data))
        return try #require(value as? [String: Any])
    }

    private func refusal(_ name: String) throws -> ScriptedTransport.Answer {
        .init(status: 400, body: try json(["__type": name, "message": "Not for the app to read."]))
    }

    private func challenge() throws -> ScriptedTransport.Answer {
        .init(body: try json([
            "ChallengeName": "CUSTOM_CHALLENGE",
            "Session": "session-1",
            "ChallengeParameters": ["challenge": "APPLE_IDENTITY_TOKEN"],
        ]))
    }

    private func issued(refreshToken: String? = "refresh-1") throws -> ScriptedTransport.Answer {
        var result: [String: Any] = [
            "AccessToken": "access-1", "IdToken": "id-1", "ExpiresIn": 3600, "TokenType": "Bearer",
        ]
        if let refreshToken { result["RefreshToken"] = refreshToken }
        return .init(body: try json(["AuthenticationResult": result]))
    }

    /// An answer that holds an empty object.
    private let empty = ScriptedTransport.Answer(body: Data("{}".utf8))

    private func target(_ request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: "X-Amz-Target")
    }

    private let saved = SessionTokens(
        accessToken: "access-0",
        refreshToken: "refresh-0",
        accessTokenExpiresAt: Date(timeIntervalSince1970: 1_799_999_000)
    )

    // MARK: Signing in

    @Test func aFirstSignInMakesTheAccountThenAnswersTheChallengeWithApplesToken() async throws {
        let transport = ScriptedTransport([.init(body: try json(["UserConfirmed": true])), try challenge(), try issued()])

        let tokens = try await service(transport).signIn(userID: "apple-user-1", identityToken: "apple-token")

        #expect(tokens == SessionTokens(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            accessTokenExpiresAt: clock.addingTimeInterval(3600)
        ))
        #expect(transport.requests.map { target($0) } == [
            "AWSCognitoIdentityProviderService.SignUp",
            "AWSCognitoIdentityProviderService.InitiateAuth",
            "AWSCognitoIdentityProviderService.RespondToAuthChallenge",
        ])
        for request in transport.requests {
            #expect(request.httpMethod == "POST")
            #expect(request.url == base)
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-amz-json-1.1")
            // The pool's sign in calls carry no token in a header.
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }

        let signUp = try object(transport.requests[0].httpBody)
        #expect(signUp["ClientId"] as? String == "client-1")
        #expect(signUp["Username"] as? String == "apple-user-1")
        let validation = try #require(signUp["ValidationData"] as? [[String: String]])
        #expect(validation == [["Name": "identityToken", "Value": "apple-token"]])

        let start = try object(transport.requests[1].httpBody)
        #expect(start["AuthFlow"] as? String == "CUSTOM_AUTH")
        #expect(start["ClientId"] as? String == "client-1")
        #expect(start["AuthParameters"] as? [String: String] == ["USERNAME": "apple-user-1"])

        let finish = try object(transport.requests[2].httpBody)
        #expect(finish["ChallengeName"] as? String == "CUSTOM_CHALLENGE")
        #expect(finish["Session"] as? String == "session-1")
        #expect(finish["ChallengeResponses"] as? [String: String] == ["USERNAME": "apple-user-1", "ANSWER": "apple-token"])
    }

    @Test func aUserWhoSignedInBeforeIsNotMadeAgain() async throws {
        let transport = ScriptedTransport([try refusal("UsernameExistsException"), try challenge(), try issued()])

        let tokens = try await service(transport).signIn(userID: "apple-user-1", identityToken: "apple-token")

        #expect(tokens.accessToken == "access-1")
        #expect(transport.requests.count == 3)
    }

    @Test func aTokenTheBackendTurnsAwayAtSignUpStopsTheSignIn() async throws {
        let transport = ScriptedTransport([try refusal("UserLambdaValidationException")])

        await #expect(throws: IdentityError.tokenRefused) {
            try await service(transport).signIn(userID: "apple-user-1", identityToken: "old-token")
        }
        #expect(transport.requests.count == 1)
    }

    @Test func aTokenTheBackendTurnsAwayAtTheChallengeIsRefused() async throws {
        let transport = ScriptedTransport([
            try refusal("UsernameExistsException"), try challenge(), try refusal("NotAuthorizedException"),
        ])

        await #expect(throws: IdentityError.tokenRefused) {
            try await service(transport).signIn(userID: "apple-user-1", identityToken: "someone-elses-token")
        }
    }

    @Test func anAnswerWithNoChallengeOrNoTokensIsUnreadable() async throws {
        let noChallenge = ScriptedTransport([empty, empty])
        await #expect(throws: IdentityError.unreadableAnswer) {
            try await service(noChallenge).signIn(userID: "apple-user-1", identityToken: "apple-token")
        }

        let noTokens = ScriptedTransport([empty, try challenge(), empty])
        await #expect(throws: IdentityError.unreadableAnswer) {
            try await service(noTokens).signIn(userID: "apple-user-1", identityToken: "apple-token")
        }

        // A sign in must come with a refresh token, or the user would be
        // asked to sign in again within the hour.
        let noRefresh = ScriptedTransport([empty, try challenge(), try issued(refreshToken: nil)])
        await #expect(throws: IdentityError.unreadableAnswer) {
            try await service(noRefresh).signIn(userID: "apple-user-1", identityToken: "apple-token")
        }

        let notJSON = ScriptedTransport([empty, .init(body: Data("not json".utf8))])
        await #expect(throws: IdentityError.unreadableAnswer) {
            try await service(notJSON).signIn(userID: "apple-user-1", identityToken: "apple-token")
        }
    }

    // MARK: Signing in a test account

    @Test func aTestAccountSignsInWithOneRequestThatCarriesItsNameAndPassword() async throws {
        let transport = ScriptedTransport([try issued()])

        let tokens = try await service(transport).signIn(testAccount: "test-one", password: "long-password")

        #expect(tokens.accessToken == "access-1")
        #expect(tokens.refreshToken == "refresh-1")
        #expect(tokens.accessTokenExpiresAt == clock.addingTimeInterval(3600))
        #expect(transport.requests.count == 1)
        #expect(target(transport.requests[0]) == "AWSCognitoIdentityProviderService.InitiateAuth")
        let sent = try object(transport.requests[0].httpBody)
        #expect(sent["AuthFlow"] as? String == "USER_PASSWORD_AUTH")
        #expect(sent["ClientId"] as? String == "client-1")
        #expect(sent["AuthParameters"] as? [String: String] == ["USERNAME": "test-one", "PASSWORD": "long-password"])
        // The password travels in the body and never in the address.
        #expect(transport.requests[0].url == base)
    }

    @Test func aWrongPasswordOrAnUnknownNameIsRefusedTheSameWay() async throws {
        for name in ["NotAuthorizedException", "UserNotFoundException"] {
            let transport = ScriptedTransport([try refusal(name)])
            await #expect(throws: IdentityError.credentialsRefused) {
                try await service(transport).signIn(testAccount: "test-one", password: "wrong")
            }
        }
    }

    @Test func aTestAccountWhosePasswordWasNotSetForGoodIsNotReady() async throws {
        let transport = ScriptedTransport([
            .init(body: try json(["ChallengeName": "NEW_PASSWORD_REQUIRED", "Session": "session-1"])),
        ])

        await #expect(throws: IdentityError.testAccountNotReady) {
            try await service(transport).signIn(testAccount: "test-one", password: "first-password")
        }
        #expect(transport.requests.count == 1)
    }

    @Test func aBackendWithTestAccountsTurnedOffKeepsItsRefusalsName() async throws {
        let transport = ScriptedTransport([try refusal("InvalidParameterException")])

        await #expect(throws: IdentityError.refused(status: 400, name: "InvalidParameterException")) {
            try await service(transport).signIn(testAccount: "test-one", password: "long-password")
        }
    }

    @Test func aTestAccountSignInWithNoTokensIsUnreadable() async throws {
        let noTokens = ScriptedTransport([empty])
        await #expect(throws: IdentityError.unreadableAnswer) {
            try await service(noTokens).signIn(testAccount: "test-one", password: "long-password")
        }

        let noRefresh = ScriptedTransport([try issued(refreshToken: nil)])
        await #expect(throws: IdentityError.unreadableAnswer) {
            try await service(noRefresh).signIn(testAccount: "test-one", password: "long-password")
        }
    }

    @Test func aRefusalTheAppDoesNotActOnKeepsItsName() async throws {
        let transport = ScriptedTransport([try refusal("TooManyRequestsException")])

        await #expect(throws: IdentityError.refused(status: 400, name: "TooManyRequestsException")) {
            try await service(transport).signIn(userID: "apple-user-1", identityToken: "apple-token")
        }
    }

    @Test func aBackendFailureIsUnavailable() async throws {
        let transport = ScriptedTransport([.init(status: 503)])

        await #expect(throws: IdentityError.unavailable(status: 503)) {
            try await service(transport).signIn(userID: "apple-user-1", identityToken: "apple-token")
        }
    }

    @Test func theThrowawayPasswordMeetsThePoolsRulesAndIsNeverTheSame() {
        let first = CognitoIdentityService.throwawayPassword()
        let second = CognitoIdentityService.throwawayPassword()

        #expect(first != second)
        #expect(first.count >= 40)
        #expect(first.contains(where: { $0.isLowercase }))
        #expect(first.contains(where: { $0.isUppercase }))
        #expect(first.contains(where: { $0.isNumber }))
        #expect(first.contains("!"))
        #expect(first.allSatisfy { $0.isASCII })
    }

    // MARK: Refreshing

    @Test func aRefreshTradesTheRefreshTokenAndKeepsIt() async throws {
        let transport = ScriptedTransport([try issued(refreshToken: nil)])

        let tokens = try await service(transport).refresh(saved)

        #expect(tokens == SessionTokens(
            accessToken: "access-1",
            refreshToken: "refresh-0",
            accessTokenExpiresAt: clock.addingTimeInterval(3600)
        ))
        let request = try #require(transport.requests.first)
        #expect(target(request) == "AWSCognitoIdentityProviderService.InitiateAuth")
        let body = try object(request.httpBody)
        #expect(body["AuthFlow"] as? String == "REFRESH_TOKEN_AUTH")
        #expect(body["ClientId"] as? String == "client-1")
        #expect(body["AuthParameters"] as? [String: String] == ["REFRESH_TOKEN": "refresh-0"])
    }

    @Test func aRefreshTakesANewRefreshTokenWhenOneIsSent() async throws {
        let transport = ScriptedTransport([try issued(refreshToken: "refresh-2")])

        let tokens = try await service(transport).refresh(saved)

        #expect(tokens.refreshToken == "refresh-2")
    }

    @Test(arguments: ["NotAuthorizedException", "UserNotFoundException", "com.amazonaws.cognito#NotAuthorizedException"])
    func aRefreshTokenThatNoLongerWorksEndsTheSession(name: String) async throws {
        let transport = ScriptedTransport([try refusal(name)])

        await #expect(throws: IdentityError.sessionEnded) {
            try await service(transport).refresh(saved)
        }
    }

    @Test func aBackendFailureDuringARefreshDoesNotEndTheSession() async throws {
        let transport = ScriptedTransport([.init(status: 500)])

        await #expect(throws: IdentityError.unavailable(status: 500)) {
            try await service(transport).refresh(saved)
        }
    }

    // MARK: Signing out

    @Test func signingOutRevokesTheRefreshToken() async throws {
        let transport = ScriptedTransport([empty])

        try await service(transport).signOut(saved)

        let request = try #require(transport.requests.first)
        #expect(transport.requests.count == 1)
        #expect(target(request) == "AWSCognitoIdentityProviderService.RevokeToken")
        let body = try object(request.httpBody)
        #expect(body["ClientId"] as? String == "client-1")
        #expect(body["Token"] as? String == "refresh-0")
    }
}

/// The in memory identity service follows the real one's rules.
@MainActor
struct SampleIdentityServiceTests {
    @Test func aSignedOutSessionCannotBeRefreshed() async throws {
        let service = SampleIdentityService()
        let tokens = try await service.signIn(userID: "apple-user-1", identityToken: "apple-token")

        let renewed = try await service.refresh(tokens)
        #expect(renewed.refreshToken == tokens.refreshToken)
        #expect(renewed.accessToken != tokens.accessToken)

        try await service.signOut(tokens)
        await #expect(throws: IdentityError.sessionEnded) {
            try await service.refresh(tokens)
        }
    }

    @Test func anEmptyTokenIsRefused() async throws {
        let service = SampleIdentityService()

        await #expect(throws: IdentityError.tokenRefused) {
            try await service.signIn(userID: "apple-user-1", identityToken: "")
        }
        #expect(service.userIDs.isEmpty)
    }
}
