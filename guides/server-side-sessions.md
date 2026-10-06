# Server-side sessions

Configure a store on your app to enable server-side sessions:

```swift
struct MyApp: RoostApp {
    private let store = MemorySessionStore()

    var sessionStore: SessionStore? { store }

    // Routes and other configuration...
}
```

`RoostApp` and `TestApp` both install this store. Alternatively, put
`session(store: store)` in your app's plugs to customize the cookie name or TTL.
Choose one configuration method.

Session mutations belong in plugs and route handlers. `putSessionValue`,
`deleteSessionValue`, and `clearSessionID` immediately update the returned
connection, so later code in the request sees the change. Login rotates the
session ID while preserving session data; logout removes the authentication
values and current-user assigns.

The request pipeline awaits session persistence before running synchronous
response hooks and sending the response. This also applies to redirects and
other halted responses. Store failures produce error responses; a failed write
does not emit a cookie advertising an unsaved session. Error handling preserves
the connection returned by the last completed application plug, including its
response hooks.

For request tests, carry the response cookie into the next request:

```swift
let app = try await TestApp(MyApp.self)
let login = try await app.post("/login", json: credentials)
let sessionID = try #require(login.cookies[defaultSessionCookie])
let next = try await app.get("/account", headers: [
    "Cookie": "\(defaultSessionCookie)=\(sessionID)"
])
```

`TestApp` also offers `app.browser()` for a cookie-preserving browser. Create two
browsers from one app to test separate users. Tests do not need sleeps or a manual
flush. Form submissions use `browser.post("/path", form: values)`.

Nexus's string session helpers (`getSession`, `putSession`, `deleteSession`) share
the server-side store with Roost's typed helpers. CSRF and flash therefore use
the same session as authentication. `putFlash` writes immediately, so a redirect
persists its message before it returns. Include `browserPlugs()` in your app to
parse forms, support method overrides, load flash, and enforce CSRF. JSON requests
are protected by default too.

When embedding `session(store:)` directly in a Nexus pipeline outside
`RoostApp` or `TestApp`, the caller must await `connection.flushSession()`
after the request pipeline and before `runBeforeSend()`. Session persistence
no longer runs in a background task. Make session changes before flushing;
`beforeSend` callbacks are for response transformations.
