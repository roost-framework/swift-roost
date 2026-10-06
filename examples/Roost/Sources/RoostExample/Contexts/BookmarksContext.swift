import Roost

/// Domain operations depend on a repository, including a transaction repository in tests.
struct BookmarksContext: Sendable {
    let repo: any Repo

    func listBookmarks(scopeId: UUID) async throws -> [Bookmark] {
        try await repo.query(Bookmark.self)
            .where({ $0.userId == scopeId })
            .orderBy(\.createdAt, .asc).all()
    }

    func getBookmark(id: UUID, scopeId: UUID) async throws -> Bookmark {
        guard let record = try await repo.query(Bookmark.self)
            .where({ $0.id == id })
            .where({ $0.userId == scopeId })
            .first() else {
            throw NexusHTTPError(.notFound, message: "Bookmark not found")
        }
        return record
    }

    func createBookmark(_ input: CreateBookmarkInput, scopeId: UUID) async throws -> Bookmark {
        let input = try await input.validated()
        var record = Bookmark()
        record.userId = scopeId
        record.title = input.title
        record.url = input.url
        record.note = input.note
        record.read = input.read
        return try await repo.insert(record)
    }

    func updateBookmark(id: UUID, with input: CreateBookmarkInput, scopeId: UUID) async throws -> Bookmark {
        _ = try await getBookmark(id: id, scopeId: scopeId)
        let input = try await input.validated()
        return try await repo.update(Bookmark.self, id: id, changes: [
            "title": input.title as any Sendable,
            "url": input.url as any Sendable,
            "note": input.note as any Sendable,
            "read": input.read as any Sendable,
            "updatedAt": Date(),
        ])
    }

    func deleteBookmark(id: UUID, scopeId: UUID) async throws {
        _ = try await getBookmark(id: id, scopeId: scopeId)
        try await repo.delete(Bookmark.self, id: id)
    }

    /// A separate domain action keeps a reading-state change from replacing the saved link.
    func setRead(id: UUID, read: Bool, scopeId: UUID) async throws {
        _ = try await getBookmark(id: id, scopeId: scopeId)
        _ = try await repo.update(Bookmark.self, id: id, changes: [
            "read": read,
            "updatedAt": Date(),
        ])
    }
}

struct CreateBookmarkInput: Codable, Sendable {
    let title: String
    let url: String
    let note: String
    let read: Bool

    func validated() async throws -> Self {
        let normalized = Self(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            read: read
        )
        var changeset = Changeset(data: normalized)
        await changeset.validate(using: [
            .required("title") { $0.title },
            .length("title", { $0.title }, max: 160),
            .length("note", { $0.note }, max: 2000),
            .custom { input in
                guard let url = URLComponents(string: input.url),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host, !host.isEmpty,
                      url.user == nil, url.password == nil,
                      !input.url.contains(where: { $0.isWhitespace }) else {
                    return [.field("url", "Enter a complete http:// or https:// link")]
                }
                return []
            },
        ])
        return try changeset.requireValid()
    }
}

extension CreateBookmarkInput {
    init(form: [String: String]) throws {
        let values = FormValues(form)
        self.title = try values.decode("title", as: String.self)
        self.url = try values.decode("url", as: String.self)
        self.note = try values.decode("note", as: String.self)
        self.read = try values.decode("read", as: Bool.self)
    }
}
