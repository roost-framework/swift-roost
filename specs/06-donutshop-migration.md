# Spec: Migrate DonutShop to Roost

**Status:** Proposed
**Date:** 2026-03-28
**Depends on:** All previous specs (01–05)

---

## 1. Goal

Migrate DonutShop from manually wiring Spectro + Nexus + ESW + Hummingbird
to using Roost as its single dependency. This is the proof that the
framework works — if DonutShop gets simpler and nothing breaks, Roost
delivers on its promise.

This is not a feature spec. It's a validation exercise. Every line of
boilerplate that survives the migration is a framework failure.

---

## 2. Scope

### 2.1 Package.swift: Before → After

**Before (6 dependencies, 6 products):**
```swift
dependencies: [
    .package(url: "...hummingbird.git", from: "2.0.0"),
    .package(path: "../Spectro"),
    .package(path: "../Nexus"),
    .package(path: "../esw"),
],
targets: [
    .executableTarget(
        name: "DonutShop",
        dependencies: [
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "SpectroKit", package: "Spectro"),
            .product(name: "Nexus", package: "Nexus"),
            .product(name: "NexusRouter", package: "Nexus"),
            .product(name: "NexusHummingbird", package: "Nexus"),
            .product(name: "ESW", package: "esw"),
        ],
        plugins: [
            .plugin(name: "ESWBuildPlugin", package: "esw"),
        ]
    ),
]
```

**After (1 dependency, 1 product + 1 plugin):**
```swift
dependencies: [
    .package(path: "../Roost"),
    .package(path: "../esw"),  // still needed for ESWBuildPlugin
],
targets: [
    .executableTarget(
        name: "DonutShop",
        dependencies: [
            .product(name: "Roost", package: "Roost"),
        ],
        plugins: [
            .plugin(name: "ESWBuildPlugin", package: "esw"),
        ]
    ),
]
```

### 2.2 App.swift: Before → After

**Before (~122 lines):**
- 7 imports
- Manual SpectroClient creation with env vars
- DB wrapper struct
- Admin auth setup
- 3 routers (api, html, main)
- Manual pipeline construction
- Manual NexusHummingbirdAdapter
- Manual Hummingbird Application
- Manual shutdown lifecycle
- Custom responseTimer plug

**After (~25 lines):**
```swift
import Roost

@main
struct DonutShop: RoostApp {
    var database: Database? {
        Database.postgres(database: "donut_shop")
    }

    var plugs: [Plug] {
        [requestId(), responseTimer(), requestLogger(), corsPlug(CORSConfig(allowedOrigin: "*"))]
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

### 2.3 Route Files

Remove `db: DB` parameter from all route functions. Replace `db.repo()` calls
with `conn.repo()`.

**Before:**
```swift
func donutRoutes(db: DB) -> [Route] {
    GET("/") { conn in
        let donuts = try await db.repo().all(Donut.self)
```

**After:**
```swift
func donutRoutes() -> [Route] {
    GET("/") { conn in
        let donuts = try await conn.repo().all(Donut.self)
```

### 2.4 Model Files

Replace `import Spectro` with `import Roost`. Everything else stays.

### 2.5 Delete Dead Code

- Remove `DB` struct (replaced by `conn.repo()`)
- Remove `Helpers.swift` if `encodeJSON` is no longer used (Encodable schemas)
- Remove `setupDatabase()` (replaced by Spectro migrations)
- Remove `responseTimer()` (now built-in)

### 2.6 Tests

Update test target to depend on `RoostTest`. Rewrite integration tests
to use `TestApp`:

```swift
@Test func listDonuts() async throws {
    let app = try await TestApp(DonutShop.self,
        database: .postgres(database: "donut_shop_test"))

    let response = try await app.get("/api/v1/donuts")
    #expect(response.status == .ok)
}
```

---

## 3. Metrics

Track these before/after the migration:

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| `App.swift` lines | 122 | ? | < 30 |
| Import statements (App.swift) | 7 | 1 | 1 |
| Dependencies in Package.swift | 4 | 1–2 | <= 2 |
| Custom infra code (DB, helpers) | ~15 lines | 0 | 0 |
| Route function parameters | `db: DB` on all | none | 0 |
| Total `.swift` files changed | — | ? | — |

---

## 4. Acceptance Criteria

- [ ] DonutShop depends on `Roost` (and `esw` for plugin only)
- [ ] `App.swift` is < 30 lines
- [ ] `import Roost` is the only import in `App.swift`
- [ ] No `DB` struct, no `Helpers.swift`, no `setupDatabase()`
- [ ] All route functions take zero infrastructure parameters
- [ ] Route handlers access database via `conn.repo()`
- [ ] All existing API endpoints return the same responses
- [ ] `test.sh` passes with no changes to curl commands
- [ ] `swift build` succeeds with zero warnings
- [ ] `swift test` passes all existing and new tests
- [ ] App boots with: `Roost running on http://127.0.0.1:8080`
- [ ] Health endpoint still returns `requestId` and `visits` cookie

---

## 5. Non-goals

- No new features. This is a pure migration.
- No route changes, no new endpoints.
- No database schema changes.
- If something can't be migrated cleanly, document it as a framework gap — don't hack around it.
