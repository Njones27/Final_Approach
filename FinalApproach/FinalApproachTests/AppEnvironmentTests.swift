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
}
