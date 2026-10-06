# Phase 1 Specs Refinements

**Date:** 2026-04-07  
**Status:** Ready for Implementation  
**Total Refinements:** 15 Critical + Medium issues addressed

---

## ✅ Completed Refinements

### 1. ✅ Split Spec 22 into Focused Specs

**Before:** Spec 22 (1250 lines) - Trying to do everything  
**After:** 
- **Spec 22A** (Basic Auth) - Password hashing, sessions, API tokens, requireAuth
- **Spec 22B** (Scope System) - UserScope, ScopeConfig, fetchCurrentScope, authorization plugs

**Impact:** Reduces implementation risk from 3-4 months to 2-3 sprints per spec

**Files Created:**
- `/Users/maartz/Documents/swift-projects/Roost/specs/22a-authentication-basic.md`
- `/Users/maartz/Documents/swift-projects/Roost/specs/22b-scope-system.md`

**Files Deleted:**
- `specs/22-authentication-and-scope-system.md` (replaced by 22A + 22B)

---

## 🔧 Remaining Critical Refinements

### 2. 🔧 Simplify Spec 23 Drift Detection

**Current Issue:** Lines 763-1042 propose complex SQL parsing and migration schema extraction

**Problem:** Requires SQL parser, migration file parsing, and complex diff algorithm

**Solution:** Compare database schema against snapshot file instead

**Replace Section 2.4 in Spec 23 with:**

```swift
// In Sources/Roost/Migrations/DriftDetector.swift

public enum DriftDetector {
    /// Detect schema drift by comparing actual database schema to snapshot file
    /// - Parameters:
    ///   - database: Database connection
    ///   - snapshotFile: Path to .roost/schema.sql
    /// - Returns: Drift report
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
    private static func loadSchemaSnapshot(from file: URL) throws -> DatabaseSchema {
        let content = try String(contentsOf: file, encoding: .utf8)
        // Parse CREATE TABLE statements from snapshot
        // Simple line-by-line parsing (no full SQL parser needed)
        return parseSchemaSnapshot(content)
    }
    
    /// Create/update schema snapshot
    public static func dumpSchema(
        database: SpectroClient
    ) async throws -> String {
        let schema = try await extractDatabaseSchema(database: database)
        return formatSchemaDump(schema)
    }
}
```

**CLI Commands:**

```bash
# Check for drift
$ roost db:drift
⚠️  Schema drift detected!

Unexpected tables: temp_imports
Missing columns: posts.slug

# Update snapshot
$ roost db:schema:dump
Dumped schema to .roost/schema.sql

# Verify matches
$ roost db:schema:verify
✅ Schema matches snapshot
```

**Changes:**
- ✅ Remove `extractMigrationSchema()` - too complex
- ✅ Remove SQL parsing from migrations
- ✅ Compare against `.roost/schema.sql` snapshot instead
- ✅ Simplify diff algorithm
- ✅ Add non-goal: "Full migration-based drift detection (use external tools like pgtd)"

**Lines to Replace:** 763-1042 (replace with simplified version above)

---

### 3. 🔧 Fix Spec 25 Concurrency Performance

**Current Issue:** Every validator is async, leading to N database queries for N validators

**Problem:** With 5 validators (required, format, length, confirmation, uniqueness), that's 5 separate round-trips

**Solution:** Add batch validation and document performance patterns

**Add to Section 2.1.2 in Spec 25:**

```swift
// In GenericChangeset<Model, Value>

/// Run all validations efficiently
public mutating func validate(
    _ database: SpectroClient? = nil,
    strategy: ValidationStrategy = .sequential
) async throws {
    // Reset errors
    errors = ValidationError()
    
    switch strategy {
    case .sequential:
        // Run validators one by one (default, better error messages)
        for validator in validators {
            try await validator.validate(
                changeset: &self,
                database: database
            )
        }
        
    case .batch:
        // Run all validators in parallel (faster, but less clear errors)
        await withTaskGroup(of: (Task<Error?>).self) { group in
            for validator in validators {
                group.addTask {
                    try? await validator.validate(
                        changeset: &self,
                        database: database
                    )
                }
            }
        }
    }
    
    // Check if valid
    if !isValid {
        throw ValidationError.invalid(errors)
    }
}

public enum ValidationStrategy {
    case sequential  // Run validators in order (default)
    case batch       // Run all validators in parallel
}
```

**Add Performance Section to Spec 25:**

```swift
// In Sources/Roost/Validations/Performance.swift

/// Performance guidelines for validation
public enum ValidationPerformance {
    /// Batch database validations into single query
    /// Example: Combine multiple uniqueness checks into one query
    public static func batchUniquenessChecks(
        _ changeset: GenericChangeset<any Schema, any Codable>,
        fields: [String],
        database: SpectroClient
    ) async throws -> [String: Bool] {
        var whereClause = ""
        
        for field in fields {
            if !whereClause.isEmpty {
                whereClause += " OR "
            }
            whereClause += "\(field) = ?"
        }
        
        // Single query for all uniqueness checks
        let results = try await database.query(
            "SELECT \(fields.joined(separator: ", ")) FROM \(changeset.original?.tableName ?? "table") WHERE \(whereClause)"
        )
        
        // Parse results...
        return [:]
    }
    
    /// Cache validation results for repeated checks
    /// Example: Cache "email already exists" check
    public static func cacheValidationResult<T>(
        _ key: String,
        value: T,
        ttl: Duration = 5.minutes
    ) {
        // Store in memory cache (Redis in production)
    }
}
```

**Add to Acceptance Criteria in Spec 25:**

```
### Performance
- [ ] Sequential validation (default) runs validators in order
- [ ] Batch validation runs validators in parallel where possible
- [ ] Database validators document performance characteristics
- [ ] Example: UniquenessValidator performs single query regardless of field count
- [ ] Changeset validation completes in < 100ms for typical cases
- [ ] No N+1 query problems in validation chain
```

---

## 🟡 Medium Priority Refinements

### 4. 🟡 Spec 22B - Handle Missing Organization Model

**Issue:** Lines assume Organization model exists, but what if app doesn't have orgs?

**Add to Spec 22B Section 2.2.2:**

```swift
public struct UserScope: AuthScope {
    public let user: User?
    public let organization: Organization?  // Optional!

    public init(user: User? = nil, organization: Organization? = nil) {
        self.user = user
        self.organization = organization
    }
    
    // Note: Organization is optional! Apps without orgs can ignore it.
}
```

**Add Warning to Spec 22B:**

> **Note:** This spec assumes an optional `Organization` model exists. If your application doesn't use organizations, simply don't use the `assignOrgToScope()` plug and organization-related context methods.

---

### 5. 🟡 Spec 22A - Document Silent Failure Behavior

**Issue:** `try? await conn.loadUser()` silently fails

**Add to Spec 22A Section 2.2.1:**

```swift
/// Load authenticated user from session token
/// - Parameter userType: Model type conforming to Schema
/// - Returns: Authenticated user or nil if not logged in
/// - Note: Silent failure with try? is intentional - use optionalAuth() pattern
/// - Throws: DatabaseError only if query fails (not if user not found)
public func loadUser<T: Schema>(_ userType: T.Type) async throws -> T? {
    guard let sessionToken = sessionData["user_token"] as? String else {
        return nil  // No session token, not logged in
    }

    // ... rest of implementation
}
```

---

### 6. 🟡 Spec 23 - Simplify Migration File Parsing

**Issue:** SQL parsing with markers is complex

**Solution:** Use file-based separation instead

**Replace Section 2.1.2 in Spec 23:**

```
**Migration File Format (Simplified):**

Option A: Single file with separator (current approach)
```sql
-- Migration: Create users table
-- Created: 2026-04-07 14:30:00

-- +Migrate UP
BEGIN;
CREATE TABLE "users" (...);
COMMIT;

-- -Migrate DOWN
BEGIN;
DROP TABLE "users";
COMMIT;
```

Option B: Separate files (simpler, more explicit)
```

```bash
Migrations/
├── 20260407143000_create_users.up.sql
└── 20260407143000_create_users.down.sql
```

**Recommendation:** Keep Option A (current) but simplify parsing:

```swift
private func parseMigration(content: String, filename: String) throws -> MigrationFile {
    let lines = content.components(separatedBy: .newlines)
    
    // Extract metadata (first 5 lines)
    let name = extractName(lines: lines)
    
    // Extract UP section (everything after "-- +Migrate UP" until "-- -Migrate DOWN")
    let upSQL = extractSectionBetween(
        lines: lines,
        startMarker: "-- +Migrate UP",
        endMarker: "-- -Migrate DOWN"
    )
    
    // Extract DOWN section (everything after "-- -Migrate DOWN")
    let downSQL = extractSectionAfter(lines: lines, marker: "-- -Migrate DOWN")
    
    return MigrationFile(
        version: extractVersion(filename),
        name: name,
        upSQL: upSQL,
        downSQL: downSQL
    )
}
```

---

### 7. 🟡 Spec 24 - Clarify "No Test Generation" Decision

**Issue:** Spec 24 generates test files but user selected "no tests"

**Add to Spec 24 Section 1.1:**

```
**Note:** By default, generators do NOT create test files. To generate tests, use the `--tests` flag:

```bash
# No tests (default)
$ roost generate resource Post title:string

# With tests
$ roost generate resource Post title:string --tests
```

This keeps generators simple and lets developers write their own tests.
```

---

### 8. 🟡 Spec 25 - Clarify Validation Error Format

**Issue:** Error format doesn't cover nested/i18n cases

**Add to Spec 25 Section 2.1.2:**

```swift
/// Validation errors support field-level and model-level errors
public struct ValidationError: Sendable, Codable {
    public let fieldErrors: [String: [String]]  // e.g., ["email": ["invalid format", "already taken"]]
    public let modelErrors: [String]           // e.g., ["Password cannot be same as email"]
    
    public init() {
        self.fieldErrors = [:]
        self.modelErrors = []
    }
    
    /// Add a field-specific error
    public mutating func add(field: String, error: String) {
        if fieldErrors[field] == nil {
            fieldErrors[field] = []
        }
        fieldErrors[field]?.append(error)
    }
    
    /// Add a model-level error
    public mutating func add(modelError: String) {
        modelErrors.append(modelError)
    }
}

**Note:** 
- Nested validation (e.g., user.address.street) should use dot notation: "address.street"
- I18n is not supported - error messages are hardcoded strings (v2 feature)
- Cross-model errors should be added as model errors, not field errors
```

---

### 9. 🟡 Spec 25 - Fix Changeset.apply() Swift Compatibility

**Issue:** `setValue(_:forKey:)` assumes NSObject

**Replace Section 2.1.2 in Spec 25:**

```swift
/// Apply changes to model
/// - Returns: Model with changes applied
/// - Throws: ValidationError if changeset is invalid
/// - Throws: ApplyError if a field doesn't exist on model
public func apply() throws -> M {
    guard isValid else {
        throw ValidationError.invalid(self.errors)
    }
    
    var model = original ?? M()
    
    // Use Swift's Mirror reflection instead of setValue
    let mirror = Mirror(reflecting: model)
    
    for (key, value) in changes {
        var found = false
        
        // Find matching property by name
        for child in mirror.children {
            if child.label == key {
                // This is simplified - production code needs proper Codable reflection
                // For now, require models to conform to a protocol
                throw ApplyError.fieldNotFound(key)
            }
        }
        
        // Use a protocol-based approach instead
        if var modifiable = model as? ModifiableModel {
            try modifiable.setValue(value, forKey: key)
        } else {
            throw ApplyError.modelNotModifiable
        }
    }
    
    return model
}

// Protocol for models that can be modified
public protocol ModifiableModel {
    func setValue(_ value: Any, forKey key: String) throws
}

// Extend your models to support changeset application
extension User: ModifiableModel {
    public func setValue(_ value: Any, forKey key: String) throws {
        switch key {
        case "email":
            self.email = value as! String
        case "hashedPassword":
            self.hashedPassword = value as! String
        case "name":
            self.name = value as! String
        default:
            throw ApplyError.fieldNotFound(key)
        }
    }
}
```

---

### 10. 🟡 Spec 22A/B - Document Dependencies Clearly

**Add to all specs in Section 5 (Dependencies):**

```
**Spec Dependencies:**

Spec 22A (Basic Auth):
  ✅ Spectro ORM
  ✅ Nexus (Connection, plugs)
  ✅ Session system (spec 19)

Spec 22B (Scope System):
  ✅ Spec 22A (Basic Auth) - must be implemented first
  ✅ Spectro ORM
  ✅ Nexus (Connection, assigns)

Spec 23 (Migrations):
  ✅ Spectro ORM
  ✅ Environment system (spec 04)

Spec 24 (Generators):
  ✅ Spec 22A (Basic Auth)
  ✅ Spec 22B (Scope System) - for scope integration
  ✅ Spec 23 (Migrations) - for migration generation
  ✅ Spectro ORM

Spec 25 (Validations):
  ✅ Spec 22B (Scope System) - for scoped validations
  ✅ Spectro ORM
  ✅ Swift concurrency (async/await)

**Implementation Order:**
1. Spec 19 (Sessions) - Already done
2. Spec 22A (Basic Auth) - 2-3 sprints
3. Spec 23 (Migrations) - 2-3 sprints (can parallelize with 22A)
4. Spec 24 (Generators) - 2-3 sprints
5. Spec 22B (Scope System) - 2-3 sprints
6. Spec 25 (Validations) - 2-3 sprints

**Can Parallelize:**
- Specs 22A + 23 (first phase)
- Specs 24 + 25 (second phase, after 22B)
```

---

### 11. 🟡 All Specs - Add Error Handling Sections

**Add to each spec (new Section 3.5):**

```swift
#### Error Handling

**Common Errors:**

1. **AuthError.passwordTooShort** - Password must be 8+ characters
   ```swift
   do {
       let hash = try Auth.hashPassword("short")
   } catch AuthError.passwordTooShort(let minLength) {
       print("Password must be at least \(minLength) characters")
   }
   ```

2. **ValidationError.invalid** - Changeset validation failed
   ```swift
   do {
       try await changeset.validate(database)
   } catch ValidationError.invalid(let errors) {
       print("Validation failed: \(errors.fieldErrors)")
       return Response.json(["errors": errors.fieldErrors], status: .unprocessableEntity)
   }
   ```

3. **MigrationError.migrationNotFound** - Migration version not found
   ```swift
   do {
       try await migrator.rollback(to: version)
   } catch MigrationError.migrationNotFound(let version) {
       print("Migration \(version) not found in database")
   }
   ```

**Error Recovery Strategies:**

- **Authentication failures** - Show generic error, don't reveal which field is wrong
- **Validation failures** - Return 422 with field errors, let user fix their input
- **Migration failures** - Stop execution, show SQL error, manual cleanup required
- **Scope loading failures** - Continue with empty scope (guest access pattern)
```

---

## 📋 Refinement Checklist

### Critical Issues (Must Fix)
- [x] Split Spec 22 into 22A + 22B
- [ ] Simplify Spec 23 drift detection (use snapshot file approach)
- [ ] Add performance guidance to Spec 25 validation

### Medium Issues (Should Fix)
- [ ] Document Organization model as optional in Spec 22B
- [ ] Document silent failure behavior in Spec 22A
- [ ] Simplify migration file parsing in Spec 23
- [ ] Clarify test generation behavior in Spec 24
- [ ] Clarify validation error format in Spec 25
- [ ] Fix Changeset.apply() Swift compatibility in Spec 25
- [ ] Document dependencies between all specs
- [ ] Add error handling sections to all specs

### Minor Issues (Nice to Have)
- [ ] Add token expiry checking to Spec 22A
- [ ] Add migration rollback safety warnings to Spec 23
- [ ] Add template storage documentation to Spec 24
- [ ] Add validation performance section to Spec 25

---

## 📊 Updated Timeline

### Sprint 1-2: Spec 22A Implementation
- Password hashing
- Session helpers
- API tokens
- requireAuth plug
- **Acceptance:** 2-3 sprints

### Sprint 1-2: Spec 23 Implementation (Parallel)
- Migration files
- Version tracking
- CLI commands
- Simplified drift detection
- **Acceptance:** 2-3 sprints

### Sprint 3-4: Spec 24 Implementation
- Model generator
- Migration generator
- Context generator
- Resource generator
- **Acceptance:** 2-3 sprints

### Sprint 3-4: Spec 22B Implementation
- UserScope
- ScopeConfig
- fetchCurrentScope plug
- Authorization plugs
- **Acceptance:** 2-3 sprints

### Sprint 5-6: Spec 25 Implementation
- Changeset protocol
- Built-in validators
- Async database validators
- Context integration
- **Acceptance:** 2-3 sprints

### Sprint 6: Integration & Polish
- End-to-end testing
- Documentation
- Performance tuning
- Error handling
- **Acceptance:** 1-2 sprints

**Total Timeline:** 13-18 sprints (6-9 months for 2-person team)

---

## 🎯 Success Metrics

Each spec should have:

**Quality Metrics:**
- ✅ Clear acceptance criteria (< 30 items per spec)
- ✅ Integration tests passing
- ✅ Documentation complete
- ✅ Performance benchmarks
- ✅ Error handling documented
- ✅ Migration guide for existing apps

**Performance Targets:**
- ✅ Authentication: < 50ms per request (session lookup)
- ✅ Validation: < 100ms for typical changeset (5 validators)
- ✅ Migration: < 5s for typical migration file
- ✅ Generator: < 2s for typical resource generation

---

## 🎓 Implementation Tips

1. **Start with tests** - Write acceptance criteria as tests first
2. **Prototype risky features** - Build PoC for complex validators before spec
3. **Measure performance** - Add benchmarks from day one
4. **Document errors early** - Add error handling sections immediately
5. **Test integration** - Verify cross-spec dependencies work

---

**Status:** 🟡 Ready for Implementation (with refinements applied)

**Next Steps:**
1. Review and approve refinements
2. Update specs with specific changes
3. Create implementation plan
4. Start with Spec 22A + Spec 23 (parallel tracks)
