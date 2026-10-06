import Roost

@main
struct RoostExample: RoostApp {
    let database: Database? = Database.postgres(database: "roost")

    let sessionStore: (any SessionStore)? = MemorySessionStore()

    var layout: HTMLLayout? {
        { conn, title, content in LayoutView(conn: conn, title: title, content: content).render() }
    }

    var plugs: [Plug] {
        [requestId(), requestLogger(), roost_staticFiles()] + browserPlugs() + [
            fetchCurrentUser(),
            // roost:plugs
        ]
    }

    @RouteBuilder var routes: [Route] {
        scope("/auth") { authRoutes() }
        scope("/", plugs: [requireAuth()]) { bookmarksRoutes() }
        bookmarksApiRoutes()
        // roost:routes
        GET("/") { conn in
            conn.redirect(to: conn.authenticatedUserID == nil ? "/auth/login" : "/bookmarks")
        }
    }

    func willStart(spectro: SpectroClient) async throws {
        if Self.demoMode { try await seedDemo(repo: spectro.repository()) }
    }

    static var demoMode: Bool {
        Roost.env == .dev && ProcessInfo.processInfo.environment["ROOST_DEMO"] == "1"
    }
}
