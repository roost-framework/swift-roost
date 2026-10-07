import Roost

struct PageController: Controller {
    enum Action: String, ControllerAction {
        case home
    }

    static func action(_ action: Action) -> Plug {
        switch action {
        case .home: home
        }
    }

    /// Readers land on their queue; visitors land on the login page.
    static func home(_ conn: Connection) async throws -> Connection {
        conn.redirect(to: conn.authenticatedUserID == nil ? "/auth/login" : "/bookmarks")
    }
}
