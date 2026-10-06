import Roost
import RoostTest
import Testing

private struct BrowserWorkflowApp: RoostApp {
    var sessionStore: SessionStore? { MemorySessionStore() }
    var plugs: [Plug] { [bodyParser(), methodOverride(), flashPlug(), roost_csrfProtection()] }

    @RouteBuilder var routes: [Route] {
        GET("/form") { conn in
            try conn.json(value: ["csrf": conn.assigns["csrfToken"] as? String ?? "", "flash": conn.flash.info ?? ""])
        }
        POST("/form") { conn in
            conn.putFlash(.info, "Saved").redirect(to: "/form")
        }
        PUT("/form") { conn in conn.text(conn.bodyParams["title"] ?? "") }
        GET("/typed") { conn in
            conn.putSessionValue("count", 42).putSessionValue("name", "before")
                .putSession(key: "name", value: "after").text("saved")
        }
        GET("/read") { conn in
            try conn.json(value: ["count": String(conn.sessionValue("count") as? Int ?? 0), "name": conn.sessionValue("name") as? String ?? ""])
        }
    }
}

@Suite("Browser workflow")
struct BrowserWorkflowTests {
    @Test("TestBrowser preserves form sessions and isolates separate cookie jars")
    func browserHelper() async throws {
        let app = try await TestApp(BrowserWorkflowApp.self)
        let browser = app.browser()
        let other = app.browser()
        let first = try await browser.get("/form")
        let token = try #require(first.json["csrf"] as? String)
        let otherToken = try #require(try await other.get("/form").json["csrf"] as? String)
        #expect(token != otherToken)
        #expect(try await browser.post("/form", form: ["_csrf_token": token]).status == .seeOther)
        #expect(try await browser.get("/form").json["flash"] as? String == "Saved")
        #expect(try await browser.get("/form").json["flash"] as? String == "")
        #expect(try await other.post("/form", form: ["_csrf_token": token]).status == .forbidden)
        let edited = try await browser.post("/form", form: ["_method": "PUT", "_csrf_token": token, "title": "Swift + & é"])
        #expect(edited.text == "Swift + & é")
    }

    @Test("CSRF and one-time flash survive a real cookie round trip")
    func csrfAndFlash() async throws {
        let app = try await TestApp(BrowserWorkflowApp.self)
        let first = try await app.get("/form")
        let token = try #require(first.json["csrf"] as? String)
        let id = try #require(first.cookies[defaultSessionCookie])
        let headers = ["Cookie": "\(defaultSessionCookie)=\(id)", "Content-Type": "application/x-www-form-urlencoded"]
        let saved = try await app.request(method: .post, path: "/form", body: Data("_csrf_token=\(token)".utf8), headers: headers)
        #expect(saved.status == .seeOther)
        let redirected = try await app.get("/form", headers: headers)
        #expect(redirected.json["flash"] as? String == "Saved")
        let consumed = try await app.get("/form", headers: headers)
        #expect(consumed.json["flash"] as? String == "")
        let edited = try await app.request(method: .post, path: "/form", body: Data("_method=PUT&_csrf_token=\(token)&title=Hello+Swift".utf8), headers: headers)
        #expect(edited.status == .ok)
        #expect(edited.text == "Hello Swift")
    }

    @Test("JSON cookie requests require CSRF too")
    func jsonRequiresCSRF() async throws {
        let app = try await TestApp(BrowserWorkflowApp.self)
        let result = try await app.post("/form", json: ["title": "no token"])
        #expect(result.status == .forbidden)
    }

    @Test("Nexus string values and Roost typed values use the same stored session")
    func commonSession() async throws {
        let app = try await TestApp(BrowserWorkflowApp.self)
        let written = try await app.get("/typed")
        let id = try #require(written.cookies[defaultSessionCookie])
        let read = try await app.get("/read", headers: ["Cookie": "\(defaultSessionCookie)=\(id)"])
        #expect(read.json["name"] as? String == "after")
        #expect(read.json["count"] as? String == "42")
    }
}
