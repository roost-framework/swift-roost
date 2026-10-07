import Roost

/// The reading queue's pages. Every action belongs to the signed-in reader.
struct BookmarkController: Controller {
    enum Action: String, ControllerAction {
        case index, new, create, show, edit, update, delete, read
    }

    static let plugs: [ActionPlug<Action>] = [.plug(requireAuth())]

    static func action(_ action: Action) -> Plug {
        switch action {
        case .index: index
        case .new: new
        case .create: create
        case .show: show
        case .edit: edit
        case .update: update
        case .delete: delete
        case .read: read
        }
    }

    static func index(_ conn: Connection) async throws -> Connection {
        let bookmarks = try await BookmarksContext(repo: conn.repo()).listBookmarks(scopeId: readerID(conn))
        let filter = ReadingFilter(rawValue: conn.queryParams["filter"] ?? "") ?? .unread
        return try conn.render(BookmarksIndexView(bookmarks: bookmarks, filter: filter), title: "Your reading queue")
    }

    static func new(_ conn: Connection) async throws -> Connection {
        try conn.render(BookmarkNewView(), title: "Save a link")
    }

    static func show(_ conn: Connection) async throws -> Connection {
        let id: UUID = try conn.requireParam("id")
        let bookmark = try await BookmarksContext(repo: conn.repo()).getBookmark(id: id, scopeId: readerID(conn))
        return try conn.render(BookmarkShowView(bookmark: bookmark), title: bookmark.title)
    }

    static func create(_ conn: Connection) async throws -> Connection {
        let scopeId = try readerID(conn)
        do {
            let input = try conn.permit(CreateBookmarkInput.self)
            let created = try await BookmarksContext(repo: conn.repo()).createBookmark(input, scopeId: scopeId)
            return conn.putFlash(.info, "Link saved").redirect(to: "/bookmarks/\(created.id)")
        } catch let errors as ValidationErrors {
            return try conn.render(BookmarkNewView(values: conn.bodyParams, errors: errors), title: "Save a link", status: .unprocessableContent)
        }
    }

    static func edit(_ conn: Connection) async throws -> Connection {
        let id: UUID = try conn.requireParam("id")
        let bookmark = try await BookmarksContext(repo: conn.repo()).getBookmark(id: id, scopeId: readerID(conn))
        return try conn.render(BookmarkEditView(bookmark: bookmark), title: "Edit link")
    }

    static func update(_ conn: Connection) async throws -> Connection {
        let scopeId = try readerID(conn)
        let context = BookmarksContext(repo: conn.repo())
        let id: UUID = try conn.requireParam("id")
        let bookmark = try await context.getBookmark(id: id, scopeId: scopeId)
        do {
            let input = try conn.permit(CreateBookmarkInput.self)
            _ = try await context.updateBookmark(id: id, with: input, scopeId: scopeId)
            return conn.putFlash(.info, "Changes saved").redirect(to: "/bookmarks/\(id)")
        } catch let errors as ValidationErrors {
            return try conn.render(BookmarkEditView(bookmark: bookmark, values: conn.bodyParams, errors: errors), title: "Edit link", status: .unprocessableContent)
        }
    }

    static func delete(_ conn: Connection) async throws -> Connection {
        let id: UUID = try conn.requireParam("id")
        try await BookmarksContext(repo: conn.repo()).deleteBookmark(id: id, scopeId: readerID(conn))
        return conn.putFlash(.info, "Link removed").redirect(to: "/bookmarks")
    }

    /// The "mark as read" button: only the reading state and the list to return to.
    struct ReadParams: Codable, Sendable {
        let read: Bool
        let filter: String?
    }

    static func read(_ conn: Connection) async throws -> Connection {
        let id: UUID = try conn.requireParam("id")
        let params = try conn.permit(ReadParams.self)
        try await BookmarksContext(repo: conn.repo()).setRead(id: id, read: params.read, scopeId: readerID(conn))
        let filter = ReadingFilter(rawValue: params.filter ?? "") ?? .unread
        return conn.putFlash(.info, params.read ? "Moved to finished" : "Moved to your reading queue")
            .redirect(to: "/bookmarks?filter=\(filter.rawValue)")
    }
}

/// The signed-in reader whose bookmarks a request may read or change.
func readerID(_ conn: Connection) throws -> UUID {
    guard let id = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
        throw NexusHTTPError(.unauthorized, message: "Authentication required")
    }
    return id
}
