# Phase 1 Specs Review

**Date:** 2026-04-07  
**Reviewed by:** Claude (Sonnet 4.6)  
**Status:** Ready for refinement

---

## Executive Summary

All 4 Phase 1 specs are well-written and comprehensive, but have several integration issues and scope concerns that should be addressed before implementation:

**Critical Issues:** 3  
**Medium Issues:** 7  
**Minor Issues:** 5  
**Recommendation:** Refine critical issues, approve for implementation planning

---

## 🔴 Critical Issues

### 1. **Spec 22 (Auth & Scopes) - Over-Scope Risk**

**Problem:** This spec is trying to do too much at once:
- Password hashing
- Session authentication
- API token authentication  
- Full Phoenix-style scope system
- Multiple auth plugs (requireAuth, optionalAuth, requireApiAuth, requireRole, requireOwnership, requirePermission)
- Generator hooks for scoped code generation

**Impact:** 1250 lines, likely 3-4 months of implementation work, high risk of scope creep

**Recommendation:** 
- **Option A:** Split into 2 specs:
  - Spec 22A: Basic Auth (password hashing, session helpers, API tokens, requireAuth plug)
  - Spec 22B: Scope System (UserScope, ScopeConfig, fetchCurrentScope plug, requireRole plug)
- **Option B:** Keep as-is but mark as "Phase 1A" and create follow-up "Phase 1B" for advanced features

**Rationale:** Phoenix developed their scope system over years. Trying to implement it all at once is risky.

---

### 2. **Spec 23 (Migrations) - Schema Drift Detection Complexity**

**Problem:** Lines 748-822 in the spec propose complex schema drift detection:

```swift
private static func extractDatabaseSchema(database: SpectroClient) async throws -> DatabaseSchema
private static func extractMigrationSchema(...) throws -> DatabaseSchema
private static func compareSchemas(...) -> DriftReport
```

This requires:
- SQL parsing capability (to read migration files)
- Full information_schema introspection
- Complex diff algorithm

**Impact:** This is a **separate product** in itself (e.g., pgtd, sqitch). Implementing from scratch is delusional.

**Recommendation:**
- Remove `extractMigrationSchema()` - just keep `extractDatabaseSchema()`
- Change drift detection to: "Compares current schema against `.roost/schema.sql` dump"
- Developers update dump manually with `roost db:schema:dump`
- Mark full drift detection as "Future Enhancement"

**Rationale:** Rails doesn't have built-in drift detection. Phoenix doesn't either. This is a nice-to-have, not essential.

---

### 3. **Spec 25 (Validations) - Swift 6 Concurrency Concerns**

**Problem:** The changeset validation system relies heavily on:

```swift
public func validate(_ database: SpectroClient? = nil) async throws
```

Every validator call is async. For validations with 5+ validators, this means:
- 5 separate database round-trips (for uniqueness, associations, etc.)
- Complex error aggregation
- Hard to reason about performance

**Impact:** Could lead to N+1 query problems and slow validation.

**Recommendation:**
- Add batch validation API:
  ```swift
  public func validateBatch(_ database: SpectroClient?) async throws
  ```
- Document that validators should batch their database queries
- Consider adding validation caching for uniqueness checks
- Add performance monitoring section to acceptance criteria

**Rationale:** Swift concurrency is great, but database validation needs to be batched for performance.

---

## 🟡 Medium Issues

### 4. **Spec 22 - Organization Model Assumptions**

**Problem:** Lines 327-329 assume an `Organization` model exists:

```swift
let org = try? await repo?.query(Organization.self)
    .where(\.slug == orgSlug)
    .where(\.userId == currentScope.user!.id)
```

But this model is never defined. What if the user doesn't have organizations?

**Recommendation:**
- Add note: "Organization model must exist or use alternative approach"
- Or make organization optional in the scope system
- Provide example without organizations

---

### 5. **Spec 22 - Silent Failure in fetchCurrentScope()**

**Problem:** Line 289:

```swift
if let user = try? await conn.loadUser(User.self) {
    scope = UserScope.forUser(user)
} else {
    scope = UserScope()  // Empty scope
}
```

Silent failure with `try?` hides errors. Why did loading fail?

**Recommendation:**
- Change to explicit error handling with logging
- Or document that this is intentional (guest access pattern)
- Add `fetchCurrentScope(silent: Bool = true)` parameter

---

### 6. **Spec 23 - Migration File Parsing Complexity**

**Problem:** Lines 579-630 propose parsing SQL files:

```swift
private func parseMigration(content: String, filename: String) throws -> MigrationFile
private func extractMetadata(lines: [String], prefix: String) -> String?
private func extractSQLSection(lines: [String], marker: String) -> String
```

This requires:
- SQL parser (even if simple)
- Metadata extraction from comments
- Section parsing with markers

**Recommendation:**
- Simplify to: UP section must be first, DOWN section must be last
- No section markers needed - just split on a separator comment
- Or use separate files: `20260407_create_users.up.sql` and `20260407_create_users.down.sql`

---

### 7. **Spec 24 - No Test Generation**

**Problem:** User explicitly selected "No tests" during brainstorming, but generators create test files in other sections.

**Recommendation:**
- Remove test file generation from resource generator
- Or add `--skip-tests` flag
- Clarify in spec that tests are developer's responsibility

---

### 8. **Spec 25 - Validation Error Format**

**Problem:** Two different error formats:

1. Field errors: `[String: [String]]` (array of errors per field)
2. Model errors: `[String]` (array of general errors)

But what about:
- Nested validation errors (e.g., user.address.street)?
- Cross-model errors (e.g., "email must belong to same organization as user")?
- I18n support for error messages?

**Recommendation:**
- Document error format clearly
- Add examples of how to handle complex errors
- Add non-goal: "No i18n support for error messages (v2)"
- Add non-goal: "No nested model validation"

---

### 9. **Spec 25 - Changeset.apply() Requirements**

**Problem:** Line 277:

```swift
public func apply() throws -> M {
    guard isValid else {
        throw ValidationError.invalid(self.errors)
    }
    
    var model = original ?? M()
    
    for (key, value) in changes {
        try model.setValue(value, forKey: key)  // ⚠️
    }
```

The `setValue(_:forKey:)` assumes `M` is a `NSObject` or has reflection. Swift's `Codable` doesn't support this.

**Recommendation:**
- Use `Codable` reflection or Mirror API
- Or require models to conform to a `Validatable` protocol
- Or use a builder pattern instead of `apply()`

---

### 10. **Cross-Spec Integration - Circular Dependencies**

**Problem:**
- Spec 22 depends on spec 19 (sessions) ✓
- Spec 23 depends on spec 04 (environment) ✓
- Spec 24 depends on spec 22 (scopes) and spec 23 (migrations) ✓
- Spec 25 depends on spec 22 (scopes) ✓

But spec 22 also references:
- Spec 10 (gen.auth) - "Generated code from roost gen.auth will be updated"
- Spec 19 (sessions) - for session token handling

**Recommendation:**
- Document dependency graph clearly
- Ensure implementation order: 19 → 22 → 24+25 → 23
- Or mark what can be implemented in parallel

---

## 🔵 Minor Issues

### 11. **Spec 22 - Missing Token Expiry Logic**

**Problem:** `AuthToken` has `expiresAt: Date?` but no logic for checking expiry.

**Recommendation:**
- Add `isExpired` property
- Document that expired tokens are filtered during validation
- Add acceptance criteria for token expiry

---

### 12. **Spec 23 - Migration Rollback Risks**

**Problem:** DOWN migrations use `DROP TABLE` and `DROP COLUMN`. This is dangerous in production.

**Recommendation:**
- Add safety warning in docs
- Add `--force` flag for destructive operations
- Or prohibit DOWN migrations in production environment

---

### 13. **Spec 24 - Template System Not Fully Specified**

**Problem:** Spec says "built-in Swift templates" but doesn't show:
- Where templates are stored
- How to override templates
- Template syntax reference

**Recommendation:**
- Add section: "Template storage in Sources/RoostCLI/Templates/"
- Add non-goal: "No custom templates (v2)"
- Or reference template files directly

---

### 14. **Spec 25 - Validation Performance**

**Problem:** No discussion of validation performance. What if I have 10 validators with 3 database queries each?

**Recommendation:**
- Add performance section
- Document best practices (e.g., "use cache for uniqueness checks")
- Add monitoring hooks

---

### 15. **All Specs - Missing Error Handling Examples**

**Problem:** All specs show happy paths, but few show error handling.

**Recommendation:**
- Add "Error Handling" section to each spec
- Show examples of common errors and how to handle them
- Document error recovery strategies

---

## 🎯 Recommendations

### Immediate Actions (Before Implementation)

1. **Split Spec 22** into 2 smaller specs (see Issue #1)
2. **Simplify Spec 23** drift detection (see Issue #2)
3. **Add concurrency guidance** to Spec 25 (see Issue #3)
4. **Document dependencies** between all specs
5. **Add error handling examples** to each spec

### Implementation Order

```
Sprint 1: Spec 22A (Basic Auth)
  - Password hashing
  - Session helpers
  - requireAuth plug
  - API tokens (basic)

Sprint 2: Spec 23 (Migrations) 
  - Migration files
  - Version tracking
  - CLI commands
  - (Skip full drift detection)

Sprint 3: Spec 24 (Generators)
  - Model generator
  - Migration generator
  - Context generator
  - Resource generator (basic)

Sprint 4: Spec 22B (Scope System)
  - UserScope
  - ScopeConfig
  - fetchCurrentScope plug
  - Generator hooks

Sprint 5: Spec 25 (Validations)
  - Changeset protocol
  - Built-in validators
  - Async database validators
  - Context integration

Sprint 6: Integration & Polish
  - End-to-end testing
  - Documentation
  - Performance tuning
  - Error handling
```

### Success Metrics

Each spec should have:
- ✅ Clear acceptance criteria (< 30 items per spec)
- ✅ Integration tests passing
- ✅ Documentation complete
- ✅ Performance benchmarks
- ✅ Error handling documented
- ✅ Migration guide for existing apps

---

## 📋 Refinement Checklist

Before approving for implementation:

- [ ] All critical issues addressed
- [ ] All medium issues addressed or documented
- [ ] Spec 22 split into 2 specs (or marked as phased)
- [ ] Spec 23 drift detection simplified
- [ ] Spec 25 concurrency guidance added
- [ ] Cross-spec dependencies documented
- [ ] Error handling examples added
- [ ] Performance considerations documented
- [ ] Implementation timeline created
- [ ] Success metrics defined

---

## ✅ Strengths of Current Specs

1. **Comprehensive** - Cover all major functionality
2. **Type-safe** - Leverage Swift's type system well
3. **Testable** - Good test support throughout
4. **Phoenix-inspired** - Battle-tested patterns
5. **Modern** - Swift 6 concurrency, Sendable, async/await
6. **Well-documented** - Clear examples and code snippets
7. **Integration-aware** - Most cross-spec integration is correct

---

## 🎓 Lessons Learned

For Phase 2 specs:
- Keep specs under 800 lines if possible
- Avoid "kitchen sink" specs that do everything
- Prototype complex features before specifying
- Consider implementation timeline when scoping
- Document error handling from the start
- Add performance sections for async operations
- Test integration points between specs
- Get feedback on scope before writing full spec

---

**Overall Assessment:** B+ (Great foundation, needs refinement)

The specs are well-written and comprehensive but suffer from over-scoping in a few areas. With the recommended changes, they'll be production-ready.
