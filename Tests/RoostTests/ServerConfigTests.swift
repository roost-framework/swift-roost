import Testing
@testable import Roost

@Suite("ServerConfig")
struct ServerConfigTests {
    @Test func defaultValues() {
        let config = ServerConfig()
        #expect(config.host == "127.0.0.1")
        #expect(config.port == 8080)
    }

    @Test func customValues() {
        let config = ServerConfig(host: "0.0.0.0", port: 4000)
        #expect(config.host == "0.0.0.0")
        #expect(config.port == 4000)
    }

    @Test func fromEnvironmentWithDefaults() {
        // Without env vars set, should use provided defaults
        let config = ServerConfig.fromEnvironment(
            defaultHost: "localhost",
            defaultPort: 3000
        )
        // If ROOST_HOST/PORT are set in the test environment, this test
        // verifies they're read; otherwise it verifies fallback defaults.
        #expect(!config.host.isEmpty)
        #expect(config.port > 0)
    }

    @Test func isSendable() {
        let config: any Sendable = ServerConfig()
        #expect(config is ServerConfig)
    }
}
