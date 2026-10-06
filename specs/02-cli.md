# Spec: Roost CLI

**Status:** Proposed
**Date:** 2026-03-28
**Depends on:** Roost core framework (spec 01)

---

## 1. Goal

A `roost` CLI that scaffolds new projects and generates code. This is what
makes the framework productive — `mix phx.new` is why people reach for Phoenix.
The CLI embodies the "no boilerplate" promise: you type a command, you get a
working app or a complete CRUD feature.

---

## 2. Commands

### 2.1 `roost new <AppName>`

Generates a new Roost project:

```bash
$ roost new DonutShop
  Creating DonutShop...
    create  DonutShop/Package.swift
    create  DonutShop/Sources/DonutShop/App.swift
    create  DonutShop/Sources/DonutShop/Routes/.gitkeep
    create  DonutShop/Sources/DonutShop/Models/.gitkeep
    create  DonutShop/Sources/DonutShop/Views/layout.esw
    create  DonutShop/Sources/Migrations/.gitkeep
    create  DonutShop/Tests/DonutShopTests/.gitkeep
    create  DonutShop/.gitignore
    create  DonutShop/.swift-format
  Done. Next steps:
    cd DonutShop
    swift run
```

The generated `App.swift`:

```swift
import Roost

@main
struct DonutShop: RoostApp {
    let database = Database.postgres(database: "donut_shop")

    @RouteBuilder var routes: [Route] {
        GET("/") { conn in
            try conn.json(value: ["message": "Welcome to DonutShop"])
        }
    }
}
```

Options:
- `--no-db` — omit database configuration
- `--no-esw` — omit Views directory and ESW plugin

### 2.2 `roost gen.schema <Name> <field:type>...`

Generates a model, migration, and optionally routes:

```bash
$ roost gen.schema Donut name:string price:double is_available:bool category_id:uuid:references
  create  Sources/DonutShop/Models/Donut.swift
  create  Sources/Migrations/20260328190000_CreateDonuts.sql
```

Generated model:

```swift
import Roost

@Schema("donuts")
struct Donut {
    @ID var id: UUID
    @Column var name: String
    @Column var price: Double
    @Column var isAvailable: Bool
    @ForeignKey var categoryId: UUID
    @Timestamp var createdAt: Date
}
```

Generated migration:

```sql
-- migrate:up
CREATE TABLE "donuts" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "price" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "is_available" BOOLEAN NOT NULL DEFAULT true,
    "category_id" UUID NOT NULL REFERENCES "categories"("id"),
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- migrate:down
DROP TABLE "donuts";
```

Field type mappings:

| CLI Type | Swift Type | Postgres Type |
|----------|-----------|---------------|
| `string` | `String` | `TEXT` |
| `int` | `Int` | `INT` |
| `double` | `Double` | `DOUBLE PRECISION` |
| `bool` | `Bool` | `BOOLEAN` |
| `uuid` | `UUID` | `UUID` |
| `date` | `Date` | `TIMESTAMPTZ` |

Modifiers:
- `:references` on a uuid field → adds `REFERENCES` FK constraint, generates `@ForeignKey` instead of `@Column`
- `:optional` → makes the field `T?` and removes `NOT NULL`

### 2.3 `roost gen.json <Name> <field:type>...`

Same as `gen.schema` plus generates JSON API routes:

```bash
$ roost gen.json Donut name:string price:double
  create  Sources/DonutShop/Models/Donut.swift
  create  Sources/DonutShop/Routes/DonutRoutes.swift
  create  Sources/Migrations/20260328190000_CreateDonuts.sql
```

Generated routes file:

```swift
import Roost

@RouteBuilder
func donutRoutes() -> [Route] {
    GET("/") { conn in
        let donuts = try await conn.repo().all(Donut.self)
        try conn.json(encodable: donuts)
    }

    GET("/:id") { conn in
        guard let id = conn.params["id"].flatMap(UUID.init) else {
            throw NexusHTTPError(.badRequest, message: "Invalid ID")
        }
        guard let donut = try await conn.repo().get(Donut.self, id: id) else {
            throw NexusHTTPError(.notFound, message: "Donut not found")
        }
        try conn.json(encodable: donut)
    }

    POST("/") { conn in
        let input = try conn.decode(as: CreateDonutInput.self)
        var donut = Donut()
        donut.name = input.name
        donut.price = input.price
        let created = try await conn.repo().insert(donut)
        try conn.json(status: .created, encodable: created)
    }

    DELETE("/:id") { conn in
        guard let id = conn.params["id"].flatMap(UUID.init) else {
            throw NexusHTTPError(.badRequest, message: "Invalid ID")
        }
        try await conn.repo().delete(Donut.self, id: id)
        try conn.json(value: ["deleted": true])
    }
}

private struct CreateDonutInput: Decodable, Sendable {
    let name: String
    let price: Double
}
```

### 2.4 `roost gen.html <Name> <field:type>...`

Same as `gen.json` plus generates `.esw` templates:

```bash
$ roost gen.html Donut name:string price:double
  create  Sources/DonutShop/Models/Donut.swift
  create  Sources/DonutShop/Routes/DonutRoutes.swift
  create  Sources/DonutShop/Views/donut_list.esw
  create  Sources/DonutShop/Views/donut_detail.esw
  create  Sources/DonutShop/Views/_donut_card.esw
  create  Sources/Migrations/20260328190000_CreateDonuts.sql
```

Routes use `respondTo(html:json:)` for content negotiation.

### 2.5 `roost migrate <up|down|status>`

Delegates to Spectro's migration system:

```bash
$ roost migrate up       # runs pending migrations
$ roost migrate down     # rolls back last migration
$ roost migrate status   # shows applied/pending
```

Reads database config from the same env vars as the app.

### 2.6 `roost server`

Builds and runs the app:

```bash
$ roost server            # swift run with defaults
$ roost server --port 4000
```

---

## 3. Terminal UI — Noora

All CLI output uses [Noora](https://github.com/tuist/Noora) for polished
terminal UI, consistent with Spectro's CLI. Define a `RoostUI` helper
(same pattern as Spectro's `SpectroUI`):

```swift
// Sources/RoostCLI/Utils/RoostUI.swift
@preconcurrency import Noora

enum RoostUI {
    static let noora = Noora(theme: Theme(
        primary: "F97316",    // roost orange
        secondary: "FB923C",
        muted: "6B7280",
        accent: "F59E0B",
        danger: "EF4444",
        success: "10B981",
        info: "3B82F6",
        selectedRowText: "FFFFFF",
        selectedRowBackground: "7C2D12"
    ))
}
```

Usage in commands:

```swift
// Success
RoostUI.noora.success(.alert(
    "Project \(.primary(appName)) created",
    takeaways: [
        "cd \(.command(appName))",
        "swift run",
    ]
))

// File creation
RoostUI.noora.info(.alert(
    "create \(.muted(filePath))"
))

// Errors
RoostUI.noora.error(.alert(
    "Failed to generate \(.primary(name))",
    takeaways: ["\(.muted("\(error)"))"]
))
```

---

## 4. Package Structure

```swift
// In Package.swift, add:
.executableTarget(
    name: "RoostCLI",
    dependencies: [
        "Roost",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Noora", package: "Noora"),
    ]
)
```

Dependencies to add:

```swift
.package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
.package(url: "https://github.com/tuist/Noora", .upToNextMajor(from: "0.15.0")),
```

Distribute via Mint:

```
# Mintfile
roost-framework/swift-roost
```

```bash
mint install roost-framework/swift-roost
```

---

## 5. Acceptance Criteria

- [ ] All CLI output uses Noora (no raw `print` statements)
- [ ] `RoostUI` follows same pattern as Spectro's `SpectroUI`
- [ ] `roost new AppName` generates a buildable project that runs on first `swift run`
- [ ] Generated `App.swift` is <15 lines and uses `RoostApp` protocol
- [ ] `roost gen.schema` generates `@Schema` model + SQL migration
- [ ] All field types map correctly (string, int, double, bool, uuid, date)
- [ ] `:references` modifier generates FK constraint and `@ForeignKey` wrapper
- [ ] `:optional` modifier generates optional Swift type and drops `NOT NULL`
- [ ] `roost gen.json` generates model + migration + CRUD routes
- [ ] `roost gen.html` generates model + migration + routes + `.esw` templates
- [ ] `roost migrate up/down/status` delegates to Spectro's migration system
- [ ] `roost server` builds and runs the app
- [ ] CLI uses ArgumentParser with `--help` on every command
- [ ] CLI prints file paths as it creates them (like Rails generators)
- [ ] Generated code compiles under Swift 6 strict concurrency
- [ ] No hardcoded paths — CLI discovers project structure from `Package.swift`
- [ ] `roost new --no-db` omits database config and SpectroKit dependency
- [ ] Installable via Mint

---

## 6. Non-goals

- No interactive prompts (fully non-interactive CLI).
- No database creation command (use `createdb` or Spectro's `spectro database create`).
- No live reload / file watcher.
- No deployment commands.
- No OpenAPI/Swagger generation.
