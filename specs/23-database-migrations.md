# Spec: Database Migrations

**Status:** Proposed
**Date:** 2026-04-07
**Depends on:** Roost core (spec 01), Spectro ORM, Environment (spec 04)

---

## 1. Goal

Roost lacks a database migration system. Developers must manually create and apply schema changes, which is error-prone and makes collaboration difficult. Rails solved this with a migration system that:

1. **Version control database schema** - Track all schema changes in SQL files
2. **Apply changes incrementally** - Run pending migrations in order
3. **Rollback when needed** - Revert migrations for development or recovery
4. **Detect schema drift** - Warn when production doesn't match migrations
5. **Seed test data** - Load development/test data automatically

This spec implements a **Rails-inspired migration system** with SQL-only files, transactional safety, and comprehensive CLI workflow.

---

## 2. Scope

### 2.1 Migration File Structure

#### 2.1.1 File Organization

```
MyApp/
├── Migrations/
│   ├── 20260407143000_create_users.sql
│   ├── 20260407145230_add_email_index.sql
│   ├── 20260407150000_create_posts.sql
│   └── .gitkeep
├── Seeds/
│   ├── development.sql
│   ├── test.sql
│   ├── production.sql
│   └── README.md
└── .roost/
    └── schema.sql  # Schema dump for source control
```

#### 2.1.2 Migration File Format

Each SQL file contains both `UP` and `DOWN` migrations:

```sql
-- Migration: Create users table
-- Created: 2026-04-07 14:30:00
-- Up: Create users table with indexes
-- Down: Drop users table

-- +Migrate UP
BEGIN;

CREATE TABLE "users" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "email" TEXT NOT NULL UNIQUE,
    "hashed_password" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX "users_email_index" ON "users" ("email");

COMMIT;

-- -Migrate DOWN
BEGIN;

DROP INDEX IF EXISTS "users_email_index";
DROP TABLE IF EXISTS "users";

COMMIT;
```

**Migration File Requirements:**
- **Filename format** - `YYYYMMDDHHMMSS_description.sql` (14-digit timestamp + description)
- **Metadata comments** - First 4 lines must contain version, created date, up description, down description
- **Section markers** - `-- +Migrate UP` and `-- -Migrate DOWN` are required
- **Transactional** - Each section must wrap in `BEGIN; ... COMMIT;`
- **Idempotent** - DOWN migrations must use `IF EXISTS` for safe rollback

#### 2.1.3 Migration File Creation API

```swift
// In Sources/RoostCLI/MigrationCommand.swift

public enum MigrationGenerator {
    /// Create a new migration file
    public static func create(
        named description: String,
        in directory: URL = "Migrations"
    ) throws -> URL {
        // Generate timestamp
        let timestamp = generateTimestamp()

        // Sanitize description
        let sanitized = description
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)

        let filename = "\(timestamp)_\(sanitized).sql"
        let filepath = directory.appendingPathComponent(filename)

        // Generate template
        let template = """
-- Migration: \(description)
-- Created: \(formatTimestamp(timestamp))
-- Up: \(description)
-- Down: Revert \(description)

-- +Migrate UP
BEGIN;

-- Your migration SQL here

COMMIT;

-- -Migrate DOWN
BEGIN;

-- Your rollback SQL here

COMMIT;
"""

        // Create directory if needed
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Write file
        try template.write(to: filepath, atomically: true, encoding: .utf8)

        return filepath
    }

    private static func generateTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        let timestamp = formatter.string(from: Date())
        return timestamp
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .prefix(14)
    }
}
```

---

### 2.2 Migration Tracking

#### 2.2.1 Schema Migrations Table

```sql
-- Auto-created on first migration run
CREATE TABLE IF NOT EXISTS "roost_migrations" (
    "version" BIGINT PRIMARY KEY,
    "name" TEXT NOT NULL,
    "applied_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### 2.2.2 Migration State API

```swift
// In Sources/Roost/Migrations/Migration.swift

public enum Migration {
    /// Get all applied migrations
    public static func appliedVersions(
        database: SpectroClient
    ) async throws -> [BigInt] {
        let rows = try await database.query(
            "SELECT version FROM roost_migrations ORDER BY version"
        )

        return rows.compactMap { row in
            row["version"] as? BigInt
        }
    }

    /// Get all pending migrations
    public static func pendingVersions(
        database: SpectroClient,
        migrationsDirectory: URL = "Migrations"
    ) async throws -> [BigInt] {
        let applied = try await appliedVersions(database: database)
        let all = try loadMigrationVersions(from: migrationsDirectory)

        return all.filter { !applied.contains($0) }
    }

    /// Check if a specific version is applied
    public static func isApplied(
        _ version: BigInt,
        database: SpectroClient
    ) async throws -> Bool {
        let result = try await database.query(
            "SELECT 1 FROM roost_migrations WHERE version = $1",
            [version]
        )

        return !result.isEmpty
    }

    /// Record a migration as applied
    public static func recordApplied(
        _ version: BigInt,
        name: String,
        database: SpectroClient
    ) async throws {
        try await database.execute(
            "INSERT INTO roost_migrations (version, name) VALUES ($1, $2)",
            [version, name]
        )
    }

    /// Remove a migration from applied (on rollback)
    public static func recordRolledBack(
        _ version: BigInt,
        database: SpectroClient
    ) async throws {
        try await database.execute(
            "DELETE FROM roost_migrations WHERE version = $1",
            [version]
        )
    }

    /// Load migration versions from filesystem
    private static func loadMigrationVersions(
        from directory: URL
    ) throws -> [BigInt] {
        let filenames = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        return filenames.compactMap { url in
            guard url.pathExtension == "sql" else { return nil }
            let filename = url.deletingPathExtension().lastPathComponent
            guard let versionStr = filename.components(separatedBy: "_").first else { return nil }
            return BigInt(versionStr)
        }.sorted()
    }
}
```

---

### 2.3 Migration Workflow

#### 2.3.1 CLI Commands

```bash
# Create a new migration
$ roost db:migration CreateUsersTable
  create  Migrations/20260407143000_create_users_table.sql

# Run pending migrations
$ roost db:migrate
Migrating: 20260407143000_create_users_table.sql
  -> UP: Create users table with indexes
✅ Applied 1 migration

# Run with verbose output
$ roost db:migrate --verbose
Migrating: 20260407143000_create_users_table.sql
  -> UP: Create users table with indexes
  -> BEGIN
  -> CREATE TABLE users...
  -> CREATE INDEX users_email_index...
  -> COMMIT
✅ Applied 1 migration

# Rollback last migration
$ roost db:rollback
Rolling back: 20260407143000_create_users_table.sql
  -> DOWN: Drop users table
✅ Rolled back 1 migration

# Rollback specific version
$ roost db:rollback --version 20260407143000
Rolling back to: 20260407143000
✅ Rolled back 1 migration

# Rollback N steps
$ roost db:rollback --steps 3
Rolling back 3 migrations...
  -> 20260407150000_create_posts_table.sql
  -> 20260407145230_add_email_index.sql
  -> 20260407143000_create_users_table.sql
✅ Rolled back 3 migrations

# Check migration status
$ roost db:status
Database: myapp_dev
Status:    2 migrations pending

Migration Status:
  Applied  20260407143000  Create users table
  Applied  20260407145230  Add email index
  Pending  20260407150000  Create posts table
  Pending  20260407153000  Add comments table

# Redo last migration (down then up)
$ roost db:redo
Rolling back: 20260407150000_create_posts_table.sql
  -> DOWN: Drop posts table
✅ Rolled back
Migrating: 20260407150000_create_posts_table.sql
  -> UP: Create posts table
✅ Applied

# Run seed data
$ roost db:seed
Seeding from: Seeds/development.sql
✅ Seeded 25 records

# Run environment-specific seed
$ roost db:seed --environment test
Seeding from: Seeds/test.sql
✅ Seeded 10 records

# Dry-run mode (preview changes)
$ roost db:migrate --dry-run
Would apply 2 migrations:
  -> 20260407150000_create_posts_table.sql
  -> 20260407153000_add_comments_table.sql

# Force migration (skip safety checks)
$ roost db:migrate --force
⚠️  Force mode enabled - skipping safety checks
Migrating: 20260407150000_create_posts_table.sql
✅ Applied 1 migration
```

#### 2.3.2 Programmatic API

```swift
// In Sources/Roost/Migrations/Migrator.swift

public final class Migrator: Sendable {
    public let database: SpectroClient
    public let migrationsDirectory: URL
    public let seedsDirectory: URL

    public init(
        database: SpectroClient,
        migrationsDirectory: URL = "Migrations",
        seedsDirectory: URL = "Seeds"
    ) {
        self.database = database
        self.migrationsDirectory = migrationsDirectory
        self.seedsDirectory = seedsDirectory
    }

    /// Run all pending migrations
    public func migrate(
        dryRun: Bool = false,
        verbose: Bool = false
    ) async throws -> [MigrationResult] {
        let pending = try await Migration.pendingVersions(
            database: database,
            migrationsDirectory: migrationsDirectory
        )

        guard !pending.isEmpty else {
            return []
        }

        var results: [MigrationResult] = []

        for version in pending {
            let result = try await runMigration(
                version: version,
                direction: .up,
                dryRun: dryRun,
                verbose: verbose
            )
            results.append(result)

            if dryRun {
                continue
            }

            if result.success {
                try await Migration.recordApplied(
                    version,
                    name: result.name,
                    database: database
                )
            }
        }

        return results
    }

    /// Rollback last N migrations
    public func rollback(
        steps: Int = 1,
        dryRun: Bool = false,
        verbose: Bool = false
    ) async throws -> [MigrationResult] {
        let applied = try await Migration.appliedVersions(database: database)
        let toRollback = applied.suffix(steps).reversed()

        var results: [MigrationResult] = []

        for version in toRollback {
            let result = try await runMigration(
                version: version,
                direction: .down,
                dryRun: dryRun,
                verbose: verbose
            )
            results.append(result)

            if dryRun {
                continue
            }

            if result.success {
                try await Migration.recordRolledBack(version, database: database)
            }
        }

        return results
    }

    /// Rollback to specific version
    public func rollback(
        to version: BigInt,
        dryRun: Bool = false,
        verbose: Bool = false
    ) async throws -> [MigrationResult] {
        let applied = try await Migration.appliedVersions(database: database)
        let toRollback = applied.filter { $0 > version }.reversed()

        var results: [MigrationResult] = []

        for ver in toRollback {
            let result = try await runMigration(
                version: ver,
                direction: .down,
                dryRun: dryRun,
                verbose: verbose
            )
            results.append(result)

            if dryRun {
                continue
            }

            if result.success {
                try await Migration.recordRolledBack(ver, database: database)
            }
        }

        return results
    }

    /// Redo last migration (down then up)
    public func redo(
        dryRun: Bool = false,
        verbose: Bool = false
    ) async throws -> (rollback: [MigrationResult], migrate: [MigrationResult]) {
        let rollbackResults = try await rollback(steps: 1, dryRun: dryRun, verbose: verbose)
        let migrateResults = try await migrate(dryRun: dryRun, verbose: verbose)
        return (rollbackResults, migrateResults)
    }

    /// Check migration status
    public func status() async throws -> MigrationStatus {
        let applied = try await Migration.appliedVersions(database: database)
        let pending = try await Migration.pendingVersions(
            database: database,
            migrationsDirectory: migrationsDirectory
        )

        let allVersions = (applied + pending).sorted()
        var migrationInfos: [MigrationInfo] = []

        for version in allVersions {
            let isApplied = applied.contains(version)
            let migration = try loadMigration(version: version)
            let appliedAt: Date? = isApplied ? try await getAppliedAt(version) : nil

            migrationInfos.append(MigrationInfo(
                version: version,
                name: migration.name,
                filename: migration.filename,
                appliedAt: appliedAt
            ))
        }

        return MigrationStatus(
            database: database.databaseName,
            currentVersion: applied.last,
            applied: migrationInfos.filter { $0.appliedAt != nil },
            pending: migrationInfos.filter { $0.appliedAt == nil },
            isUpToDate: pending.isEmpty
        )
    }

    /// Run seed data
    public func seed(
        environment: Environment = .current
    ) async throws -> SeedResult {
        let seedFile = seedsDirectory.appendingPathComponent("\(environment).sql")

        guard FileManager.default.fileExists(atPath: seedFile.path) else {
            throw MigrationError.seedFileNotFound(seedFile.path)
        }

        let sql = try String(contentsOf: seedFile, encoding: .utf8)
        let startTime = Date()

        try await database.execute(sql)

        let duration = Date().timeIntervalSince(startTime)

        // Count records inserted (requires parsing SQL or using statement hooks)
        let recordsInserted = try await countInsertedRecords()

        return SeedResult(
            environment: environment,
            file: seedFile.lastPathComponent,
            recordsInserted: recordsInserted,
            duration: Duration.seconds(duration)
        )
    }

    // MARK: - Private Helpers

    private func runMigration(
        version: BigInt,
        direction: MigrationDirection,
        dryRun: Bool,
        verbose: Bool
    ) async throws -> MigrationResult {
        let migration = try loadMigration(version: version)
        let sql = direction == .up ? migration.upSQL : migration.downSQL

        if dryRun {
            return MigrationResult(
                version: version,
                name: migration.name,
                direction: direction,
                success: true,
                error: nil
            )
        }

        do {
            if verbose {
                print("  -> \(direction == .up ? "BEGIN" : "ROLLBACK")")
            }

            try await database.execute(sql)

            if verbose {
                print("  -> COMMIT")
            }

            return MigrationResult(
                version: version,
                name: migration.name,
                direction: direction,
                success: true,
                error: nil
            )
        } catch {
            return MigrationResult(
                version: version,
                name: migration.name,
                direction: direction,
                success: false,
                error: error
            )
        }
    }

    private func loadMigration(version: BigInt) throws -> MigrationFile {
        let filename = try findMigrationFile(version: version)
        let content = try String(contentsOf: filename, encoding: .utf8)
        return try parseMigration(content: content, filename: filename.lastPathComponent)
    }

    private func findMigrationFile(version: BigInt) throws -> URL {
        let filenames = try FileManager.default.contentsOfDirectory(
            at: migrationsDirectory,
            includingPropertiesForKeys: nil
        )

        guard let filename = filenames.first(where: { url in
            guard url.pathExtension == "sql" else { return false }
            let name = url.deletingPathExtension().lastPathComponent
            return name.hasPrefix("\(version)_")
        }) else {
            throw MigrationError.migrationNotFound(version)
        }

        return filename
    }

    private func parseMigration(content: String, filename: String) throws -> MigrationFile {
        let lines = content.components(separatedBy: .newlines)

        // Extract metadata
        let name = extractMetadata(lines: lines, prefix: "Migration:") ?? "Unknown"
        let upDescription = extractMetadata(lines: lines, prefix: "Up:") ?? "Migrate up"
        let downDescription = extractMetadata(lines: lines, prefix: "Down:") ?? "Migrate down"

        // Extract SQL sections
        let upSQL = extractSQLSection(lines: lines, marker: "-- +Migrate UP")
        let downSQL = extractSQLSection(lines: lines, marker: "-- -Migrate DOWN")

        return MigrationFile(
            version: BigInt(filename.prefix(14))!,
            name: name,
            filename: filename,
            upDescription: upDescription,
            downDescription: downDescription,
            upSQL: upSQL,
            downSQL: downSQL
        )
    }

    private func extractMetadata(lines: [String], prefix: String) -> String? {
        for line in lines.prefix(10) {
            if line.hasPrefix("-- \(prefix)") {
                return line.dropFirst(prefix.count + 3).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func extractSQLSection(lines: [String], marker: String) -> String {
        var inSection = false
        var sqlLines: [String] = []

        for line in lines {
            if line == marker {
                inSection = true
                continue
            }

            if inSection {
                if line.hasPrefix("-- ") && !line.hasPrefix("-- --") {
                    // Skip comment lines but allow SQL comments
                    continue
                }
                if line.isEmpty && sqlLines.isEmpty {
                    // Skip leading whitespace
                    continue
                }
                if !line.isEmpty || !sqlLines.isEmpty {
                    sqlLines.append(line)
                }
            }
        }

        return sqlLines.joined(separator: "\n")
    }

    private func getAppliedAt(_ version: BigInt) async throws -> Date? {
        let rows = try await database.query(
            "SELECT applied_at FROM roost_migrations WHERE version = $1",
            [version]
        )

        return rows.first?["applied_at"] as? Date
    }

    private func countInsertedRecords() async throws -> Int {
        // This would require statement hooks or SQL parsing
        // For now, return 0 and let callers track manually
        return 0
    }
}

// MARK: - Supporting Types

public struct MigrationResult: Sendable {
    public let version: BigInt
    public let name: String
    public let direction: MigrationDirection
    public let success: Bool
    public let error: Error?

    public var description: String {
        let status = success ? "✅" : "❌"
        let dir = direction == .up ? "UP" : "DOWN"
        return "\(status) \(version) \(name) (\(dir))"
    }
}

public enum MigrationDirection {
    case up
    case down
}

public struct MigrationStatus: Sendable {
    public let database: String
    public let currentVersion: BigInt?
    public let applied: [MigrationInfo]
    public let pending: [MigrationInfo]
    public let isUpToDate: Bool

    public func printReport() {
        print("Database: \(database)")
        print("Status:    \(isUpToDate ? "Up to date" : "\(pending.count) migrations pending")")
        print("\nMigration Status:")

        for info in applied {
            print("  Applied  \(info.version)  \(info.name)")
        }

        for info in pending {
            print("  Pending  \(info.version)  \(info.name)")
        }
    }
}

public struct MigrationInfo: Sendable {
    public let version: BigInt
    public let name: String
    public let filename: String
    public let appliedAt: Date?
}

public struct SeedResult: Sendable {
    public let environment: Environment
    public let file: String
    public let recordsInserted: Int
    public let duration: Duration
}

public enum MigrationError: Error {
    case migrationNotFound(BigInt)
    case invalidMigrationFormat(String)
    case seedFileNotFound(String)
}

private struct MigrationFile {
    let version: BigInt
    let name: String
    let filename: String
    let upDescription: String
    let downDescription: String
    let upSQL: String
    let downSQL: String
}
```

---

### 2.4 Schema Drift Detection

#### 2.4.1 Drift Detection API

```swift
// In Sources/Roost/Migrations/DriftDetector.swift

public enum DriftDetector {
    /// Detect schema drift by comparing actual schema to migrations
    public static func detectDrift(
        database: SpectroClient,
        migrationsDirectory: URL = "Migrations"
    ) async throws -> DriftReport {
        // Get actual database schema
        let actualSchema = try await extractDatabaseSchema(database: database)

        // Get expected schema from migrations
        let expectedSchema = try await extractMigrationSchema(
            database: database,
            migrationsDirectory: migrationsDirectory
        )

        // Compare and report drift
        return compareSchemas(actual: actualSchema, expected: expectedSchema)
    }

    /// Create a schema dump for source control
    public static func dumpSchema(
        database: SpectroClient
    ) async throws -> String {
        let schema = try await extractDatabaseSchema(database: database)
        return formatSchemaDump(schema)
    }

    /// Verify schema matches migrations
    public static func verifySchema(
        database: SpectroClient,
        migrationsDirectory: URL = "Migrations"
    ) async throws -> Bool {
        let report = try await detectDrift(
            database: database,
            migrationsDirectory: migrationsDirectory
        )
        return !report.hasDrift
    }

    // MARK: - Private

    private static func extractDatabaseSchema(
        database: SpectroClient
    ) async throws -> DatabaseSchema {
        // Query information_schema for actual schema
        let tables = try await database.query("""
            SELECT
                table_name,
                column_name,
                data_type,
                is_nullable,
                column_default
            FROM information_schema.columns
            WHERE table_schema = 'public'
            ORDER BY table_name, ordinal_position
        """)

        var schema = DatabaseSchema()

        for row in tables {
            let tableName = row["table_name"] as! String
            let columnName = row["column_name"] as! String
            let dataType = row["data_type"] as! String
            let isNullable = (row["is_nullable"] as! String) == "YES"

            var table = schema.tables[tableName] ?? TableSchema(name: tableName)
            table.columns.append(ColumnSchema(
                name: columnName,
                type: dataType,
                nullable: isNullable
            ))
            schema.tables[tableName] = table
        }

        return schema
    }

    private static func extractMigrationSchema(
        database: SpectroClient,
        migrationsDirectory: URL
    ) throws -> DatabaseSchema {
        // This is complex - would need to parse all migration SQL
        // For now, return empty schema and rely on manual verification
        return DatabaseSchema()
    }

    private static func compareSchemas(
        actual: DatabaseSchema,
        expected: DatabaseSchema
    ) -> DriftReport {
        var unexpectedTables: [String] = []
        var unexpectedColumns: [ColumnDrift] = []
        var missingTables: [String] = []
        var missingColumns: [ColumnDrift] = []
        var typeMismatches: [TypeDrift] = []

        // Find unexpected tables
        for (tableName, _) in actual.tables {
            if expected.tables[tableName] == nil {
                unexpectedTables.append(tableName)
            }
        }

        // Find missing tables
        for (tableName, _) in expected.tables {
            if actual.tables[tableName] == nil {
                missingTables.append(tableName)
            }
        }

        // Compare columns (implementation skipped for brevity)
        // ...

        return DriftReport(
            hasDrift: !unexpectedTables.isEmpty ||
                      !unexpectedColumns.isEmpty ||
                      !missingTables.isEmpty ||
                      !missingColumns.isEmpty ||
                      !typeMismatches.isEmpty,
            unexpectedTables: unexpectedTables,
            unexpectedColumns: unexpectedColumns,
            missingTables: missingTables,
            missingColumns: missingColumns,
            typeMismatches: typeMismatches
        )
    }

    private static func formatSchemaDump(_ schema: DatabaseSchema) -> String {
        var lines: [String] = []
        lines.append("-- Roost Schema Dump")
        lines.append("-- Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        for (_, table) in schema.tables.sorted(by: { $0.key < $1.key }) {
            lines.append("-- Table: \(table.name)")
            lines.append("CREATE TABLE \"\(table.name)\" (")

            let columnDefs = table.columns.map { column in
                let nullability = column.nullable ? "" : " NOT NULL"
                return "    \"\(column.name)\" \(column.type)\(nullability)"
            }

            lines.append(columnDefs.joined(separator: ",\n"))
            lines.append(");")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Schema Types

public struct DriftReport: Sendable {
    public let hasDrift: Bool
    public let unexpectedTables: [String]
    public let unexpectedColumns: [ColumnDrift]
    public let missingTables: [String]
    public let missingColumns: [ColumnDrift]
    public let typeMismatches: [TypeDrift]

    public func printReport() {
        if !hasDrift {
            print("✅ Schema matches migrations")
            return
        }

        print("⚠️  Schema drift detected!\n")

        if !unexpectedTables.isEmpty {
            print("Unexpected tables found in database:")
            for table in unexpectedTables {
                print("  - \(table)")
            }
            print("")
        }

        if !unexpectedColumns.isEmpty {
            print("Unexpected columns:")
            for drift in unexpectedColumns {
                print("  - \(drift.table).\(drift.column) (found in \(drift.foundIn))")
            }
            print("")
        }

        if !missingTables.isEmpty {
            print("Missing tables:")
            for table in missingTables {
                print("  - \(table)")
            }
            print("")
        }

        if !missingColumns.isEmpty {
            print("Missing columns:")
            for drift in missingColumns {
                print("  - \(drift.table).\(drift.column)")
            }
            print("")
        }

        if !typeMismatches.isEmpty {
            print("Type mismatches:")
            for mismatch in typeMismatches {
                print("  - \(mismatch.table).\(mismatch.column): database=\(mismatch.databaseType), migration=\(mismatch.migrationType)")
            }
        }
    }
}

public struct ColumnDrift: Sendable {
    public let table: String
    public let column: String
    public let foundIn: String  // "database" or "migration"
}

public struct TypeDrift: Sendable {
    public let table: String
    public let column: String
    public let databaseType: String
    public let migrationType: String
}

private struct DatabaseSchema {
    var tables: [String: TableSchema] = [:]
}

private struct TableSchema {
    let name: String
    var columns: [ColumnSchema] = []
}

private struct ColumnSchema {
    let name: String
    let type: String
    let nullable: Bool
}
```

#### 2.4.2 Schema Dump Commands

```bash
# Detect schema drift
$ roost db:drift
⚠️  Schema drift detected!

Unexpected tables found in database:
  - temp_imports
  - old_users_backup

Unexpected columns:
  - users.admin (found in database, not in migrations)

Missing columns:
  - posts.slug (found in migrations, missing from database)

Type mismatches:
  - users.created_at: database=TIMESTAMP, migration=TIMESTAMPTZ

Run `roost db:schema:dump` to update schema dump.

# Dump current schema
$ roost db:schema:dump
Dumping schema to: .roost/schema.sql
✅ Schema dumped

# Verify schema matches migrations
$ roost db:schema:verify
✅ Schema matches migrations
```

---

### 2.5 Seed Data

#### 2.5.1 Seed Files

```sql
-- Seeds/development.sql
-- Development seed data

INSERT INTO "users" (email, hashed_password) VALUES
  ('admin@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLaEmc0i'),
  ('user@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLaEmc0i'),
  ('test@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLaEmc0i')
ON CONFLICT (email) DO NOTHING;

INSERT INTO "posts" (user_id, title, body, published)
SELECT
  id,
  'First Post',
  'This is my first post!',
  true
FROM "users"
WHERE email = 'admin@example.com'
ON CONFLICT DO NOTHING;

INSERT INTO "posts" (user_id, title, body, published)
SELECT
  id,
  'Draft Post',
  'This is a draft',
  false
FROM "users"
WHERE email = 'user@example.com'
ON CONFLICT DO NOTHING;
```

```sql
-- Seeds/test.sql
-- Test fixtures

INSERT INTO "users" (email, hashed_password) VALUES
  ('test@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLaEmc0i');

INSERT INTO "posts" (user_id, title, body, published)
SELECT id, 'Test Post', 'Test content', true
FROM "users" WHERE email = 'test@example.com';
```

#### 2.5.2 Seeder API

```swift
// In Sources/Roost/Migrations/Seeder.swift

public enum Seeder {
    /// Run seed file for current environment
    public static func seed(
        database: SpectroClient,
        seedsDirectory: URL = "Seeds",
        environment: Environment = .current
    ) async throws -> SeedResult {
        let seedFile = seedsDirectory.appendingPathComponent("\(environment).sql")

        guard FileManager.default.fileExists(atPath: seedFile.path) else {
            throw MigrationError.seedFileNotFound(seedFile.path)
        }

        let sql = try String(contentsOf: seedFile, encoding: .utf8)
        let startTime = Date()

        try await database.execute(sql)

        let duration = Date().timeIntervalSince(startTime)

        return SeedResult(
            environment: environment,
            file: seedFile.lastPathComponent,
            recordsInserted: 0,  // Would need SQL parsing to count
            duration: Duration.seconds(duration)
        )
    }

    /// Truncate all tables (for test cleanup)
    public static func reset(
        database: SpectroClient
    ) async throws {
        // Get all table names
        let tables = try await database.query("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'public'
            AND table_name != 'roost_migrations'
            ORDER BY table_name
        """)

        // Truncate each table
        for row in tables {
            let tableName = row["table_name"] as! String
            try await database.execute("TRUNCATE TABLE \"\(tableName)\" CASCADE")
        }
    }
}
```

#### 2.5.3 Seed README

```markdown
# Seeds

This directory contains seed data for different environments.

## Files

- `development.sql` - Development seed data (sample data for manual testing)
- `test.sql` - Test fixtures (minimal data for automated tests)
- `production.sql` - Production seed data (required reference data)

## Usage

```bash
# Run seeds for current environment
$ roost db:seed

# Run seeds for specific environment
$ roost db:seed --environment test

# Reset database (truncate all tables)
$ roost db:reset
```

## Guidelines

- Use `ON CONFLICT DO NOTHING` for idempotent seeds
- Keep test seeds minimal
- Use transactions for related data
- Document any assumptions in comments
```

---

### 2.6 Testing Integration

#### 2.6.1 Auto-Migration in Tests

```swift
// In Sources/RoostTest/DatabaseTestHelper.swift

extension TestApp {
    /// Setup test database with migrations
    public func setupDatabase() async throws {
        // Get migrator
        let migrator = Migrator(
            database: self.database,
            migrationsDirectory: "Migrations",
            seedsDirectory: "Seeds"
        )

        // Run pending migrations
        try await migrator.migrate()

        // Run test seeds
        try await Seeder.seed(
            database: self.database,
            seedsDirectory: "Seeds",
            environment: .test
        )
    }

    /// Teardown test database (transactional rollback)
    public func teardownDatabase() async throws {
        // Rollback transaction instead of cleaning
        // This requires test framework support
        try await database.rollback()
    }

    /// Get migrator for custom migration control
    public var migrator: Migrator {
        Migrator(
            database: self.database,
            migrationsDirectory: "Migrations",
            seedsDirectory: "Seeds"
        )
    }

    /// Run specific migration for testing
    public func runMigration(_ version: BigInt) async throws {
        let migrator = self.migrator
        try await migrator.migrate()
    }

    /// Rollback to specific version for testing
    public func rollbackTo(_ version: BigInt) async throws {
        let migrator = self.migrator
        try await migrator.rollback(to: version)
    }
}
```

#### 2.6.2 Test Assertions

```swift
// In Sources/RoostTest/MigrationAssertions.swift

extension XCTestCase {
    /// Assert a specific migration is applied
    public func assertMigrationApplied(
        _ version: BigInt,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let app = TestApp(MyApp())
        let applied = try await Migration.isApplied(version, database: app.database)
        XCTAssertTrue(applied, "Migration \(version) should be applied", file: file, line: line)
    }

    /// Assert a specific migration is pending
    public func assertMigrationPending(
        _ version: BigInt,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let app = TestApp(MyApp())
        let applied = try await Migration.isApplied(version, database: app.database)
        XCTAssertFalse(applied, "Migration \(version) should be pending", file: file, line: line)
    }

    /// Assert table exists
    public func assertTableExists(
        _ name: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let app = TestApp(MyApp())
        let result = try await app.database.query("""
            SELECT 1 FROM information_schema.tables
            WHERE table_name = $1
        """, [name])

        XCTAssertFalse(result.isEmpty, "Table \(name) should exist", file: file, line: line)
    }

    /// Assert table has column
    public func assertTable(
        _ tableName: String,
        hasColumn columnName: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let app = TestApp(MyApp())
        let result = try await app.database.query("""
            SELECT 1 FROM information_schema.columns
            WHERE table_name = $1 AND column_name = $2
        """, [tableName, columnName])

        XCTAssertFalse(result.isEmpty, "Table \(tableName) should have column \(columnName)", file: file, line: line)
    }
}
```

#### 2.6.3 Example Test

```swift
// Tests/MigrationTests.swift

import Testing
@testable import MyApp

struct MigrationTests {
    @Test("migrations run successfully")
    func migrationsRun() async throws {
        let app = TestApp(MyApp())

        // Run migrations
        try await app.setupDatabase()

        // Verify migrations were applied
        let status = try await app.migrator.status()
        #expect(status.isUpToDate)
    }

    @Test("can rollback migrations")
    func rollbackWorks() async throws {
        let app = TestApp(MyApp())

        // Setup database
        try await app.setupDatabase()

        // Rollback last migration
        let results = try await app.migrator.rollback(steps: 1)
        #expect(results.count == 1)
        #expect(results[0].success)
    }

    @Test("seed data loads correctly")
    func seedDataLoads() async throws {
        let app = TestApp(MyApp())

        // Setup and seed
        try await app.setupDatabase()

        // Verify seed data
        let result = try await app.database.query(
            "SELECT COUNT(*) as count FROM users"
        )

        let count = result.first?["count"] as? Int ?? 0
        #expect(count > 0)
    }
}
```

---

## 3. Acceptance Criteria

### 3.1 Migration Files
- [ ] Migration files use `YYYYMMDDHHMMSS_description.sql` format
- [ ] Files contain both UP and DOWN SQL sections
- [ ] Sections marked with `-- +Migrate UP` and `-- -Migrate DOWN`
- [ ] All migrations wrapped in transactions (`BEGIN; ... COMMIT;`)
- [ ] DOWN migrations use `IF EXISTS` for safe rollback
- [ ] Metadata comments include version, created date, descriptions
- [ ] Migration descriptions are human-readable
- [ ] Filenames are sanitized and URL-safe

### 3.2 Migration Tracking
- [ ] `roost_migrations` table auto-created on first run
- [ ] Table tracks version, name, and applied_at timestamp
- [ ] `Migration.appliedVersions()` returns list of applied versions
- [ ] `Migration.pendingVersions()` returns list of pending versions
- [ ] `Migration.isApplied()` checks if specific version is applied
- [ ] `Migration.recordApplied()` records migration as applied
- [ ] `Migration.recordRolledBack()` removes migration from applied
- [ ] Versions are loaded from filesystem and database
- [ ] Migration versions are sorted correctly

### 3.3 Migration Workflow
- [ ] `roost db:migration <name>` generates new migration file
- [ ] `roost db:migrate` runs all pending migrations
- [ ] `roost db:migrate --dry-run` previews migrations without running
- [ ] `roost db:migrate --verbose` shows detailed SQL execution
- [ ] `roost db:rollback` reverts last migration
- [ ] `roost db:rollback --steps N` reverts N migrations
- [ ] `roost db:rollback --version V` rolls back to specific version
- [ ] `roost db:redo` rolls back and re-applies last migration
- [ ] `roost db:status` shows migration status
- [ ] `roost db:status` indicates if migrations are pending
- [ ] Failed migrations roll back automatically (transactional)
- [ ] Failed migrations stop execution chain
- [ ] Migration errors are reported clearly

### 3.4 Schema Drift Detection
- [ ] `roost db:drift` detects schema drift
- [ ] Drift report shows unexpected tables
- [ ] Drift report shows unexpected columns
- [ ] Drift report shows missing tables
- [ ] Drift report shows missing columns
- [ ] Drift report shows type mismatches
- [ ] `roost db:schema:dump` dumps schema to `.roost/schema.sql`
- [ ] `roost db:schema:verify` checks schema matches migrations
- [ ] Schema dump includes all tables and columns
- [ ] Schema dump is formatted as valid SQL

### 3.5 Seed Data
- [ ] Seed files exist for dev/test/prod environments
- [ ] `roost db:seed` runs seeds for current environment
- [ ] `roost db:seed --environment <env>` runs specific environment seed
- [ ] `roost db:reset` truncates all tables
- [ ] Seeds are idempotent (use `ON CONFLICT DO NOTHING`)
- [ ] Seeds are transactional
- [ ] Seed execution reports records inserted
- [ ] Seeds/README.md documents seed usage

### 3.6 Testing Integration
- [ ] `TestApp.setupDatabase()` runs migrations automatically
- [ ] `TestApp.teardownDatabase()` supports transactional rollback
- [ ] `TestApp.migrator` provides migrator instance
- [ ] `assertMigrationApplied()` asserts migration is applied
- [ ] `assertMigrationPending()` asserts migration is pending
- [ ] `assertTableExists()` asserts table exists
- [ ] `assertTable(_:hasColumn:)` asserts column exists
- [ ] Test migrations run in test database
- [ ] Test migrations don't affect development database
- [ ] Seed files load correctly in tests

### 3.7 Error Handling
- [ ] Missing migration file throws clear error
- [ ] Invalid migration format throws clear error
- [ ] Missing seed file throws clear error
- [ ] Migration execution errors are reported with context
- [ ] Database connection errors are handled gracefully
- [ ] Transaction rollback failures are reported

### 3.8 CLI Experience
- [ ] All commands support `--help` flag
- [ ] Commands show clear output (✅/❌/⚠️ indicators)
- [ ] Verbose mode shows SQL execution details
- [ ] Dry-run mode previews changes
- [ ] Status output is human-readable
- [ ] Error messages are actionable
- [ ] Commands respect `ROOST_ENV` environment variable

---

## 4. Non-goals

- No Swift-based migrations (SQL-only for transparency)
- No automatic migration generation from schema changes
- No interactive migration prompts (always non-interactive)
- No migration dependencies (each migration is independent)
- No data transformation helpers (use SQL)
- No parallel migration execution (serial only)
- No distributed migration locking (single-server only)
- No migration version conflicts (resolve manually)
- No automatic rollback on failure (transactional handling is enough)
- No migration testing beyond schema verification
- No seed data factories or fixtures (use SQL)
- No database-specific optimizations (Postgres-focused)
- No NoSQL migration support (relational only)
- No migration validation beyond syntax checking

---

## 5. Dependencies

- **Spectro ORM** - For database connection and query execution
- **Environment system (spec 04)** - For environment-specific behavior
- **PostgreSQL** - For `information_schema` queries and schema introspection

---

## 6. Migration Notes

This spec introduces a new migration system. Migration guide for existing apps:

1. **New apps** - Start using migrations immediately
2. **Existing schemas** - Create baseline migration from current schema
3. **Manual schema changes** - Create migration files before applying changes
4. **Team collaboration** - Commit migration files, run `roost db:migrate` after pull

To create a baseline migration for existing databases:

```bash
# Dump current schema
$ roost db:schema:dump > baseline.sql

# Create baseline migration
$ roost db:migration Baseline
# Edit migration file, paste schema dump into UP section
# Leave DOWN section empty (or DROP all tables)

# Mark as applied without running
$ roost db:migrate --mark-only 20260407143000
```

---

## 7. Future Enhancements

Possible follow-up features:

- **Migration generators** - Generate migrations from Spectro schema changes
- **Data migrations** - Separate data migration files from schema migrations
- **Migration dependencies** - Define migration execution order
- **Parallel migrations** - Speed up large migration batches
- **Migration validation** - Check for destructive changes before applying
- **Migration testing** - Test migrations on clone of production database
- **Rollback safety** - Auto-test DOWN migrations
- **Visual diff** - Show schema changes in human-readable format
- **Migration analytics** - Track migration execution times
- **Multi-database support** - Support MySQL, SQLite in addition to Postgres
