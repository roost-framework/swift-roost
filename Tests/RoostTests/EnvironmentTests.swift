import Testing
@testable import Roost

@Suite("Environment")
struct EnvironmentTests {
    @Test func defaultsToDevWhenUnset() {
        // ROOST_ENV is not set in the test process by default
        // so Roost.env should fall back to .dev
        #expect(Roost.env == .dev)
    }

    @Test func environmentRawValues() {
        #expect(Environment(rawValue: "dev") == .dev)
        #expect(Environment(rawValue: "test") == .test)
        #expect(Environment(rawValue: "prod") == .prod)
        #expect(Environment(rawValue: "staging") == nil)
        #expect(Environment(rawValue: "") == nil)
    }

    @Test func environmentIsSendable() {
        let env: any Sendable = Environment.dev
        #expect(env is Environment)
    }
}
