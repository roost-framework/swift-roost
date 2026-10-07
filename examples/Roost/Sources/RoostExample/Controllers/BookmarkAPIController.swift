import Roost

/// The reading queue as JSON, for the signed-in reader's session.
struct BookmarkAPIController: Controller {
    enum Action: String, ControllerAction {
        case index, show, create, update, delete
    }

    static func action(_ action: Action) -> Plug {
        switch action {
        case .index: index
        case .show: show
        case .create: create
        case .update: update
        case .delete: delete
        }
    }

    static func index(_ conn: Connection) async throws -> Connection {
        try conn.json(value: await BookmarksContext(repo: conn.repo()).listBookmarks(scopeId: readerID(conn)))
    }

    static func show(_ conn: Connection) async throws -> Connection {
        let id: UUID = try conn.requireParam("id")
        return try conn.json(value: await BookmarksContext(repo: conn.repo()).getBookmark(id: id, scopeId: readerID(conn)))
    }

    static func create(_ conn: Connection) async throws -> Connection {
        let scopeId = try readerID(conn)
        do {
            let input = try conn.permit(CreateBookmarkInput.self)
            return try conn.json(status: .created, value: await BookmarksContext(repo: conn.repo()).createBookmark(input, scopeId: scopeId))
        } catch let errors as ValidationErrors {
            return try conn.json(status: .unprocessableContent, value: errors)
        }
    }

    static func update(_ conn: Connection) async throws -> Connection {
        let scopeId = try readerID(conn)
        let id: UUID = try conn.requireParam("id")
        do {
            let input = try conn.permit(CreateBookmarkInput.self)
            return try conn.json(value: await BookmarksContext(repo: conn.repo()).updateBookmark(id: id, with: input, scopeId: scopeId))
        } catch let errors as ValidationErrors {
            return try conn.json(status: .unprocessableContent, value: errors)
        }
    }

    static func delete(_ conn: Connection) async throws -> Connection {
        let id: UUID = try conn.requireParam("id")
        try await BookmarksContext(repo: conn.repo()).deleteBookmark(id: id, scopeId: readerID(conn))
        return try conn.json(value: ["deleted": true])
    }
}
