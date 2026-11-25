import Foundation
import Testing

@testable import FinalApproach

/// The words around signing in a test account.
@MainActor
struct TestAccountTests {
    @Test func aNameAndAPasswordAreBothNeededToSend() {
        #expect(TestAccountSignInView.canSend(name: "test-one", password: "long-password"))
        #expect(TestAccountSignInView.canSend(name: " test-one ", password: " "))
        #expect(!TestAccountSignInView.canSend(name: "", password: "long-password"))
        #expect(!TestAccountSignInView.canSend(name: "   ", password: "long-password"))
        #expect(!TestAccountSignInView.canSend(name: "test-one", password: ""))
    }

    @Test func eachKindOfFailureHasItsOwnWords() {
        let refused = TestAccountSignInView.message(for: IdentityError.credentialsRefused)
        let notReady = TestAccountSignInView.message(for: IdentityError.testAccountNotReady)
        let down = TestAccountSignInView.message(for: IdentityError.unavailable(status: 503))
        let turnedOff = TestAccountSignInView.message(
            for: IdentityError.refused(status: 400, name: "InvalidParameterException")
        )
        let other = TestAccountSignInView.message(
            for: IdentityError.refused(status: 400, name: "TooManyRequestsException")
        )
        let offline = TestAccountSignInView.message(for: URLError(.notConnectedToInternet))

        #expect(refused == "That name and password did not match a test account.")
        #expect(Set([refused, notReady, down, turnedOff, other]).count == 5)
        #expect(offline == other)
        // No message says whether the name or the password was the wrong one.
        #expect(!refused.contains("name is") && !refused.contains("password is"))
    }

    @Test func profileSaysHowTheUserSignedIn() {
        #expect(AccountSection.signedInWith(testAccount: false) == "With Apple")
        #expect(AccountSection.signedInWith(testAccount: true) == "With a test account")
    }

    @Test func theSampleServiceKnowsThePreviewsTestAccount() async throws {
        let sync = SyncCoordinator.preview(.signedOut)
        let model = SampleData.model()

        try await sync.signIn(
            testAccount: SampleData.testAccountName,
            password: SampleData.testAccountPassword,
            on: model
        )

        #expect(sync.session.state == .signedIn(userID: SampleData.testAccountName))
        #expect(sync.session.isTestAccount)
    }
}
