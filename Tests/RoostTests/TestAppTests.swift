import Foundation
import HTTPTypes
import Nexus
import NexusRouter
import Testing

@testable import Roost
@testable import RoostTest

// MARK: - Fixture App

private struct FixtureApp: RoostApp {
    var plugs: [Plug] {
        [
            { conn in return conn.assign(key: "plug_order", value: "first") },
            { conn in
                let existing = conn.assigns["plug_order"] as? String ?? ""
                return conn.assign(key: "plug_order", value: existing + ",second")
            },
        ]
    }

    @RouteBuilder var routes: [Route] {
        GET("/") { conn in
            return conn.text("Hello from Roost")
        }

        GET("/json") { conn in
            return try conn.json(value: ["message": "ok"])
        }

        POST("/echo") { conn in
            let input = try conn.decode(as: [String: String].self)
            return try conn.json(value: input)
        }

        GET("/assigns") { conn in
            let order = conn.assigns["plug_order"] as? String ?? "none"
            return conn.text(order)
        }

        GET("/session") { conn in
            let userId = conn.getSession("user_id") ?? "anonymous"
            return conn.text(userId)
        }

        GET("/header-check") { conn in
            let value = conn.getReqHeader(HTTPField.Name("X-Custom")!) ?? "missing"
            return conn.text(value)
        }

        GET("/set-cookie") { conn in
            return conn.putRespHeader(HTTPField.Name("Set-Cookie")!, "token=abc123; Path=/; HttpOnly")
                .text("ok")
        }
    }
}

// MARK: - Tests

@Suite("TestApp")
struct TestAppTests {

    @Test func getReturns200() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.get("/")

        #expect(response.status == .ok)
        #expect(response.text == "Hello from Roost")
    }

    @Test func getJSON() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.get("/json")

        #expect(response.status == .ok)
        #expect(response.json["message"] as? String == "ok")
    }

    @Test func postWithJSONBody() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.post("/echo", json: ["name": "donut"])

        #expect(response.status == .ok)
        let decoded = try response.decode(as: [String: String].self)
        #expect(decoded["name"] == "donut")
    }

    @Test func missingRouteReturns404() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.get("/nonexistent")

        #expect(response.status == .notFound)
    }

    @Test func plugsExecuteInOrder() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.get("/assigns")

        #expect(response.text == "first,second")
    }

    @Test func sessionInjection() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.get(
            "/session",
            session: ["user_id": "42"]
        )

        #expect(response.text == "42")
    }

    @Test func assignsInjection() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.get(
            "/assigns",
            assigns: ["plug_order": "injected"]
        )

        // Injected assigns are set before plugs run, so plugs overwrite them
        // This verifies the pipeline runs after injection
        #expect(response.text.contains("first"))
    }

    @Test func customHeaders() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.get(
            "/header-check",
            headers: ["X-Custom": "hello"]
        )

        #expect(response.text == "hello")
    }

    @Test func responseHeaders() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.get("/json")

        #expect(response.header("Content-Type") == "application/json")
    }

    @Test func cookies() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.get("/set-cookie")

        #expect(response.cookies["token"] == "abc123")
    }

    @Test func deleteMethod() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.delete("/nonexistent")

        #expect(response.status == .notFound)
    }

    @Test func testResponseText() async throws {
        let app = try await TestApp(FixtureApp.self)
        let response = try await app.get("/")

        #expect(response.text == "Hello from Roost")
        #expect(!response.body.isEmpty)
    }
}
