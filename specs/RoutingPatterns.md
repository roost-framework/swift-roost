# Roost Routing Patterns

## Philosophy

Roost adopts the **Rails/Phoenix approach** to routing: declarative, composable, and immutable. Routes are data structures built at compile-time, not mutable objects modified at runtime.

## Comparison with Other Frameworks

### Hummingbird (Vapor-style)

```swift
// Hummingbird: Mutable router, imperative registration
var router = Router()
router.get("/") { request, context in
    // handler
}
router.post("/items") { request, context in
    // handler
}

// Grouping requires mutable context
router.group("api/v1") { api in
    api.get("/users") { ... }  // mutations on api object
}
```

**Issues:**
- Router is mutated throughout initialization
- Order of registration matters (side effects)
- Hard to compose routes from multiple files
- Testing requires the full mutable router

### Vapor (Even more verbose)

```swift
// Vapor: Controller classes + route registration
func routes(_ app: Application) throws {
    app.get("/") { req async in
        "Hello"
    }

    // Grouping
    let api = app.grouped("api", "v1")
    api.get("users") { req in
        // handler
    }

    // Controller-based routes
    let usersController = UsersController()
    app.get("users", use: usersController.index)
    app.post("users", use: usersController.create)
}
```

**Issues:**
- Routes separated from handlers
- Controller classes require boilerplate
- App object carries mutable state
- Routes are registered imperatively

---

## Roost: The Rails/Phoenix Way

### 1. Route Functions Return Data

```swift
@RouteBuilder
func donutRoutes() -> [Route] {
    GET("/") { conn in
        // handler
    }

    POST("/") { conn in
        // handler
    }
}
```

**Benefits:**
- Routes are pure data, no side effects
- Order-independent composition
- Easy to test in isolation
- File organization matches URL structure

### 2. Composable with `scope` and `forward`

```swift
@RouteBuilder var routes: [Route] {
    // Flat routes
    GET("/health") { conn in ... }

    // Nested scope
    scope("/api/v1") {
        GET("/donuts") { ... }
        scope("/orders") { orderRoutes() }
    }

    // Forward to sub-routers
    forward("/", to: Router {
        scope("/donuts") { donutFrontendRoutes() }
        scope("/customers") { customerFrontendRoutes() }
    })
}
```

**Phoenix/Rails Equivalent:**

```elixir
# Phoenix
scope "/api/v1", MyAppWeb do
  get "/donuts", DonutController, :index
  resources "/orders", OrderController
end

scope "/" do
  pipe_through :browser
  resources "/donuts", DonutFrontendController
end
```

```ruby
# Rails
namespace :api do
  namespace :v1 do
    resources :donuts, only: [:index]
    resources :orders
  end
end

scope module: :frontend do
  resources :donuts
end
```

### 3. Controller-Free (or Optional)

No need for controller classes. Route handlers are closures:

```swift
GET("/:id") { conn in
    let id = conn.params["id"]
    let donut = try await conn.repo().get(Donut.self, id: id)
    return try conn.json(value: donut)
}
```

When you need shared logic, use functions:

```swift
func requireAdmin(_ conn: Connection) async throws -> Connection {
    guard conn.isAdmin else {
        throw NexusHTTPError(.forbidden)
    }
    return conn
}

@RouteBuilder
func adminRoutes() -> [Route] {
    scope("/admin", through: [requireAdmin]) {
        GET("/stats") { conn in ... }
        POST("/seed") { conn in ... }
    }
}
```

**Compare to Phoenix's pipeline:**

```elixir
pipeline :admin do
  plug :require_admin
end

scope "/admin", MyAppWeb do
  pipe_through :admin
  get "/stats", StatsController, :index
end
```

### 4. Frontend/API Split (Clean Architecture)

```swift
// API: JSON, no CSRF, bearer tokens
forward("/api/v1", to: Router {
    scope("/donuts") { donutApiRoutes() }
    scope("/orders") { orderApiRoutes() }
})

// Frontend: HTML, CSRF, sessions
forward("/", to: Router {
    scope("/donuts") { donutFrontendRoutes() }
    scope("/customers") { customerFrontendRoutes() }
})
```

**Benefits:**
- Clear separation of concerns
- API can evolve independently
- Frontend can use server-rendered HTML + HTMX/Alpine
- Different middleware per stack

### 5. Testing Without the Server

```swift
@Test func listDonuts() async throws {
    let app = try await TestApp(DonutShop.self)

    let response = try await app.get("/api/v1/donuts")

    #expect(response.status == .ok)
    #expect(response.json["donuts"] != nil)
}
```

**Compare to Hummingbird:**

```swift
// Requires building the full router
let router = Router()
router.get("/") { ... }
let app = Application(responder: router)
// ... more setup
```

**Compare to Vapor:**

```swift
// Requires Application instance
let app = Application(.testing)
try configure(app)  // runs all route registration
// ... more setup
```

---

## Route Organization in DonutShop

```
Sources/DonutShop/
├── App.swift                 # Main app, routes composition
├── Routes/
│   ├── DonutRoutes.swift     # API + Frontend variants
│   ├── OrderRoutes.swift     # API + Frontend variants
│   ├── CustomerRoutes.swift  # API + Frontend variants
│   ├── AnalyticsRoutes.swift # API only
│   └── SeedRoutes.swift      # Admin only
```

### DonutRoutes.swift Pattern

```swift
// MARK: - API Routes (JSON)
@RouteBuilder
func donutApiRoutes() -> [Route] {
    GET("/") { conn in
        let donuts = try await conn.repo().all(Donut.self)
        return try conn.json(value: donuts)
    }

    GET("/:id") { conn in
        // JSON response
    }

    POST("/") { conn in
        // JSON create
    }
}

// MARK: - Frontend Routes (HTML)
@RouteBuilder
func donutFrontendRoutes() -> [Route] {
    GET("/") { conn in
        let donuts = try await conn.repo().all(Donut.self)
        return conn.html(#render("donut_list.esw"))
    }

    GET("/:id") { conn in
        // HTML detail page
    }

    POST("/") { conn in
        // Form submission → redirect with flash
        return conn
            .putFlash(.info, "Donut created!")
            .redirect(to: "/donuts")
    }
}
```

---

## Key Wins

1. **Immutable Routes**: No mutable router state, no registration order bugs
2. **Composable**: Routes are just `[Route]` arrays, compose with functions
3. **Testable**: `TestApp` runs routes without starting a server
4. **Rails-like**: File organization matches URL structure
5. **Phoenix-like**: Pipeline/scope pattern for middleware
6. **Type-Safe**: `@RouteBuilder` ensures valid route construction
