# Testing browser workflows

Keep cookies across requests, submit CSRF-protected forms, and model separate readers.

## Overview

Create a ``TestBrowser`` with `app.browser()`. Each instance has an independent
cookie jar. It stores response cookies and sends them on the next request.
Redirects are returned to the test rather than followed automatically.

### Build a small fixture

This self-contained fixture exposes its token as JSON to keep the test focused.
In an application workflow, get the token from the rendered form instead.

```swift
import Roost

struct BrowserExample: RoostApp {
    let sessionStore: (any SessionStore)? = MemorySessionStore()
    var plugs: [Plug] { browserPlugs() }

    @RouteBuilder var routes: [Route] {
        GET("/csrf", MessageController.self, .token)
        POST("/message", MessageController.self, .create)
        GET("/message", MessageController.self, .show)
    }
}

struct MessageParams: Codable, Sendable {
    let message: String
}

struct MessageController: Controller {
    enum Action: String, ControllerAction { case token, create, show }

    static func action(_ action: Action) -> Plug {
        switch action {
        case .token: token
        case .create: create
        case .show: show
        }
    }

    static func token(_ conn: Connection) async throws -> Connection {
        try conn.json(value: ["token": conn.csrfToken])
    }

    static func create(_ conn: Connection) async throws -> Connection {
        let params = try conn.permit(MessageParams.self)
        return conn.putSessionValue("message", params.message).redirect(to: "/message")
    }

    static func show(_ conn: Connection) async throws -> Connection {
        conn.text(conn.sessionValue("message") as? String ?? "")
    }
}
```

### Follow the form and redirect

```swift
import Testing
import RoostTest

@Test func browserKeepsItsSession() async throws {
    let app = try await TestApp(BrowserExample.self)
    let reader = app.browser()
    let anotherReader = app.browser()

    let page = try await reader.get("/csrf")
    let token = try #require(page.json["token"] as? String)
    let saved = try await reader.post("/message", form: [
        "_csrf_token": token,
        "message": "Hello, Roost."
    ])
    #expect(saved.status == .seeOther)
    #expect(saved.header("Location") == "/message")

    let next = try await reader.get("/message")
    #expect(next.text == "Hello, Roost.")
    let separate = try await anotherReader.get("/message")
    #expect(separate.text.isEmpty)
    await app.shutdown()
}
```

The token and cookie belong to the same browser. Session persistence has already
completed when the request returns; the test needs no delay or manual flush.

### Extend it to authentication

For an authenticated resource test, fetch the registration or login form,
submit its token and credentials, assert the redirect, then fetch the resource
page. Exercise a second browser to confirm that it cannot read, change, or
delete the first user's records.

Also check a missing or invalid token, invalid field values, the 422 response,
retained form input, flash delivery, and logout. A successful page load alone
does not cover those transitions.

Browser JavaScript and layout remain outside this in-process helper's scope.
Use a real browser when testing the rendered UI.
