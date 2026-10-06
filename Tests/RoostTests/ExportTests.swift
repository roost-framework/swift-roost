import Testing
import Roost

@Suite("Exports")
struct ExportTests {
    @Test func nexusTypesAccessible() {
        // Connection is from Nexus core
        let _: Connection.Type = Connection.self
        // Plug is from Nexus
        let _: Plug.Type = Plug.self
    }

    @Test func nexusRouterTypesAccessible() {
        // Router is from NexusRouter
        let _: Router.Type = Router.self
        // Route is from NexusRouter
        let _: Route.Type = Route.self
    }

    @Test func httpTypesAccessible() {
        // HTTPRequest is from swift-http-types
        let _: HTTPRequest.Type = HTTPRequest.self
        let _: HTTPResponse.Type = HTTPResponse.self
    }

    @Test func roostAppProtocolAccessible() {
        let _: any RoostApp.Type = MinimalApp.self
    }
}

/// Minimal conformance to verify the protocol compiles with only `routes`.
private struct MinimalApp: RoostApp {
    @RouteBuilder var routes: [Route] {
        GET("/") { conn in
            conn
        }
    }
}
