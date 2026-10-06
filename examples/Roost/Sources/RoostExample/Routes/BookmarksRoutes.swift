import Roost

@RouteBuilder
func bookmarksRoutes() -> [Route] {
    GET("/bookmarks") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        let bookmarks = try await context.listBookmarks(scopeId: scopeId)
        let filter = ReadingFilter(rawValue: conn.queryParams["filter"] ?? "") ?? .unread
        return try conn.render(BookmarksIndexView(bookmarks: bookmarks, filter: filter), title: "Your reading queue")
    }
    GET("/bookmarks/new") { conn in
        try conn.render(BookmarkNewView(), title: "Save a link")
    }
    GET("/bookmarks/:id") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        let id: UUID = try conn.requireParam("id")
        let bookmark = try await context.getBookmark(id: id, scopeId: scopeId)
        return try conn.render(BookmarkShowView(bookmark: bookmark), title: bookmark.title)
    }
    POST("/bookmarks") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        do {
            let input = try CreateBookmarkInput(form: conn.bodyParams)
            let created = try await context.createBookmark(input, scopeId: scopeId)
            return conn.putFlash(.info, "Link saved").redirect(to: "/bookmarks/\(created.id)")
        } catch let errors as ValidationErrors {
            return try conn.render(BookmarkNewView(values: conn.bodyParams, errors: errors), title: "Save a link", status: .unprocessableContent)
        }
    }
    GET("/bookmarks/:id/edit") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        let id: UUID = try conn.requireParam("id")
        let bookmark = try await context.getBookmark(id: id, scopeId: scopeId)
        return try conn.render(BookmarkEditView(bookmark: bookmark), title: "Edit link")
    }
    PUT("/bookmarks/:id") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        let id: UUID = try conn.requireParam("id")
        let bookmark = try await context.getBookmark(id: id, scopeId: scopeId)
        do {
            let input = try CreateBookmarkInput(form: conn.bodyParams)
            _ = try await context.updateBookmark(id: id, with: input, scopeId: scopeId)
            return conn.putFlash(.info, "Changes saved").redirect(to: "/bookmarks/\(id)")
        } catch let errors as ValidationErrors {
            return try conn.render(BookmarkEditView(bookmark: bookmark, values: conn.bodyParams, errors: errors), title: "Edit link", status: .unprocessableContent)
        }
    }
    DELETE("/bookmarks/:id") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        let id: UUID = try conn.requireParam("id")
        try await context.deleteBookmark(id: id, scopeId: scopeId)
        return conn.putFlash(.info, "Link removed").redirect(to: "/bookmarks")
    }
    POST("/bookmarks/:id/read") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let id: UUID = try conn.requireParam("id")
        let read = try FormValues(conn.bodyParams).decode("read", as: Bool.self)
        try await BookmarksContext(repo: conn.repo()).setRead(id: id, read: read, scopeId: scopeId)
        let filter = ReadingFilter(rawValue: conn.bodyParams["filter"] ?? "") ?? .unread
        return conn.putFlash(.info, read ? "Moved to finished" : "Moved to your reading queue")
            .redirect(to: "/bookmarks?filter=\(filter.rawValue)")
    }
}
