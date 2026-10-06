import Roost

// MARK: - Pattern 1: Dual Frontend/API Routes
//
// Roost makes it trivial to maintain both HTML and JSON endpoints
// for the same resources. No need for separate controllers or complex
// content negotiation.

// API: Returns JSON, used by mobile apps, SPAs, third parties
@RouteBuilder
func donutApiRoutes() -> [Route] {
    GET("/") { conn in
        let donuts = try await conn.repo().query(Donut.self)
            .where { $0.isAvailable == true }
            .all()

        return try conn.json(value: donuts.map { d in
            [
                "id": "\(d.id)",
                "name": d.name,
                "price": d.price,
            ]
        })
    }

    POST("/") { conn in
        // JSON create
        let body = try conn.decode(as: CreateDonutRequest.self)
        // ... create donut
        return try conn.json(status: .created, value: ["id": "..."])
    }
}

// Frontend: Returns HTML, uses flash messages, CSRF protection
@RouteBuilder
func donutFrontendRoutes() -> [Route] {
    GET("/") { conn in
        let donuts = try await conn.repo().query(Donut.self)
            .where { $0.isAvailable == true }
            .all()

        // Render template with assigns
        let content = #render("donut_list.esw")
        let title = "Menu"
        return conn.html(#render("layout.esw"))
    }

    POST("/") { conn in
        // Form submission
        let form = conn.formParams
        // ... create donut

        // Flash + redirect pattern (POST-redirect-GET)
        return conn
            .putFlash(.info, "Donut '\(name)' created!")
            .redirect(to: "/donuts")
    }
}

// MARK: - Pattern 2: Scope-Based Middleware
//
// Different URL scopes get different middleware pipelines.
// Clean separation without global state.

@RouteBuilder var routes: [Route] {
    // Health check: No middleware needed
    GET("/health") { conn in
        try conn.json(value: ["status": "ok"])
    }

    // API scope: CORS, no CSRF, no flash
    forward("/api/v1", to: Router {
        scope("/donuts") { donutApiRoutes() }
        scope("/orders") { orderApiRoutes() }
    })

    // Frontend scope: Sessions, flash, CSRF protection
    forward("/", to: Router {
        scope("/donuts") { donutFrontendRoutes() }
        scope("/customers") { customerFrontendRoutes() }
    })

    // Admin scope: Authentication + all frontend middleware
    scope("/admin", through: [basicAuth(realm: "Admin") { user, pass in
        user == "admin" && pass == secretPassword
    }]) {
        seedRoute()
    }
}

// MARK: - Pattern 3: Route Files as Modules
//
// Each route file is self-contained. No need to import routes into
// a central registry - just call the function.

// Sources/DonutShop/Routes/OrderRoutes.swift
@RouteBuilder
func orderRoutes() -> [Route] {
    // Private helper functions stay in the file
    func calculateTotal(items: [OrderItem]) -> Double {
        items.reduce(0) { $0 + $1.unitPrice * Double($1.quantity) }
    }

    GET("/") { conn in
        // Uses private helper
        // ...
    }
}

// Sources/DonutShop/Routes/AnalyticsRoutes.swift
@RouteBuilder
func analyticsRoutes() -> [Route] {
    // Analytics use aggregates that regular routes don't need
    GET("/revenue") { conn in
        let total = try await conn.repo().query(Order.self)
            .where { $0.status == "confirmed" }
            .sum { $0.totalPrice }

        return try conn.json(value: ["revenue": total ?? 0])
    }
}

// MARK: - Pattern 4: Testing Without the Server
//
// Routes are pure data, so we can test them with TestApp
// without starting an HTTP server.

/*
@Test func createsDonut() async throws {
    let app = try await TestApp(DonutShop.self)

    let response = try await app.post(
        "/api/v1/donuts",
        json: ["name": "Glazed", "price": 1.99]
    )

    #expect(response.status == .created)
    #expect(response.json["name"] == "Glazed")
}
*/

// MARK: - Pattern 5: Immutable Configuration
//
// No global state, no mutation. The app is a struct with
// computed properties returning configuration.

struct DonutShop: RoostApp {
    // Database config: computed, not stored
    var database: Database? {
        Database.postgres(
            hostname: ProcessInfo.processInfo.environment["DB_HOST"] ?? "localhost",
            database: "donut_shop"
        )
    }

    // Middleware pipeline: just an array
    var plugs: [Plug] {
        [
            roost_staticFiles(from: "Public", at: "/"),
            requestId(),
            responseTimer(),
            requestLogger(),
            corsPlug(CORSConfig(allowedOrigin: "*")),
            flashPlug(),
            roost_csrfProtection(except: ["/admin/seed"]),
            methodOverride(),
        ]
    }

    // Routes: composed from functions, no mutation
    @RouteBuilder var routes: [Route] {
        GET("/health") { conn in ... }
        forward("/api/v1", to: Router { ... })
        forward("/", to: Router { ... })
    }
}

// MARK: - Pattern 6: Request Context (Conn vs Req/Res)
//
// Roost uses a single Connection object that carries
// request, response, and assigns. No need to return Response
// and manually manage state.

// Hummingbird: Must return Response
func handler(request: Request, context: Context) async throws -> Response {
    // Can't easily share data between middleware and handler
    let body = try await request.body.collect()
    return Response(status: .ok, body: .init(data: body))
}

// Roost: Connection accumulates state
@RouteBuilder
func routes() -> [Route] {
    GET("/") { conn in
        // conn has request data
        let userId = conn.session["user_id"]

        // conn.assigns contains data from middleware
        let requestId = conn.assigns["request_id"]

        // Modify conn and return it
        return try conn
            .putRespHeader(.contentType, "application/json")
            .json(value: ["ok": true])
    }
}

// MARK: - Pattern 7: Database Repository Pattern
//
// No ORM, no active record. Just queries and structs.

@Schema("donuts")
struct Donut {
    @ID var id: UUID
    @Column var name: String
    @Column var price: Double
    @Timestamp var createdAt: Date
}

func listExpensiveDonuts(conn: Connection) async throws -> [Donut] {
    // Query builder, not ORM
    try await conn.repo().query(Donut.self)
        .where { $0.price > 2.00 }
        .orderBy(\.price, .desc)
        .limit(10)
        .all()
}

// MARK: - Pattern 8: Flash Messages (Rails-style)
//
// One-time messages that survive redirects.

@RouteBuilder
func routes() -> [Route] {
    POST("/items") { conn in
        // Create item...

        // Set flash message
        return conn
            .putFlash(.info, "Item created!")
            .redirect(to: "/items")
    }

    GET("/items") { conn in
        // Flash is available here, then cleared
        let flash = conn.flash

        return conn.html("Items: \(flash.info ?? "")")
    }
}

// MARK: - Pattern 9: CSRF Protection (Automatic)
//
// Forms get CSRF tokens, JSON APIs don't. No configuration needed.

var plugs: [Plug] {
    [
        roost_csrfProtection(),  // Protects all routes
        // JSON requests (Content-Type: application/json) bypass CSRF
        // HTML form submissions require token
    ]
}

// Template automatically gets csrfTag assign
// <form method="post">
//   <%= csrfTag %>  <!-- <input type="hidden" name="_csrf" value="..."> -->
// </form>

// MARK: - Pattern 10: Static File Serving
//
// Built-in static file serving with security and caching.

var plugs: [Plug] {
    [
        // Serves from Public/ at URL /
        // - Hidden files (starting with .) return 404
        // - Path traversal blocked
        // - Environment-aware caching headers
        roost_staticFiles(from: "Public", at: "/"),

        // Other middleware...
    ]
}

// MARK: - Helper Types

struct CreateDonutRequest: Decodable {
    let name: String
    let price: Double
}

let secretPassword = ProcessInfo.processInfo.environment["ADMIN_PASS"] ?? "admin"
