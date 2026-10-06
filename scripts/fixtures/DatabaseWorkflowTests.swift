import Testing
import Roost
import RoostTest
@testable import TodoWorkshop

@Test("HTTP routes and contexts share a transaction that rolls back")
func transactionIsolation() async throws {
    let config = Database.postgres()
    let client = try SpectroClient(hostname: config.hostname, port: config.port,
        username: config.username, password: config.password, database: config.database)
    let repo = client.repository()
    let email = "rollback-\(UUID())@example.test"
    do {
        try await withTestRollback(repository: repo) { transaction in
            var fixture = User()
            fixture.email = email
            fixture.hashedPassword = "unused by this test"
            let user = try await transaction.insert(fixture)
            let rawToken = Auth.generateToken()
            var token = UserToken()
            token.userId = user.id
            token.token = Auth.sha256Hex(rawToken)
            token.context = "session"
            _ = try await transaction.insert(token)
            let app = try await TestApp(TodoWorkshop.self, repository: transaction)
            let form = try await app.get("/todos/new", session: [
                "_roost_auth_token": rawToken,
                // Authorization must use the loaded user's identity, not this stale hint.
                "_roost_user_id": UUID().uuidString,
                "_csrf_token": "test-csrf",
            ])
            #expect(form.status == .ok)
            let cookie = try #require(form.cookies[defaultSessionCookie])
            let saved = try await app.post("/todos", form: ["title": "In transaction", "_csrf_token": "test-csrf"],
                headers: ["Cookie": "\(defaultSessionCookie)=\(cookie)"])
            #expect(saved.status == .seeOther)
            let rows = try await TodosContext(repo: transaction).listTodos(scopeId: user.id)
            #expect(rows.count == 1)
            #expect(rows.first?.title == "In transaction")
        }
        #expect(try await repo.query(User.self).where { $0.email == email }.first() == nil)
    } catch {
        await client.shutdown()
        throw error
    }
    await client.shutdown()
}
