# Spec: Testing Support

**Status:** Proposed
**Date:** 2026-03-28
**Depends on:** Roost core framework (spec 01), NexusTest (complete)

---

## 1. Goal

Make testing a Roost app as frictionless as building one. Today, testing a
Nexus pipeline requires manually constructing `TestConnection` objects, building
request objects by hand, and asserting on raw connection state. Roost should
provide a test DSL that reads like a conversation:

```swift
@Test func listDonuts() async throws {
    let app = try await TestApp(DonutShop.self)

    let response = try await app.get("/api/v1/donuts")

    #expect(response.status == .ok)
    #expect(response.json["donuts"] != nil)
}
```

No server started. No ports allocated. No database needed for pure pipeline
tests. Just: build request → run through pipeline → assert on response.

---

## 2. Scope

### 2.1 `TestApp`

A test harness that instantiates a `RoostApp` and runs requests through
its pipeline without starting Hummingbird:

```swift
// Sources/RoostTest/TestApp.swift
public struct TestApp<App: RoostApp> {
    private let app: App
    private let plug: Plug

    public init(_ type: App.Type) async throws {
        self.app = App()
        // Build the same pipeline as main() but skip server boot
        self.plug = rescueErrors(
            pipeline(app.plugs + [{ conn in try await router(conn) }])
        )
    }
}
```

### 2.2 Request Methods

```swift
extension TestApp {
    /// GET request
    public func get(
        _ path: String,
        headers: [String: String] = [:]
    ) async throws -> TestResponse

    /// POST request with JSON body
    public func post(
        _ path: String,
        json: [String: Any],
        headers: [String: String] = [:]
    ) async throws -> TestResponse

    /// PUT request with JSON body
    public func put(
        _ path: String,
        json: [String: Any],
        headers: [String: String] = [:]
    ) async throws -> TestResponse

    /// DELETE request
    public func delete(
        _ path: String,
        headers: [String: String] = [:]
    ) async throws -> TestResponse

    /// Generic request for custom methods
    public func request(
        method: HTTPRequest.Method,
        path: String,
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> TestResponse
}
```

### 2.3 `TestResponse`

A response wrapper with convenient assertion helpers:

```swift
public struct TestResponse: Sendable {
    /// HTTP status code
    public let status: HTTPResponse.Status

    /// Response headers
    public let headers: HTTPFields

    /// Raw body data
    public let body: Data

    /// Body as UTF-8 string
    public var text: String { String(data: body, encoding: .utf8) ?? "" }

    /// Body parsed as JSON dictionary
    public var json: [String: Any] { ... }

    /// Body decoded as Decodable type
    public func decode<T: Decodable>(as type: T.Type) throws -> T

    /// Header value by name
    public func header(_ name: String) -> String?

    /// All cookies set in response
    public var cookies: [String: String]
}
```

### 2.4 Database Testing Modes

Two modes for tests that need a database:

**Mode A — Real database (integration tests):**
```swift
let app = try await TestApp(DonutShop.self, database: .postgres(database: "donut_shop_test"))
```

**Mode B — No database (pipeline tests):**
```swift
let app = try await TestApp(DonutShop.self, database: nil)
```

When `database: nil`, route handlers that call `conn.repo()` will crash —
that's intentional. Pipeline-only tests shouldn't touch the database.

### 2.5 Request Context Helpers

Inject assigns or session data into test requests:

```swift
let response = try await app.get("/admin/dashboard",
    assigns: ["current_user": adminUser],
    session: ["user_id": "123"]
)
```

### 2.6 Package Target

```swift
// New product in Roost's Package.swift
.library(name: "RoostTest", targets: ["RoostTest"]),

// New target
.target(
    name: "RoostTest",
    dependencies: [
        "Roost",
        .product(name: "NexusTest", package: "swift-nexus"),
    ]
)
```

Consumer adds to their test target:

```swift
.testTarget(
    name: "DonutShopTests",
    dependencies: [
        .product(name: "RoostTest", package: "swift-roost"),
    ]
)
```

---

## 3. Acceptance Criteria

- [ ] `TestApp` can be initialized from any `RoostApp` conformance
- [ ] Requests run through the full plug pipeline without starting a server
- [ ] `get`, `post`, `put`, `delete` convenience methods work
- [ ] `TestResponse` exposes `status`, `headers`, `body`, `text`, `json`
- [ ] `TestResponse.decode(as:)` decodes JSON response into `Decodable` type
- [ ] `TestResponse.header(_:)` returns response header values
- [ ] `TestResponse.cookies` parses `Set-Cookie` headers
- [ ] Database can be overridden to test database or nil
- [ ] Assigns and session data can be injected into test requests
- [ ] No ports are opened during tests
- [ ] All types compile under Swift 6 strict concurrency
- [ ] Tests for the test framework itself: GET returns 200, POST with JSON body, 404 on missing route, pipeline plugs execute in order

---

## 4. Non-goals

- No browser/UI testing.
- No snapshot testing.
- No mocking framework — use Swift Testing's built-in capabilities.
- No test database migration runner (use `roost migrate` before test run).
- No parallel test isolation (each test manages its own database state).
