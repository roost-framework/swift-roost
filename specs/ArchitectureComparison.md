# Roost vs Other Swift Web Frameworks

## The Mutability Problem

### Hummingbird's Approach

```swift
// Router is a class, mutated during setup
let router = Router()

// Each registration mutates internal state
router.get("/") { req, context in ... }
router.post("/items") { req, context in ... }

// Groups create new routers that are also mutated
router.group("api") { api in  // api is a reference, not value
    api.get("/users") { ... }  // mutation!
}
```

**Problems:**
1. **Side effects everywhere** - Route registration order matters
2. **Testing is hard** - Need full router instance, can't test routes in isolation
3. **Composition is awkward** - Can't easily merge routers from different modules
4. **No compile-time safety** - Typos in paths found at runtime

### Vapor's Approach

```swift
// Application is a massive dependency container
let app = Application(.production)

// Routes registered on app during configure()
app.get("/") { req in ... }

// Controllers separate handlers from registration
final class TodoController {
    func index(req: Request) throws -> [Todo] { ... }
    func create(req: Request) throws -> Todo { ... }
}
let todos = TodoController()
app.get("todos", use: todos.index)
app.post("todos", use: todos.create)
```

**Problems:**
1. **Controller boilerplate** - Classes with methods just to route
2. **Registration scattered** - Routes defined in one place, handlers in another
3. **Massive Application type** - Carries database, middleware, etc.
4. **Testing requires full app** - Hard to test single route

---

## Roost's Solution: Immutable Route Trees

### Routes as Data

```swift
// Routes are just arrays
@RouteBuilder
func userRoutes() -> [Route] {
    GET("/") { conn in ... }
    GET("/:id") { conn in ... }
}

// Composition is array concatenation
@RouteBuilder
func apiRoutes() -> [Route] {
    scope("/users") { userRoutes() }
    scope("/posts") { postRoutes() }
}
```

**Benefits:**
- No mutation, no side effects
- Routes compose like any other Swift value
- Test individual routes without the app
- File organization matches URL structure

### No Global State

```swift
// Hummingbird/Vapor: Application is god object
app.databases.use(...)  // global state
app.middleware.use(...) // global state
app.routes.get(...)     // global state

// Roost: Config struct, immutable pipeline
struct DonutShop: RoostApp {
    var database: Database? { .postgres(...) }
    var plugs: [Plug] { [...] }  // just an array
    @RouteBuilder var routes: [Route] { [...] }  // just an array
}
```

### Testing Without the Server

```swift
// Hummingbird: Need the full router
let router = Router()
router.get("/users") { ... }
let app = Application(router: router)
// ... still need to start server or mock

// Vapor: Need the full Application
let app = Application(.testing)
try configure(app)
// ... app carries entire dependency graph

// Roost: Just the routes
let testApp = try await TestApp(DonutShop.self)
let response = try await testApp.get("/api/v1/donuts")
#expect(response.status == .ok)
```

---

## Phoenix/Rails Inspiration

### Phoenix-Style Pipelines

```elixir
# Phoenix
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :protect_from_forgery
end

pipeline :api do
  plug :accepts, ["json"]
end

scope "/", MyAppWeb do
  pipe_through :browser
  get "/", PageController, :index
end

scope "/api", MyAppWeb do
  pipe_through :api
  resources "/users", UserController
end
```

```swift
// Roost: Same concept, Swift syntax
var plugs: [Plug] {
    [
        roost_staticFiles(from: "Public"),
        requestId(),
        responseTimer(),
        corsPlug(...),
        flashPlug(),
        roost_csrfProtection(),
    ]
}

@RouteBuilder var routes: [Route] {
    // Frontend pipeline (HTML, CSRF, sessions)
    scope("/") {
        GET("/donuts") { conn in ... }  // uses flash, CSRF
    }

    // API pipeline (JSON, no CSRF)
    scope("/api/v1") {
        GET("/donuts") { conn in ... }  // JSON only
    }
}
```

### Rails-Style Resource Organization

```ruby
# Rails: app/controllers/users_controller.rb
class UsersController < ApplicationController
  def index
    @users = User.all
  end

  def show
    @user = User.find(params[:id])
  end
end

# config/routes.rb
resources :users
```

```swift
// Roost: Sources/DonutShop/Routes/CustomerRoutes.swift
@RouteBuilder
func customerRoutes() -> [Route] {
    GET("/") { conn in
        let customers = try await conn.repo().all(Customer.self)
        return conn.html(...)
    }

    GET("/:id") { conn in
        let id = conn.params["id"]
        let customer = try await conn.repo().get(Customer.self, id: id)
        return conn.html(...)
    }
}
```

**Key insight:** Roost eliminates the controller class. The route *is* the action.

---

## The @RouteBuilder Advantage

### Compile-Time Route Validation

```swift
// This compiles - valid route tree
@RouteBuilder
func validRoutes() -> [Route] {
    GET("/") { ... }
    POST("/items") { ... }
}

// This also compiles - RouteBuilder validates structure
@RouteBuilder
func nestedRoutes() -> [Route] {
    scope("/api") {
        scope("/v1") {
            GET("/users") { ... }
        }
    }
}
```

Compare to:

```swift
// Hummingbird: Runtime errors for path conflicts
router.get("/users/:id") { ... }
router.get("/users/:id") { ... }  // runtime conflict!

// Vapor: Same problem
app.get("users", ":id") { ... }
app.get("users", ":id") { ... }  // silent overwrite!
```

### Pure Functions Enable Testing

```swift
// Roost: Route handler is pure
func showDonut(conn: Connection) async throws -> Connection {
    let id = conn.params["id"]
    let donut = try await conn.repo().get(Donut.self, id: id)
    return try conn.json(value: donut)
}

// Can test handler directly
@Test func showDonutHandler() async throws {
    let conn = TestConnection.get("/donuts/123")
    let result = try await showDonut(conn: conn)
    #expect(result.response.status == .ok)
}
```

Compare to:

```swift
// Hummingbird: Handler tied to Request/Response types
func showDonut(
    request: Request,
    context: Context
) async throws -> Response { ... }
// Hard to test without Request/Context mocks

// Vapor: Handler tied to Request type
func showDonut(req: Request) async throws -> Donut { ... }
// Returns model, not Response - harder to test full pipeline
```

---

## Summary Table

| Feature | Hummingbird | Vapor | Roost |
|---------|-------------|-------|-----------|
| **Route definition** | Imperative mutation | Imperative mutation | Declarative data |
| **Route composition** | Awkward (group closures) | Awkward (controllers) | Natural (functions) |
| **Handler isolation** | Tied to Router | Tied to Application | Pure functions |
| **Testing** | Full router required | Full app required | TestApp, no server |
| **Frontend/API split** | Manual | Manual | scope/forward |
| **Middleware** | Router-level | Route-level | Pipeline array |
| **Type safety** | Path strings | Path strings | @RouteBuilder |
| **Inspiration** | Swift NIO | Node/Express | Phoenix/Rails |

---

## When to Use Each

**Use Hummingbird when:**
- You need low-level HTTP control
- Performance is absolutely critical
- You want minimal abstractions

**Use Vapor when:**
- You want a large ecosystem
- You prefer controller classes
- You need ORM integration (Fluent)

**Use Roost when:**
- You want Rails/Phoenix patterns in Swift
- You value testability
- You prefer functional composition
- You want clean Frontend/API separation
