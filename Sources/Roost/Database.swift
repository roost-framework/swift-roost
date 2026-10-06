import Foundation

/// Database connection configuration.
public struct Database: Sendable {
    public let hostname: String
    public let port: Int
    public let username: String
    public let password: String
    public let database: String

    public init(
        hostname: String,
        port: Int,
        username: String,
        password: String,
        database: String
    ) {
        self.hostname = hostname
        self.port = port
        self.username = username
        self.password = password
        self.database = database
    }

    /// Creates a Postgres configuration by reading standard environment
    /// variables with sensible defaults for local development.
    ///
    /// Environment variables: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`.
    ///
    /// In `.dev` and `.test` environments, a suffix (`_dev` or `_test`) is
    /// appended to the database name unless `DB_NAME` is explicitly set.
    /// In `.prod`, an explicit `DB_NAME` wins; otherwise a supplied base name
    /// is used unchanged. Production fails only when neither is provided.
    public static func postgres(
        hostname: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        database: String? = nil
    ) -> Database {
        let env = ProcessInfo.processInfo.environment

        let dbNameExplicit = env["DB_NAME"]
        let resolvedDatabase: String = {
            if let explicit = dbNameExplicit {
                return explicit
            }
            guard let base = database else {
                if Roost.env == .prod {
                    fatalError("DB_NAME environment variable is required in production")
                }
                return "roost_\(Roost.env.rawValue)"
            }
            switch Roost.env {
            case .dev:
                return "\(base)_dev"
            case .test:
                return "\(base)_test"
            case .prod:
                return base
            }
        }()

        return Database(
            hostname: hostname ?? env["DB_HOST"] ?? "localhost",
            port: port ?? env["DB_PORT"].flatMap(Int.init) ?? 5432,
            username: username ?? env["DB_USER"] ?? "postgres",
            password: password ?? env["DB_PASSWORD"] ?? "postgres",
            database: resolvedDatabase
        )
    }
}
