# Spec 23 Refinements - Database Migrations

**Date:** 2026-04-07  
**Status:** Ready for Implementation

---

## 🎯 Overview

Spec 23 (Database Migrations) is well-designed, but Section 2.4 (Schema Drift Detection) is over-engineered. This document provides simplified alternatives.

---

## 🔧 Critical Refinement: Simplify Drift Detection

### Current Problem (Lines 763-1042)

The current drift detection implementation:
1. Parses all migration SQL files to extract expected schema
2. Queries `information_schema` for actual schema
3. Compares both schemas to find differences

**Complexity Issues:**
- Requires SQL parser (even if simple)
- Migration file parsing is error-prone
- Complex diff algorithm
- 280+ lines of code for one feature

**Reality Check:** Rails and Phoenix don't have built-in drift detection. This is typically handled by external tools (pgtd, sqitch, etc.).

---

### ✅ Recommended Solution: Snapshot-Based Drift Detection

**Replace Section 2.4 entirely with:**

```swift
// In Sources/Roost/Migrations/DriftDetector.swift

public enum DriftDetector {
    /// Detect schema drift by comparing actual database schema to snapshot file
    /// 
    /// **How it works:**
    /// 1. Extract current database schema via `information_schema`
    /// 2. Load expected schema from `.roost/schema.sql` snapshot file
    /// 3. Compare both schemas and report differences
    ///
    /// **Workflow:**
    /// - Run migrations: `roost db:migrate`
    /// - Update snapshot: `roost db:schema:dump`
    /// - Commit snapshot to git: `git add .roost/schema.sql`
    /// - Check drift in CI: `roost db:drift`
    ///
    /// - Parameters:
    ///   - database: Database connection
    ///   - snapshotFile: Path to .roost/schema.sql (default: .roost/schema.sql)
    /// - Returns: Drift report with differences
    /// - Throws: ReadError if snapshot file doesn't exist
    public static func detectDrift(
        database: SpectroClient,
        snapshotFile: URL = URL(fileURLWithPath: ".roost/schema.sql")
    ) async throws -> DriftReport {
        // Get actual database schema
        let actualSchema = try await extractDatabaseSchema(database: database)
    
        // Load expected schema from snapshot file
        let expectedSchema = try loadSchemaSnapshot(from: snapshotFile)
    
        // Compare schemas
        return compareSchemas(actual: actualSchema, expected: expectedSchema)
    }
    
    /// Load schema from snapshot file
    /// - Parameter file: Path to .roost/schema.sql
    /// - Returns: Parsed database schema
    /// - Throws: ReadError if file doesn't exist, ParseError if invalid format
    private static func loadSchemaSnapshot(from file: URL) throws -> DatabaseSchema {
        let content = try String(contentsOf: file, encoding: .utf8)
        return parseSchemaSnapshot(content)
    }
    
    /// Parse CREATE TABLE statements from snapshot
    /// Simple line-by-line parsing (no full SQL parser needed)
    /// - Parameter content: SQL snapshot content
    /// - Returns: Parsed DatabaseSchema
    private static func parseSchemaSnapshot(_ content: String) -> DatabaseSchema {
        let lines = content.components(separatedBy: .newlines)
        var schema = DatabaseSchema()
        var currentTable: TableSchema?
        var inCreateTable = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.hasPrefix("--") || trimmed.isEmpty {
                continue
            }
            
            // Start of CREATE TABLE
            if trimmed.hasPrefix("CREATE TABLE") {
                let tableName = extractTableName(from: trimmed)
                currentTable = TableSchema(name: tableName)
                inCreateTable = true
                continue
            }
            
            // End of CREATE TABLE
            if inCreateTable && trimmed == ");" {
                if let table = currentTable {
                    schema.tables[table.name] = table
                }
                currentTable = nil
                inCreateTable = false
                continue
            }
            
            // Parse column definitions (inside CREATE TABLE)
            if inCreateTable, let table = currentTable {
                if trimmed.hasPrefix("\"") && trimmed.contains(" ") {
                    let columnName = extractColumnName(from: trimmed)
                    let columnType = extractColumnType(from: trimmed)
                    let isNullable = trimmed.contains("NULL")
                    
                    let column = ColumnSchema(
                        name: columnName,
                        type: columnType,
                        nullable: isNullable
                    )
                    table.columns.append(column)
                }
            }
        }
        
        return schema
    }
    
    /// Extract table name from CREATE TABLE statement
    private static func extractTableName(from sql: String) -> String {
        // Extract "table_name" from: CREATE TABLE "table_name" (
        let pattern = Regex #"CREATE TABLE ["']([^"']+)["']"#
        guard let match = try? pattern.firstMatch(in: sql) else {
            return "unknown"
        }
        return String(sql[match.range])
    }
    
    /// Extract column name from: "column_name" TYPE
    private static func extractColumnName(from sql: String) -> String {
        let pattern = #""([^"]+)""#
        guard let match = try? pattern.firstMatch(in: sql) else {
            return "unknown"
        }
        return String(sql[match.range])
    }
    
    /// Extract type from: TYPE or TYPE NOT NULL
    private static func extractColumnType(from sql: String) -> String {
        // Remove column name, everything after is the type
        let trimmed = sql.dropFirst(sql.firstIndex(of: "\"") ?? sql.endIndex)
        let typePart = trimmed.trimmingPrefix("`").trimmingCharacters(in: .whitespaces)
        
        // Remove "NOT NULL" if present
        let type = typePart.replacingOccurrences(of: " NOT NULL", with: "")
            .replacingOccurrences(of: ",$", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        return type
    }
    
    /// Create a schema dump for source control
    /// - Parameter database: Database connection
    /// - Returns: SQL dump of current schema
    /// - Note: Output goes to .roost/schema.sql for version control
    public static func dumpSchema(
        database: SpectroClient
    ) async throws -> String {
        let schema = try await extractDatabaseSchema(database: database)
        return formatSchemaDump(schema)
    }
    
    /// Verify schema matches snapshot
    /// - Parameters:
    ///   - database: Database connection
    ///   - snapshotFile: Path to .roost/schema.sql
    /// - Returns: true if schema matches snapshot, false otherwise
    public static func verifySchema(
        database: SpectroClient,
        snapshotFile: URL = URL(fileURLWithPath: ".roost/schema.sql")
    ) async throws -> Bool {
        let report = try await detectDrift(
            database: database,
            snapshotFile: snapshotFile
        )
        return !report.hasDrift
    }
    
    // MARK: - Private
    
    /// Extract database schema via information_schema
    private static func extractDatabaseSchema(
        database: SpectroClient
    ) async throws -> DatabaseSchema {
        let tables = try await database.query("""
            SELECT
                table_name,
                column_name,
                data_type,
                is_nullable
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
    
    /// Format schema as SQL CREATE TABLE statements
    private static func formatSchemaDump(_ schema: DatabaseSchema) -> String {
        var lines: [String] = []
        lines.append("-- Roost Schema Dump")
        lines.append("-- Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("-- Run `roost db:schema:dump` to update")
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
    
    /// Compare two schemas and find differences
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
        
        // Compare columns for tables that exist in both
        for (tableName, expectedTable) in expected.tables {
            guard let actualTable = actual.tables[tableName] else {
                continue
            }
            
            // Find unexpected columns in actual table
            for column in actualTable.columns {
                if !expectedTable.hasColumn(named: column.name) {
                    unexpectedColumns.append(ColumnDrift(
                        table: tableName,
                        column: column.name,
                        foundIn: "database"
                    ))
                }
            }
            
            // Find missing columns
            for column in expectedTable.columns {
                if !actualTable.hasColumn(named: column.name) {
                    missingColumns.append(ColumnDrift(
                        table: tableName,
                        column: column.name,
                        foundIn: "migration"
                    ))
                }
            }
            
            // Check for type mismatches
            for column in expectedTable.columns {
                if let actualColumn = actualTable.column(named: column.name) {
                    if actualColumn.type != column.type {
                        typeMismatches.append(TypeDrift(
                            table: tableName,
                            column: column.name,
                            databaseType: actualColumn.type,
                            migrationType: column.type
                        ))
                    }
                }
            }
        }
        
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
}

// MARK: - Schema Types

public struct DriftReport: Sendable {
    public let hasDrift: Bool
    public let unexpectedTables: [String]
    public let unexpectedColumns: [ColumnDrift]
    public let missingTables: [String]
    public let missingColumns: [ColumnDrift]
    public let typeMismatches: [TypeDrift]
    
    public var isEmpty: Bool {
        !hasDrift
    }
    
    public func printReport() {
        if !hasDrift {
            print("✅ Schema matches snapshot (.roost/schema.sql)")
            return
        }
        
        print("⚠️  Schema drift detected!\n")
        
        if !unexpectedTables.isEmpty {
            print("Unexpected tables (in DB, not in snapshot):")
            for table in unexpectedTables {
                print("  - \(table)")
            }
            print("")
        }
        
        if !unexpectedColumns.isEmpty {
            print("Unexpected columns (in DB, not in snapshot):")
            for drift in unexpectedColumns {
                print("  - \(drift.table).\(drift.column)")
            }
            print("")
        }
        
        if !missingTables.isEmpty {
            print("Missing tables (in snapshot, not in DB):")
            for table in missingTables {
                print("  - \(table)")
            }
            print("")
        }
        
        if !missingColumns.isEmpty {
            print("Missing columns (in snapshot, not in DB):")
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
        
        print("\nRun `roost db:schema:dump` to update snapshot")
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

// MARK: - Schema Types

private struct DatabaseSchema {
    var tables: [String: TableSchema] = [:]
    
    func table(named name: String) -> TableSchema? {
        tables[name]
    }
}

private struct TableSchema {
    let name: String
    var columns: [ColumnSchema] = []
    
    func hasColumn(named name: String) -> Bool {
        columns.contains { $0.name == name }
    }
}

private struct ColumnSchema {
    let name: String
    let type: String
    let nullable: Bool
}
```

---

### 2. Simplified CLI Commands

**Replace Section 2.4.2 CLI Commands with:**

```bash
# Check for drift against snapshot
$ roost db:drift
⚠️  Schema drift detected!

Unexpected tables (in DB, not in snapshot):
  - temp_imports
  - old_users_backup

Unexpected columns (in DB, not in snapshot):
  - users.admin

Missing columns (in snapshot, not in DB):
  - posts.slug

Type mismatches:
  - users.created_at: database=TIMESTAMP, migration=TIMESTAMPTZ

Run `roost db:schema:dump` to update snapshot

# Update/create snapshot
$ roost db:schema:dump
Dumping schema to: .roost/schema.sql
✅ Schema dumped

# Verify schema matches snapshot
$ roost db:schema:verify
✅ Schema matches snapshot

# Show snapshot status
$ roost db:schema:status
Snapshot file: .roost/schema.sql
Last updated: 2026-04-07 14:30:00
Status: ✅ Up to date
```

---

### 3. Add Non-Goals for Drift Detection

**Add to Section 4 (Non-goals):**

```
- No migration-based drift detection (too complex, use snapshot-based approach)
- No automatic snapshot generation (must run manually)
- No SQL parser for migration files (use simple line-based parsing instead)
- No full schema diff algorithm (use table/column comparison only)
- No automatic migration suggestions (developers handle manually)
```

---

## 📋 Updated Acceptance Criteria

### Replace Section 3 (Acceptance Criteria) Drift Detection subsection:

```
### Schema Drift Detection
- [ ] `roost db:drift` compares database schema against snapshot file
- [ ] `roost db:schema:dump` dumps current schema to .roost/schema.sql
- [ ] `roost db:schema:verify` checks if schema matches snapshot
- [ ] Drift detection reports unexpected tables
- [ ] Drift detection reports unexpected columns
- [ ] Drift detection reports missing tables
- [ ] Drift detection reports type mismatches
- [ ] DriftReport.printReport() shows human-readable output
- [ ] Snapshot file parsing uses simple line-by-line parsing (no SQL parser)
- [ ] Schema snapshot is committed to version control
- [ ] `swift test` passes with drift detection tests
```

---

## 🎓 Implementation Notes

**Snapshot-Based Drift Detection Workflow:**

1. **Initial Setup** (one-time):
   ```bash
   # Run all migrations
   $ roost db:migrate
   
   # Create initial snapshot
   $ roost db:schema:dump
   ✅ Schema dumped to .roost/schema.sql
   
   # Commit to git
   $ git add .roost/schema.sql
   $ git commit -m "Initial schema snapshot"
   ```

2. **Development** (repeat as needed):
   ```bash
   # Create migration
   $ roost generate migration AddColumnToPosts
   # Edit migration file
   $ roost db:migrate
   
   # Update snapshot
   $ roost db:schema:dump
   ✅ Schema dumped
   
   # Commit both migration and snapshot
   $ git add Migrations/ .roost/schema.sql
   $ git commit -m "Add column to posts"
   ```

3. **CI/CD** (automated):
   ```yaml
   # .github/workflows/ci.yml
   - name: Check schema drift
     run: |
       roost db:drift
   ```

**Why This Approach:**
- ✅ Simple to implement (no SQL parser needed)
- ✅ Fast (no migration parsing overhead)
- ✅ Reliable (snapshot is source of truth)
- ✅ Git-friendly (snapshot committed alongside migrations)
- ✅ Industry-standard (Rails uses similar approach with schema.rb)

**What This Doesn't Do:**
- ❌ Parse migration files to extract expected schema
- ❌ Automatically fix drift (developers handle manually)
- ❌ Generate migration suggestions (use external tools)

**External Tools for Advanced Use:**
- **pgtd** - PostgreSQL table diff tool
- **sqitch** - SQL migration system with verification
- **pgscan** - Find table dependencies
- ** ORM tools** - Generate migrations from schema changes

---

**Status:** ✅ Ready for implementation (with simplified drift detection)
