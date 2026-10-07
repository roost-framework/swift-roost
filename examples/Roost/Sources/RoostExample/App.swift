import Roost

@main
struct RoostExample: RoostApp {
    let database: Database? = Database.postgres(database: "roost")

    let sessionStore: (any SessionStore)? = MemorySessionStore()

    var layout: HTMLLayout? {
        { conn, title, content in LayoutView(conn: conn, title: title, content: content).render() }
    }

    var plugs: [Plug] {
        [requestId(), roost_requestLogger(), roost_staticFiles()] + browserPlugs() + [
            fetchCurrentUser(),
            // roost:plugs
        ]
    }

    @RouteBuilder var routes: [Route] {
        scope("/auth") { authRoutes() }
        resources("/bookmarks", BookmarkController.self)
        POST("/bookmarks/:id/read", BookmarkController.self, .read)
        scope("/api") { resources("/bookmarks", BookmarkAPIController.self) }
        // roost:routes
        GET("/", PageController.self, .home)
    }

    func willStart(spectro: SpectroClient) async throws {
        if Self.demoMode { try await seedDemo(repo: spectro.repository()) }
    }

    static var demoMode: Bool {
        Roost.env == .dev && ProcessInfo.processInfo.environment["ROOST_DEMO"] == "1"
    }
}
