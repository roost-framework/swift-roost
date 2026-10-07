import Roost

/// The fields the registration and login forms submit. Other fields are ignored.
struct Credentials: Codable, Sendable {
    let email: String
    let password: String
}

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