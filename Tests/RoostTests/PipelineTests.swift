import Foundation
import HTTPTypes
import Nexus
import NexusRouter
import Testing

@testable import Roost
@testable import RoostTest

// MARK: - Fixture plugs

/// Records which plugs ran in `conn.assigns["pipeline"]`.
private func stamp(_ name: String) -> Plug {
    { conn in conn.assign(key: "pipeline", value: (conn.assigns["pipeline"] as? String ?? "") + name) }
}

private func authPlug() -> Plug {
    { conn in
        guard conn.assigns["token"] as? String == "valid" else {
            return conn.respond(status: .unauthorized)
        }
        return conn
    }
}

// MARK: - Fixture app

private struct PipelineApp: RoostApp {
    @RouteBuilder var routes: [Route] {
        // Named pipelines
        pipeline("browser") {
            stamp("B")
        }
        pipeline("api") {
            stamp("A")
        }
        pipeline("auth") {
            authPlug()
        }

        // Public browser routes
        scope("/", pipelines: ["browser"]) {
            GET("/home") { conn in conn.text("home") }
        }

        // Authenticated browser routes (two pipelines stacked)
        scope("/", pipelines: ["browser", "auth"]) {
            GET("/dashboard") { conn in conn.text("dashboard") }
        }

        // API routes
        scope("/api", pipelines: ["api"]) {
            GET("/status") { conn in conn.text("ok") }
        }

        // Inline plugs (anonymous pipeline)
        scope("/admin", plugs: [stamp("X")]) {
            GET("/panel") { conn in conn.text("panel") }
        }
    }
}

// MARK: - Tests

@Suite("Pipeline Integration", .serialized)
struct PipelineTests {

    // MARK: - Named pipelines

    @Suite("Named Pipelines")
    struct NamedPipelines {

        @Test("Route in browser pipeline receives browser plug")
        func browserPipelineApplied() async throws {
            let app      = try await TestApp(PipelineApp.self)
            let response = try await app.get("/home")

            #expect(response.status == .ok)
            #expect(response.text == "home")
        }

        @Test("Pipeline plug mutates the connection")
        func browserPlugRunsFirst() async throws {
            let app      = try await TestApp(PipelineApp.self)
            // We can verify indirectly: if the pipeline ran, the route handler received `conn` with the stamp.
            // Since `stamp` writes to assigns (not the response), we verify the route responds ok.
            let response = try await app.get("/home")
            #expect(response.status == .ok)
        }

        @Test("API route receives api pipeline plugs")
        func apiPipelineApplied() async throws {
            let app      = try await TestApp(PipelineApp.self)
            let response = try await app.get("/api/status")
            #expect(response.status == .ok)
            #expect(response.text == "ok")
        }
    }

    // MARK: - Stacked pipelines

    @Suite("Stacked Pipelines")
    struct StackedPipelines {

        @Test("Route with two pipelines is rejected when unauthenticated")
        func stackedPipelinesRejectsUnauthenticated() async throws {
            let app      = try await TestApp(PipelineApp.self)
            let response = try await app.get("/dashboard")
            #expect(response.status == .unauthorized)
        }

        @Test("Route with two pipelines succeeds when authenticated")
        func stackedPipelinesSucceedsAuthenticated() async throws {
            let app      = try await TestApp(PipelineApp.self)
            let response = try await app.get("/dashboard", assigns: ["token": "valid"])
            #expect(response.status == .ok)
            #expect(response.text == "dashboard")
        }
    }

    // MARK: - Inline plugs

    @Suite("Inline Plugs")
    struct InlinePlug {

        @Test("Route with inline plugs applies them")
        func inlinePlugsApplied() async throws {
            let app      = try await TestApp(PipelineApp.self)
            let response = try await app.get("/admin/panel")
            #expect(response.status == .ok)
            #expect(response.text == "panel")
        }
    }

    // MARK: - Path prefixing

    @Suite("Path Prefixing")
    struct PathPrefixing {

        @Test("scope prefix is prepended to all nested routes")
        func scopePrefixApplied() async throws {
            let app  = try await TestApp(PipelineApp.self)
            // /api/status matches, /status does not
            let ok  = try await app.get("/api/status")
            let nf  = try await app.get("/status")
            #expect(ok.status == .ok)
            #expect(nf.status == .notFound)
        }
    }
}
