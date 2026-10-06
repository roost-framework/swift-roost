import Foundation
import HTTPTypes
import Nexus
import NexusRouter
import NexusTest
import RoostTest
import Testing

@testable import Roost

private struct SessionUser: Authenticatable {
    let authID = "user-42"
}

private struct SessionLifecycleApp: RoostApp {
    static let store = MemorySessionStore()

    var plugs: [Plug] {
        [
            session(store: Self.store),
            { conn in
                conn.registerBeforeSend { result in
                    result.putRespHeader(HTTPField.Name("X-Before-Send")!, "preserved")
                }
            },
        ]
    }

    @RouteBuilder var routes: [Route] {
        POST("/login") { conn in
            let (loggedIn, token) = conn.loginUser(SessionUser())
            return loggedIn.text(token)
        }

        DELETE("/logout") { conn in
            conn.logoutUser().text("logged out")
        }

        GET("/session") { conn in
            try conn.json(value: [
                "user_id": conn.authUserID ?? "",
                "token": conn.authSessionToken ?? "",
                "theme": conn.sessionValue("theme") as? String ?? "",
            ])
        }

        GET("/error") { _ in
            throw NexusHTTPError(.badRequest, message: "expected failure")
        }
    }
}

private struct ConfiguredSessionApp: RoostApp {
    static let store = MemorySessionStore()
    var sessionStore: SessionStore? { Self.store }
    var plugs: [Plug] { [] }
    var routes: [Route] { SessionLifecycleApp().routes }
}

private struct FailingSessionStore: SessionStore {
    enum Operation: Sendable, CaseIterable { case read, write, delete }
    struct Unavailable: Error {}
    let operation: Operation

    func get(_ id: String) async throws -> [String: any Sendable]? {
        if operation == .read { throw Unavailable() }
        return ["theme": "dark"]
    }

    func set(_ id: String, data: [String: any Sendable], ttl: Duration?) async throws {
        if operation == .write { throw Unavailable() }
    }

    func delete(_ id: String) async throws {
        if operation == .delete { throw Unavailable() }
    }
}

@Suite("Session lifecycle")
struct SessionLifecycleTests {
    @Test("TestApp installs the app's sessionStore and persists a fresh login")
    func configuredSessionStore() async throws {
        let app = try await TestApp(ConfiguredSessionApp.self)
        let login = try await app.post("/login", json: [String: String]())
        let sessionID = try #require(login.cookies[defaultSessionCookie])
        let next = try await app.get("/session", headers: ["Cookie": "\(defaultSessionCookie)=\(sessionID)"])
        #expect(next.json["user_id"] as? String == "user-42")
        #expect(next.json["token"] as? String == login.text)
    }

    @Test("login persists identity before the next request and rotates the old session")
    func loginPersistsAcrossRequests() async throws {
        let app = try await TestApp(SessionLifecycleApp.self)
        let oldID = UUID().uuidString
        try await SessionLifecycleApp.store.set(oldID, data: ["theme": "dark"], ttl: nil)

        let login = try await app.post("/login", json: [String: String](), headers: ["Cookie": "\(defaultSessionCookie)=\(oldID)"])
        let newID = try #require(login.cookies[defaultSessionCookie])
        #expect(newID != oldID)
        #expect(!login.text.isEmpty)

        let next = try await app.get("/session", headers: ["Cookie": "\(defaultSessionCookie)=\(newID)"])
        #expect(next.json["user_id"] as? String == "user-42")
        #expect(next.json["token"] as? String == login.text)
        #expect(next.json["theme"] as? String == "dark")
        #expect(try await SessionLifecycleApp.store.get(oldID) == nil)
    }

    @Test("logout persists removal of authentication on the next request")
    func logoutPersistsAcrossRequests() async throws {
        let app = try await TestApp(SessionLifecycleApp.self)
        let sessionID = UUID().uuidString
        try await SessionLifecycleApp.store.set(sessionID, data: [
            "_roost_user_id": "user-42",
            "_roost_auth_token": "token",
            "theme": "dark",
        ], ttl: nil)
        let headers = ["Cookie": "\(defaultSessionCookie)=\(sessionID)"]

        let logout = try await app.delete("/logout", headers: headers)
        #expect(logout.status == .ok)

        let next = try await app.get("/session", headers: headers)
        #expect(next.json["user_id"] as? String == "")
        #expect(next.json["token"] as? String == "")
        #expect(next.json["theme"] as? String == "dark")
    }

    @Test("error responses preserve hooks registered by earlier plugs")
    func errorsPreserveBeforeSend() async throws {
        let app = try await TestApp(SessionLifecycleApp.self)
        let response = try await app.get("/error")

        #expect(response.status == .badRequest)
        #expect(response.header("X-Before-Send") == "preserved")
        #expect(response.cookies[defaultSessionCookie] != nil)
    }

    @Test("store failures return an error before emitting a session cookie", arguments: FailingSessionStore.Operation.allCases)
    private func storeFailures(operation: FailingSessionStore.Operation) async throws {
        let handle = roost_requestPipeline([
            { conn in
                conn.registerBeforeSend { result in
                    result.putRespHeader(HTTPField.Name("X-Final-Status")!, "\(result.response.status.code)")
                }
            },
            session(store: FailingSessionStore(operation: operation)),
            { conn in
                if operation == .delete { return conn.clearSessionID().text("cleared") }
                return conn.loginUser(SessionUser()).0.text("logged in")
            },
        ])
        let conn = TestConnection.build(headers: [.cookie: "\(defaultSessionCookie)=existing"])
        let response = try await handle(conn).runBeforeSend()

        #expect(response.response.status == .internalServerError)
        #expect(response.isHalted)
        #expect(response.response.headerFields[.setCookie] == nil)
        #expect(response.response.headerFields[HTTPField.Name("X-Final-Status")!] == "500")
    }

    @Test("halted requests persist sessions and preserve unrelated cookies")
    func haltedRequestPersists() async throws {
        let store = MemorySessionStore()
        let handle = roost_requestPipeline([
            session(store: store, cookieName: "custom_session"),
            { conn in
                conn.putSessionValue("return_to", "/dashboard")
                    .putRespHeader(.setCookie, "preference=dark; Path=/")
                    .redirect(to: "/login")
            },
            { conn in
                Issue.record("The halted pipeline must not call this plug")
                return conn
            },
        ])
        let response = try await handle(TestConnection.build()).runBeforeSend()
        #expect(response.isHalted)
        let cookies = response.response.headerFields.filter { $0.name == .setCookie }.map(\.value)
        #expect(cookies.contains("preference=dark; Path=/"))
        let cookie = try #require(cookies.first { $0.hasPrefix("custom_session=") })
        let sessionID = String(cookie.split(separator: ";")[0].split(separator: "=", maxSplits: 1)[1])
        #expect(try await store.get(sessionID)?["return_to"] as? String == "/dashboard")
    }

    @Test("custom error pages keep completed plug state and halt downstream processing")
    func customErrorsKeepState() async throws {
        let store = MemorySessionStore()
        let handle = roost_requestPipeline([
            session(store: store),
            { conn in
                conn.putSessionValue("theme", "dark")
                    .registerBeforeSend { result in
                        let count = result.response.headerFields[HTTPField.Name("X-Hook-Count")!].flatMap(Int.init) ?? 0
                        return result.putRespHeader(HTTPField.Name("X-Hook-Count")!, "\(count + 1)")
                    }
            },
            { _ in throw NexusHTTPError(.badRequest, message: "expected failure") },
            { conn in
                Issue.record("The pipeline must halt after a custom error response")
                return conn
            },
        ], customErrorPage: { conn, _, _ in
            // Deliberately leave isHalted unchanged: rescue must enforce the halt.
            var response = conn
            response.response.status = .badRequest
            response.responseBody = .buffered(Data("custom error".utf8))
            return response
        })

        let response = try await handle(TestConnection.build()).runBeforeSend().runBeforeSend()
        #expect(response.response.status == .badRequest)
        #expect(response.sessionValue("theme") as? String == "dark")
        #expect(response.response.headerFields[HTTPField.Name("X-Hook-Count")!] == "1")
        let cookie = try #require(response.response.headerFields[.setCookie])
        let sessionID = String(cookie.split(separator: ";")[0].split(separator: "=", maxSplits: 1)[1])
        #expect(try await store.get(sessionID)?["theme"] as? String == "dark")
    }
}
