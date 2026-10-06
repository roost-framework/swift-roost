# Spec: Roost Core Framework

**Status:** Proposed
**Date:** 2026-03-28
**Depends on:** Spectro (complete), Nexus (complete), ESW (complete)

---

## 1. Goal

Roost is the top-level Swift web framework that unifies Spectro (ORM),
Nexus (HTTP pipeline), and ESW (templates) into a single dependency with
zero-boilerplate application bootstrap. Users write `import Roost`, conform
to a protocol, and have a running web app.

The design principle is the roost falcon: **small, fast, no wasted motion.**

DonutShop's `App.swift` today is 122 lines of ceremony. After Roost:

```swift
import Roost

@main
struct DonutShop: RoostApp {
    let database = Database.postgres(env: .default)

    var plugs: some PlugPipeline {
        RequestId()
        ResponseTimer()
        RequestLogger()
        CORS(origin: "*")
    }

    var routes: some RouteBuilder {
        scope("/api/v1") {
            scope("/donuts") { DonutRoutes() }
            scope("/orders") { OrderRoutes() }
        }

        scope("/admin", through: [BasicAuth(realm: "Admin")]) {
            SeedRoute()
        }
    }
}
```

~20 lines. Everything else is convention.

---

## 2. Scope

### 2.1 Package Structure

```
swift-roost/
  Package.swift
  Sources/
    Roost/              ← Main target, re-exports everything
      RoostApp.swift    ← Application protocol + runner
      Database.swift        ← Database configuration helpers
      Defaults.swift        ← Default plug pipeline, env var conventions
      Exports.swift         ← @_exported import Nexus, Spectro, ESW, etc.
  Tests/
    RoostTests/
```

### 2.2 `Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-roost",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Roost", targets: ["Roost"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Spectro-ORM/Spectro", from: "1.0.0"),
        .package(url: "https://github.com/alembic-labs/swift-nexus", from: "0.1.0"),
        .package(url: "https://github.com/alembic-labs/swift-esw", from: "0.1.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "Roost",
            dependencies: [
                .product(name: "SpectroKit", package: "Spectro"),
                .product(name: "Nexus", package: "swift-nexus"),
                .product(name: "NexusRouter", package: "swift-nexus"),
                .product(name: "NexusHummingbird", package: "swift-nexus"),
                .product(name: "NexusTest", package: "swift-nexus"),
                .product(name: "ESW", package: "swift-esw"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
    ]
)
```

### 2.3 Re-exports

```swift
// Sources/Roost/Exports.swift
@_exported import Nexus
@_exported import NexusRouter
@_exported import NexusHummingbird
@_exported import Spectro
@_exported import ESW
@_exported import HTTPTypes
```

A consumer writes `import Roost` and gets everything. No more 7-import
headers.

### 2.4 `RoostApp` Protocol

```swift
public protocol RoostApp {
    /// Database configuration. Return `nil` for apps without a database.
    var database: Database? { get }

    /// Middleware pipeline applied to every request.
    /// Default: requestId + requestLogger + rescueErrors.
    var plugs: [Plug] { get }

    /// Route definitions.
    @RouteBuilder var routes: [Route] { get }

    /// Server configuration (host, port).
    /// Default: reads from ROOST_HOST / ROOST_PORT env vars,
    /// falls back to 127.0.0.1:8080.
    var server: ServerConfig { get }

    /// Called after database is connected but before server starts.
    /// Use for seed data, cache warming, etc.
    func willStart(spectro: SpectroClient) async throws

    /// Application entry point. Default implementation provided.
    static func main() async throws
}
```

Default implementations for everything except `routes`:

```swift
extension RoostApp {
    public var database: Database? { nil }

    public var plugs: [Plug] {
        [requestId(), requestLogger()]
    }

    public var server: ServerConfig {
        ServerConfig.fromEnvironment()
    }

    public func willStart(spectro: SpectroClient) async throws {}
}
```

### 2.5 `Database` Configuration

```swift
public struct Database: Sendable {
    public let hostname: String
    public let port: Int
    public let username: String
    public let password: String
    public let database: String

    /// Reads from standard env vars: DB_HOST, DB_PORT, DB_USER,
    /// DB_PASSWORD, DB_NAME. Falls back to localhost/postgres defaults.
    public static func postgres(
        hostname: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        database: String? = nil
    ) -> Database
}
```

The env-var convention means zero config in dev — just have Postgres running
with defaults. Override individual fields when needed.

### 2.6 `ServerConfig`

```swift
public struct ServerConfig: Sendable {
    public let host: String
    public let port: Int

    public static func fromEnvironment(
        defaultHost: String = "127.0.0.1",
        defaultPort: Int = 8080
    ) -> ServerConfig

    public init(host: String = "127.0.0.1", port: Int = 8080)
}
```

### 2.7 Default `static func main()`

The default `main()` implementation:

1. Reads `database` config → creates `SpectroClient` (if non-nil)
2. Injects `SpectroClient` into pipeline via `assign("spectro", value:)`
3. Calls `willStart(spectro:)` hook
4. Builds the plug pipeline: `user plugs + rescueErrors(router)`
5. Creates `NexusHummingbirdAdapter`
6. Creates Hummingbird `Application` with `server` config
7. Prints startup banner with port
8. Runs `server.runService()`
9. Shuts down `SpectroClient` on exit

All of this is what DonutShop does manually today in 100+ lines.

### 2.8 Built-in `ResponseTimer` Plug

Move DonutShop's `responseTimer()` into Nexus or Roost as a built-in plug.
It measures request duration and sets `X-Response-Time` header via
`registerBeforeSend`. This is universally useful.

### 2.9 Typed Database Access

Roost provides a typed assign key and convenience accessor:

```swift
public enum SpectroKey: AssignKey {
    public typealias Value = SpectroClient
}

extension Connection {
    public var spectro: SpectroClient { self[SpectroKey.self]! }
    public func repo() -> GenericDatabaseRepo { spectro.repository() }
}
```

Route handlers use `conn.repo()` directly — no captured `db` parameter.

---

## 3. What DonutShop Becomes

```swift
import Roost

@main
struct DonutShop: RoostApp {
    let database = Database.postgres(database: "donut_shop")

    var plugs: [Plug] {
        [
            requestId(),
            responseTimer(),
            requestLogger(),
            corsPlug(CORSConfig(allowedOrigin: "*")),
        ]
    }

    @RouteBuilder var routes: [Route] {
        GET("/health") { conn in
            try conn.json(value: ["status": "ok"])
        }

        forward("/api/v1", to: Router {
            scope("/donuts") { donutRoutes() }
            scope("/orders") { orderRoutes() }
            scope("/customers") { customerRoutes() }
            scope("/analytics") { analyticsRoutes() }
        })

        scope("/admin", through: [basicAuth(realm: "Admin") { u, p in
            u == "admin" && p == "admin"
        }]) {
            seedRoute()
        }
    }
}
```

Route files simplify too — no more `db: DB` parameter threading:

```swift
// Before
func donutRoutes(db: DB) -> [Route] {
    GET("/") { conn in
        let donuts = try await db.repo().all(Donut.self)
        ...
    }
}

// After
@RouteBuilder
func donutRoutes() -> [Route] {
    GET("/") { conn in
        let donuts = try await conn.repo().all(Donut.self)
        ...
    }
}
```

---

## 4. Acceptance Criteria

- [ ] `import Roost` gives access to Nexus, NexusRouter, Spectro, ESW, and HTTPTypes
- [ ] `RoostApp` protocol compiles with only `routes` required
- [ ] Default `main()` boots Hummingbird server with the configured pipeline
- [ ] `Database.postgres()` reads from env vars with sensible defaults
- [ ] `ServerConfig.fromEnvironment()` reads `ROOST_HOST` / `ROOST_PORT`
- [ ] `conn.spectro` and `conn.repo()` are available in route handlers when database is configured
- [ ] `willStart(spectro:)` is called before server accepts connections
- [ ] `responseTimer()` plug is available as built-in
- [ ] SpectroClient is shut down cleanly on server exit
- [ ] Startup banner prints: `Roost running on http://{host}:{port}`
- [ ] DonutShop can be migrated to use `RoostApp` with <30 lines in `App.swift`
- [ ] `swift build` succeeds with zero warnings under Swift 6 strict concurrency
- [ ] All types are `Sendable`
- [ ] No `@unchecked Sendable` in the Roost target

---

## 5. Non-goals (This Spec)

- No CLI tool (`roost new`, `roost gen.*`) — that's spec 02.
- No project template generation — that's spec 02.
- No custom server backends (only Hummingbird) — extensibility later.
- No configuration file (`.roost.yml` or similar) — env vars are enough.
- No hot reload / live reload — future spec.
- No authentication framework beyond what Nexus already provides.
