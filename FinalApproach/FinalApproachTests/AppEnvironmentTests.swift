import Testing

@testable import FinalApproach

@MainActor
struct AppEnvironmentTests {
    @Test func everyEnvironmentHasADisplayName() {
        #expect(AppEnvironment.dev.displayName == "Development")
        #expect(AppEnvironment.beta.displayName == "Beta")
        #expect(AppEnvironment.prod.displayName == "Production")
    }

    @Test func rawValuesMatchTheBuildSetting() {
        #expect(AppEnvironment(rawValue: "beta") == .beta)
        #expect(AppEnvironment(rawValue: "prod") == .prod)
        #expect(AppEnvironment(rawValue: "staging") == nil)
    }

    @Test func anAppClientIDIsLettersAndDigitsOnly() {
        #expect(AppEnvironment.clientID(from: "1gcjpq4tk9nbt575ki8bqkn8d6") == "1gcjpq4tk9nbt575ki8bqkn8d6")
        #expect(AppEnvironment.clientID(from: "") == nil)
        #expect(AppEnvironment.clientID(from: "client id") == nil)
        #expect(AppEnvironment.clientID(from: "client-id") == nil)
        #expect(AppEnvironment.clientID(from: "$(AUTH_CLIENT_ID)") == nil)
    }
}
