import Foundation
import Spectro
import SpectroCommon

// MARK: - Roost Migrator

/// High-level migration runner that wraps Spectro's `MigrationManager`.
///
/// Provides Roost-specific conveniences on top of Spectro's migration
/// infrastructure: dry-run, redo, rich status reports, and integration with
/// Roost's ``Environment`` system.
///
/// ```swift
/// let migrator = RoostMigrator(database: app.spectro)
///
/// // Run pending migrations
/// try await migrator.migrate()
///
/// // Preview pending (dry-run)
/// let pending = try await migrator.pending()
///
/// // Rich status report
/// let report = try await migrator.status()
/// report.printReport()
/// ```
public struct RoostMigrator: Sendable {

    private let database: SpectroClient
    private let migrationsPath: URL

    /// Create a migrator.
    ///
    /// - Parameters:
    ///   - database: A connected Spectro client.
    ///   - migrationsPath: Path to the migrations directory
    ///     (default: `Sources/Migrations`).
    public init(
        database: SpectroClient,
        migrationsPath: URL? = nil
    ) {
        self.database = database
        self.migrationsPath = migrationsPath
            ?? MigrationGenerator.defaultMigrationsDirectory
    }

    // MARK: - Public API

    /// Run all pending migrations.
    ///
    /// Delegates to Spectro's `MigrationManager.runMigrations()` which
    /// executes each migration in a transaction and records it in
    /// `schema_migrations`.
    public func migrate() async throws {
        let manager = database.migrationManager(migrationsPath: migrationsPath)
        try await manager.runMigrations()
    }

    /// List pending migrations without running them (dry-run).
    ///
    /// - Returns: An array of `SpectroCommon.MigrationFile` representing unexecuted migrations.
    public func pending() async throws -> [MigrationFile] {
        let manager = database.migrationManager(migrationsPath: migrationsPath)
        return try await manager.getPendingMigrations()
    }

    /// Rollback the most recent `steps` migrations.
    ///
    /// - Parameter steps: Number of migrations to roll back (default: 1).
    public func rollback(steps: Int = 1) async throws {
        let manager = database.migrationManager(migrationsPath: migrationsPath)
        try await manager.runRollback(steps: steps)
    }

    /// Rollback all migrations after `version`.
    ///
    /// Finds how many applied migrations come after the given version
    /// and rolls them back.
    ///
    /// - Parameter version: The version to rollback to (this version stays applied).
    public func rollback(to version: String) async throws {
        let manager = database.migrationManager(migrationsPath: migrationsPath)
        let applied = try await manager.getAppliedMigrations()

        // Count migrations that come after the target version
        let toRollback = applied.filter { $0.version > version }
        guard !toRollback.isEmpty else { return }

        try await manager.runRollback(steps: toRollback.count)
    }

    /// Redo the last migration (rollback then re-apply).
    ///
    /// Useful during development when iterating on a migration.
    public func redo() async throws {
        try await rollback(steps: 1)
        try await migrate()
    }

    /// Get a rich migration status report.
    ///
    /// - Returns: A ``RoostMigrationReport`` with all discovered migrations
    ///   and their applied/pending status.
    public func status() async throws -> RoostMigrationReport {
        let manager = database.migrationManager(migrationsPath: migrationsPath)
        let (discovered, statuses) = try await manager.getMigrationStatuses()

        let infos = discovered.map { file in
            let applied = statuses[file.version] == .completed
            return RoostMigrationInfo(
                version: file.version,
                name: file.name,
                filePath: file.filePath,
                isApplied: applied
            )
        }

        return RoostMigrationReport(
            database: "current",
            migrations: infos
        )
    }
}
