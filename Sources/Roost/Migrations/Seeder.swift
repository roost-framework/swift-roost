import Foundation
import Spectro

// MARK: - Seed Data Manager

/// Load and execute environment-specific SQL seed files.
///
/// Seed files live in a `Seeds/` directory organized by environment:
///
/// ```
/// Seeds/
/// ├── dev.sql
/// ├── test.sql
/// └── prod.sql
/// ```
///
/// ```swift
/// let seeder = Seeder(database: app.spectro)
///
/// // Seed for current environment
/// let result = try await seeder.seed()
///
/// // Seed for a specific environment
/// let result = try await seeder.seed(environment: .test)
/// ```
public struct Seeder: Sendable {

    private let database: SpectroClient
    private let seedsDirectory: URL

    /// Create a seeder.
    ///
    /// - Parameters:
    ///   - database: A connected Spectro client.
    ///   - seedsDirectory: Path to the seeds directory (default: `Seeds/`).
    public init(
        database: SpectroClient,
        seedsDirectory: URL? = nil
    ) {
        self.database = database
        self.seedsDirectory = seedsDirectory
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Seeds")
    }

    /// Run the seed file for the given environment.
    ///
    /// Seeds should be idempotent (use `ON CONFLICT DO NOTHING`).
    ///
    /// - Parameter environment: The environment to seed (default: current).
    /// - Returns: A ``SeedResult`` with timing information.
    /// - Throws: ``RoostMigrationError/seedFileNotFound(_:)`` if no seed
    ///   file exists for the environment.
    @discardableResult
    public func seed(
        environment: Environment = Roost.env
    ) async throws -> SeedResult {
        let seedFile = seedFileURL(for: environment)

        guard FileManager.default.fileExists(atPath: seedFile.path) else {
            throw RoostMigrationError.seedFileNotFound(seedFile.path)
        }

        let sql = try String(contentsOf: seedFile, encoding: .utf8)
        let startTime = Date()

        let repo = database.repository()
        try await repo.executeRawSQL(sql)

        let duration = Date().timeIntervalSince(startTime)

        return SeedResult(
            environment: environment,
            file: seedFile.lastPathComponent,
            duration: duration
        )
    }

    /// Check whether a seed file exists for the given environment.
    ///
    /// - Parameter environment: The environment to check.
    /// - Returns: `true` if a seed file exists.
    public func seedFileExists(for environment: Environment = Roost.env) -> Bool {
        FileManager.default.fileExists(atPath: seedFileURL(for: environment).path)
    }

    /// Get the URL for a seed file.
    ///
    /// - Parameter environment: The environment.
    /// - Returns: The URL to `Seeds/{environment}.sql`.
    public func seedFileURL(for environment: Environment) -> URL {
        seedsDirectory.appendingPathComponent("\(environment.rawValue).sql")
    }

    /// Reset the database by truncating all user tables.
    ///
    /// **Warning:** This is destructive. It drops and recreates the public
    /// schema, removing all data but preserving extensions. Only use in
    /// development and test environments.
    ///
    /// - Throws: If the database operation fails.
    public func reset() async throws {
        let repo = database.repository()
        try await repo.executeRawSQL("""
            DO $$ DECLARE
                r RECORD;
            BEGIN
                FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public')
                LOOP
                    EXECUTE 'TRUNCATE TABLE "' || r.tablename || '" CASCADE';
                END LOOP;
            END $$;
            """)
    }
}
