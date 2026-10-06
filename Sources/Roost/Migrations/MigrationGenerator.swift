import Foundation

// MARK: - Migration File Generator

/// Creates new migration SQL files with the correct format for Roost/Spectro.
///
/// Generated files use Spectro-compatible markers (`-- migrate:up` / `-- migrate:down`)
/// and Unix-timestamp-based filenames for compatibility with Spectro's migration manager.
///
/// ```swift
/// let url = try MigrationGenerator.create(
///     named: "Create Users Table",
///     in: URL(fileURLWithPath: "Sources/Migrations")
/// )
/// // Creates: Sources/Migrations/1712504400_create_users_table.sql
/// ```
public enum MigrationGenerator {

    /// Create a new migration file.
    ///
    /// - Parameters:
    ///   - description: Human-readable description (e.g. "Create Users Table").
    ///   - directory: Directory for migration files (default: `Sources/Migrations`).
    ///   - now: Override the timestamp (for testing). Defaults to `Date()`.
    /// - Returns: The URL of the created migration file.
    /// - Throws: ``RoostMigrationError/invalidMigrationName(_:)`` if the
    ///   description is empty.
    @discardableResult
    public static func create(
        named description: String,
        in directory: URL = defaultMigrationsDirectory,
        now: Date = Date()
    ) throws -> URL {
        let sanitized = sanitize(description)
        guard !sanitized.isEmpty else {
            throw RoostMigrationError.invalidMigrationName(description)
        }

        let timestamp = Int(now.timeIntervalSince1970)
        let filename = "\(timestamp)_\(sanitized).sql"
        let filepath = directory.appendingPathComponent(filename)

        let template = migrationTemplate(
            description: description,
            timestamp: timestamp,
            name: sanitized,
            date: now
        )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        try template.write(to: filepath, atomically: true, encoding: .utf8)

        return filepath
    }

    /// Default directory for migration files.
    public static let defaultMigrationsDirectory: URL = {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
            .appendingPathComponent("Migrations")
    }()

    // MARK: - Internal Helpers

    /// Sanitize a description into a snake_case filename component.
    ///
    /// - "Create Users Table" → "create_users_table"
    /// - "add-email-index" → "add_email_index"
    static func sanitize(_ description: String) -> String {
        description
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
            .replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Generate the SQL template content for a new migration.
    static func migrationTemplate(
        description: String,
        timestamp: Int,
        name: String,
        date: Date
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dateString = formatter.string(from: date)

        return """
        -- Migration: \(description)
        -- Version: \(timestamp)_\(name)
        -- Created: \(dateString)

        -- migrate:up

        -- TODO: Write your forward migration SQL here
        -- Example:
        -- CREATE TABLE IF NOT EXISTS "my_table" (
        --     "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        --     "name" TEXT NOT NULL DEFAULT '',
        --     "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        --     "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
        -- );

        -- migrate:down

        -- TODO: Write your rollback SQL here
        -- Example:
        -- DROP TABLE IF EXISTS "my_table";
        """
    }
}
