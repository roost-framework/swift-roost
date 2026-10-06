import Roost

@RouteBuilder
func bookmarksApiRoutes() -> [Route] {
    GET("/api/bookmarks") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        return try conn.json(value: await context.listBookmarks(scopeId: scopeId))
    }
    GET("/api/bookmarks/:id") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        let id: UUID = try conn.requireParam("id")
        return try conn.json(value: await context.getBookmark(id: id, scopeId: scopeId))
    }
    POST("/api/bookmarks") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        do {
            let input = try conn.decode(as: CreateBookmarkInput.self)
            return try conn.json(status: .created, value: await context.createBookmark(input, scopeId: scopeId))
        } catch let errors as ValidationErrors {
            return try conn.json(status: .unprocessableContent, value: errors)
        }
    }
    PUT("/api/bookmarks/:id") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        let id: UUID = try conn.requireParam("id")
        do {
            let input = try conn.decode(as: CreateBookmarkInput.self)
            return try conn.json(value: await context.updateBookmark(id: id, with: input, scopeId: scopeId))
        } catch let errors as ValidationErrors {
            return try conn.json(status: .unprocessableContent, value: errors)
        }
    }
    DELETE("/api/bookmarks/:id") { conn in
        guard let scopeId = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {
            throw NexusHTTPError(.unauthorized, message: "Authentication required")
        }
        let context = BookmarksContext(repo: conn.repo())
        let id: UUID = try conn.requireParam("id")
        try await context.deleteBookmark(id: id, scopeId: scopeId)
        return try conn.json(value: ["deleted": true])
    }
}