// PipelinePatterns.swift
// Design specification for Roost Router Pipelines — inspired by Phoenix.Router pipelines
//
// Pipelines are named, reusable plug stacks. Routes declare which pipeline(s) they belong to.
// This replaces ad-hoc per-route middleware stacking with explicit, named composition.
//
// Goal: make the security posture of every route obvious at a glance.

// MARK: - 1. Define pipelines and attach them to scopes

struct MyApp: RoostApp {
    var routes: [Route] {
        // :browser pipeline — full session, flash, CSRF (for HTML consumers)
        pipeline("browser") {
            sessionPlug()
            flashPlug()
            roost_csrfProtection()
            responseTimer()
        }

        // :api pipeline — stateless, JSON, bearer auth (for API consumers)
        pipeline("api") {
            acceptJSON()          // enforces Content-Type: application/json
            bearerAuthPlug()      // sets conn.assigns["currentUser"] if valid token
        }

        // :authenticated — layered on top of :browser or :api
        pipeline("authenticated") {
            requireAuthPlug()     // halts with 401/redirect if no currentUser
        }

        // HTML public routes (no auth required)
        scope("/", pipelines: ["browser"]) {
            get("/",        HomeController.index)
            get("/login",   SessionController.new)
            post("/login",  SessionController.create)
            get("/register",UserController.new)
            post("/register",UserController.create)
        }

        // HTML authenticated routes
        scope("/", pipelines: ["browser", "authenticated"]) {
            get("/dashboard",  DashboardController.index)
            get("/profile",    UserController.show)
            post("/logout",    SessionController.delete)
        }

        // JSON API — public
        scope("/api/v1", pipelines: ["api"]) {
            get("/products",   ProductsAPI.index)
            get("/products/:id", ProductsAPI.show)
        }

        // JSON API — authenticated
        scope("/api/v1", pipelines: ["api", "authenticated"]) {
            post("/products",      ProductsAPI.create)
            put("/products/:id",   ProductsAPI.update)
            delete("/products/:id",ProductsAPI.delete)
        }
    }
}

// MARK: - 2. Inline pipeline (anonymous, single-use)

// For one-off middleware needs that don't warrant a named pipeline:
//
//   scope("/admin", plugs: [requireRole("admin")]) {
//       get("/users",  AdminController.users)
//   }

// MARK: - 3. Pipeline as a value (composable)

// Pipelines can be extracted into constants and reused across apps or modules:
//
//   let browserPipeline = Pipeline("browser") {
//       sessionPlug()
//       flashPlug()
//       roost_csrfProtection()
//   }
//
//   extension MyApp {
//       var routes: [Route] {
//           use(browserPipeline)
//           scope("/", pipelines: ["browser"]) { ... }
//       }
//   }

// MARK: - 4. Difference from Phoenix

// Phoenix uses `pipe_through :browser` as a call inside a scope block.
// Roost makes the pipeline association explicit in the `scope` declaration,
// so the full middleware stack for a route is visible at the `scope` call site
// rather than requiring you to look up where `pipe_through` is called.

// MARK: - 5. Pipeline introspection in dev

// In development, Roost's dev server prints a routing table at startup:
//
//   GET  /                        [browser]           HomeController.index
//   GET  /login                   [browser]           SessionController.new
//   POST /login                   [browser]           SessionController.create
//   GET  /dashboard               [browser, authenticated]  DashboardController.index
//   GET  /api/v1/products         [api]               ProductsAPI.index
//   POST /api/v1/products         [api, authenticated]  ProductsAPI.create

// MARK: - 6. Built-in pipeline plugs (provided by Roost)

// sessionPlug()               — loads/saves session from cookie-backed store
// flashPlug()                 — reads/writes one-time flash messages in session
// roost_csrfProtection()  — validates CSRF token on state-changing requests
// responseTimer()             — adds X-Response-Time header
// acceptJSON()                — sets Content-Type: application/json on responses
// bearerAuthPlug()            — extracts Bearer token, sets conn.assigns["currentUser"]
// requireAuthPlug()           — halts 401 (API) or redirects to /login (browser) if no currentUser
// requireRole(_ role: String) — halts 403 if currentUser lacks the given role
// staticFiles(from:at:)       — serves Public/ directory (typically in browser pipeline)
