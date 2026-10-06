import Foundation

enum AuthTemplates {

    // MARK: - User Model

    static func userModel() -> String {
        return """
        import Roost

        @Schema("users")
        struct User: Authenticatable {
            @ID var id: UUID
            @Column var email: String
            @Column var hashedPassword: String
            @Timestamp var createdAt: Date

            var authID: String { id.uuidString }
        }
        """
    }

    // MARK: - UserToken Model

    static func userTokenModel() -> String {
        return """
        import Roost

        @Schema("user_tokens")
        struct UserToken: Sendable {
            @ID var id: UUID
            @ForeignKey var userId: UUID
            @Column var token: String
            @Column var context: String
            @Column var sentTo: String?
            @Timestamp var createdAt: Date
        }
        """
    }

    // MARK: - SQL Migrations

    static func createUserTableMigration() -> String {
        return """
        -- migrate:up
        CREATE TABLE "users" (
            "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            "email" TEXT NOT NULL UNIQUE,
            "hashed_password" TEXT NOT NULL,
            "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );

        -- migrate:down
        DROP TABLE "users";
        """
    }

    static func createUserTokensTableMigration() -> String {
        return """
        -- migrate:up
        CREATE TABLE "user_tokens" (
            "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
            "token" TEXT NOT NULL,
            "context" TEXT NOT NULL,
            "sent_to" TEXT,
            "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );

        CREATE INDEX "user_tokens_user_id_index" ON "user_tokens" ("user_id");
        CREATE UNIQUE INDEX "user_tokens_token_context_index" ON "user_tokens" ("token", "context");

        -- migrate:down
        DROP TABLE "user_tokens";
        """
    }

    // MARK: - Auth Routes

    static func authRoutes() -> String {
        """
        import Roost

        @RouteBuilder
        func authRoutes() -> [Route] {
            GET("/register") { conn in
                try conn.render(RegisterView(), title: "Register")
            }
            POST("/register") { conn in
                let email = conn.bodyParams["email"] ?? ""
                do {
                    let (user, token) = try await AccountsContext(repo: conn.repo()).register(
                        email: email, password: conn.bodyParams["password"] ?? "")
                    return conn.loginUser(user, token: token).0.putFlash(.info, "Account created").redirect(to: "/")
                } catch let errors as ValidationErrors {
                    let message = errors.fieldErrors.sorted { $0.key < $1.key }.flatMap { $0.value }.joined(separator: ". ")
                    return try conn.render(RegisterView(email: email, error: message), title: "Register", status: .unprocessableContent)
                }
            }
            GET("/login") { conn in
                try conn.render(LoginView(error: conn.flash.error), title: "Log in")
            }
            POST("/login") { conn in
                let email = conn.bodyParams["email"] ?? ""
                guard let (user, token) = try await AccountsContext(repo: conn.repo()).login(
                    email: email, password: conn.bodyParams["password"] ?? "") else {
                    return try conn.render(LoginView(email: email, error: "Invalid email or password"), title: "Log in", status: .unprocessableContent)
                }
                return conn.loginUser(user, token: token).0.putFlash(.info, "Logged in").redirect(to: "/")
            }
            DELETE("/logout") { conn in
                if let token = conn.authSessionToken {
                    try await AccountsContext(repo: conn.repo()).revoke(token: token)
                }
                return conn.logoutUser().renewSessionID().deleteSession("_csrf_token").redirect(to: "/auth/login")
            }
        }
        """
    }

    // MARK: - Current user plug

    static func requireAuthPlug() -> String {
        """
        import Roost

        /// Fetch once for both browser routes and cookie-authenticated JSON routes.
        /// Protected scopes use Roost's `requireAuth()` after this plug.
        func fetchCurrentUser() -> Plug {
            { conn in
                guard let token = conn.authSessionToken else { return conn }
                guard let user = try await AccountsContext(repo: conn.repo()).user(for: token) else {
                    return conn.logoutUser()
                }
                return conn.setCurrentUser(user)
            }
        }
        """
    }

    // MARK: - Accounts context

    static func authHelper() -> String {
        """
        import Roost

        struct AccountsContext: Sendable {
            let repo: any Repo
            static let sessionLifetime: TimeInterval = 24 * 60 * 60

            func register(email: String, password: String) async throws -> (User, String) {
                let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                var errors = ValidationErrors()
                if email.isEmpty || !email.contains("@") { errors.add(field: "email", "Enter a valid email address") }
                if password.count < Auth.minimumPasswordLength { errors.add(field: "password", "Password must be at least 8 characters") }
                guard errors.isValid else { throw errors }
                if try await repo.query(User.self).where({ $0.email == email }).first() != nil {
                    errors.add(field: "email", "Email is already taken")
                    throw errors
                }
                let hash = try Auth.hashPassword(password)
                let token = Auth.generateToken()
                do {
                    return try await repo.transaction { transaction in
                        var user = User()
                        user.email = email
                        user.hashedPassword = hash
                        let created = try await transaction.insert(user)
                        try await Self.store(token: token, userId: created.id, in: transaction)
                        return (created, token)
                    }
                } catch {
                    // The unique constraint also handles concurrent registrations.
                    if isUniqueConstraintViolation(error) {
                        var errors = ValidationErrors()
                        errors.add(field: "email", "Email is already taken")
                        throw errors
                    }
                    throw error
                }
            }

            func login(email: String, password: String) async throws -> (User, String)? {
                let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let user = try await repo.query(User.self).where({ $0.email == email }).first(),
                      Auth.verifyPassword(password, against: user.hashedPassword) else { return nil }
                let token = Auth.generateToken()
                try await Self.store(token: token, userId: user.id, in: repo)
                return (user, token)
            }

            func user(for token: String) async throws -> User? {
                let hash = Auth.sha256Hex(token)
                guard let match = try await repo.query(UserToken.self)
                    .where({ $0.token == hash && $0.context == "session" }).first(),
                    match.createdAt > Date().addingTimeInterval(-Self.sessionLifetime) else { return nil }
                return try await repo.get(User.self, id: match.userId)
            }

            func revoke(token: String) async throws {
                let hash = Auth.sha256Hex(token)
                if let match = try await repo.query(UserToken.self)
                    .where({ $0.token == hash && $0.context == "session" }).first() {
                    try await repo.delete(UserToken.self, id: match.id)
                }
            }

            private static func store(token: String, userId: UUID, in repo: any Repo) async throws {
                var record = UserToken()
                record.userId = userId
                record.token = Auth.sha256Hex(token)
                record.context = "session"
                _ = try await repo.insert(record)
            }
        }
        """
    }

    // MARK: - Helpers

    static func migrationFilename(table: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(timestamp)_create_\(table).sql"
    }

    // MARK: - ESW Templates

    static func view(name: String, template: String) -> String {
        """
        import Roost

        @ESWTemplate("\(template)")
        struct \(name) {
            var email: String = ""
            var error: String? = nil
        }
        """
    }

    static func loginTemplate() -> String {
        return """
        <main class="container">
            <article>
                <h1>Log in</h1>
                <% if let error { %>
                <p role="alert" class="error"><%= error %></p>
                <% } %>
                <.form action="/auth/login" method="post">
                    <label>
                        Email
                        <input type="email" name="email" value="<%= email %>" required>
                    </label>
                    <label>
                        Password
                        <input type="password" name="password" required>
                    </label>
                    <button type="submit">Log in</button>
                </.form>
                <p>Don't have an account? <a href="/auth/register">Register</a></p>
            </article>
        </main>
        """
    }

    static func registerTemplate() -> String {
        return """
        <main class="container">
            <article>
                <h1>Register</h1>
                <% if let error { %>
                <p role="alert" class="error"><%= error %></p>
                <% } %>
                <.form action="/auth/register" method="post">
                    <label>
                        Email
                        <input type="email" name="email" value="<%= email %>" required>
                    </label>
                    <label>
                        Password
                        <input type="password" name="password" required minlength="8">
                    </label>
                    <button type="submit">Create account</button>
                </.form>
                <p>Already have an account? <a href="/auth/login">Log in</a></p>
            </article>
        </main>
        """
    }
}
