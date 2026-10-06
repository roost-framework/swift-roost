# Spec 22B Refinements - Scope System

**Date:** 2026-04-07  
**Status:** Ready for Implementation

---

## 🎯 Overview

Spec 22B (Scope System) was extracted from the original monolithic Spec 22. This document provides refinements and clarifications.

---

## ✅ What Changed from Original Spec 22

### Moved from Spec 22A (Basic Auth) to Spec 22B
- ✅ AuthScope protocol
- ✅ UserScope and SessionScope implementations
- ✅ ScopeConfig and ScopeMetadata
- ✅ fetchCurrentScope plug
- ✅ assignOrgToScope plug
- ✅ requireRole, requireOwnership, requirePermission plugs
- ✅ Generator hooks integration

---

## 🔧 Specific Refinements

### 1. Organization Model is Optional

**Current Issue:** Spec assumes Organization model exists, but what if app doesn't have organizations?

**Refinement:** Add clear documentation and provide alternative approaches.

**Add to Section 2.2.2 (UserScope Implementation):**

```swift
/// Scope for authenticated users with optional organization context
/// This is the most common scope type for web applications
/// 
/// **Note:** The organization parameter is OPTIONAL. If your application doesn't
/// use organizations, simply:
/// - Don't use the `assignOrgToScope()` plug
/// - Don't pass organization to `UserScope.forUser(_:organization:)`
/// - Ignore organization-related context methods
///
/// Multi-tenant apps can use organizations to isolate data per organization.
public struct UserScope: AuthScope {
    public let user: User?
    public let organization: Organization?

    public static var scopeName: String { "user" }
    public static var scopeDescription: String? { "Scope for authenticated users" }

    public var scopeId: String? { user?.id.uuidString }
    public var isEmpty: Bool { user == nil }

    public init(user: User? = nil, organization: Organization? = nil) {
        self.user = user
        self.organization = organization
    }

    /// Create scope for a user (without organization)
    public static func forUser(_ user: User) -> UserScope {
        UserScope(user: user, organization: nil)
    }

    /// Create scope for a user in an organization
    public static func forUser(_ user: User, organization: Organization) -> UserScope {
        UserScope(user: user, organization: organization)
    }

    /// Add organization to existing scope
    public func withOrganization(_ org: Organization) -> UserScope {
        UserScope(user: self.user, organization: org)
    }

    /// Get scope for testing
    public static func fixture(user: User? = nil, organization: Organization? = nil) -> UserScope {
        UserScope(user: user, organization: organization)
    }
}
```

**Add Usage Examples for Apps Without Organizations:**

```swift
// In your App.swift - single-tenant app
var plugs: [Plug] {
    [
        session(store: .postgres),
        fetchCurrentScope(),  // Will create empty UserScope for guests
        router()
    ]

// In routes - use scope without organization
GET("/posts") { conn in
    let scope = conn.assigns["current_scope"] as! UserScope
    let context = PostsContext(conn: conn, scope: scope)
    
    // This works even without organization!
    let posts = try await context.listPosts()
    return Response.render("posts/index", ["posts": posts])
}
```

---

### 2. Add Scope Testing Examples

**Current Issue:** Testing helpers mentioned but not shown.

**Add to Section 2.2.2 (SessionScope):**

```swift
/// SessionScope for testing
extension SessionScope {
    /// Create a test scope with a specific session ID
    public static func fixture(sessionId: String? = nil) -> SessionScope {
        SessionScope(sessionId: sessionId ?? UUID().uuidString)
    }
}
```

**Add Testing Section to Spec 22B:**

```swift
#### Testing Support

**Test Helpers:**

```swift
// In Sources/RoostTest/ScopeTestHelpers.swift

extension TestApp {
    /// Create a test connection with user scope
    public func withUserScope(user: User) -> Connection {
        var conn = connection()
        let scope = UserScope.forUser(user)
        conn.assigns["current_scope"] = scope
        conn.assigns["current_user"] = user
        conn.sessionData["user_token"] = "dummy-token"
        return conn
    }
    
    /// Create a test connection with user + organization scope
    public func withUserScope(user: User, organization: Organization) -> Connection {
        var conn = connection()
        let scope = UserScope.forUser(user, organization: organization)
        conn.assigns["current_scope"] = scope
        conn.assigns["current_user"] = user
        return conn
    }
    
    /// Create a test connection with guest (empty) scope
    public func withGuestScope() -> Connection {
        var conn = connection()
        let scope = UserScope()  // Empty scope
        conn.assigns["current_scope"] = scope
        return conn
    }
}
```

**Test Examples:**

```swift
// Tests/ScopeTests.swift
import Testing
@testable import MyApp

struct ScopeTests {
    @Test("user scope provides access to user's resources")
    func userScopeScopesResources() async throws {
        let app = TestApp(MyApp())
        let repo = app.database
        
        // Create user1 and user2
        var user1 = User()
        user1.email = "user1@example.com"
        let saved1 = try await repo.save(user1)
        
        var user2 = User()
        user2.email = "user2@example.com"
        let saved2 = try await repo.save(user2)
        
        // Create post for user1
        var post = Post()
        post.userId = saved1.id
        try await repo.save(post)
        
        // Query as user1 - should see post
        let conn1 = app.withUserScope(saved1)
        let context1 = PostsContext(conn: conn1, scope: UserScope.forUser(saved1))
        let posts1 = try await context1.listPosts()
        
        #expect(posts1.count == 1)
        #expect(posts1[0].id == post.id)
        
        // Query as user2 - should NOT see post
        let conn2 = app.withUserScope(saved2)
        let context2 = PostsContext(conn: conn2, scope: UserScope.forUser(saved2))
        let posts2 = try await context2.listPosts()
        
        #expect(posts2.isEmpty)
    }
    
    @Test("guest scope cannot access any resources")
    func guestScopeIsReadOnly() async throws {
        let app = TestApp(MyApp())
        
        // Create a post
        let conn = app.withGuestScope()
        let context = PostsContext(conn: conn, scope: UserScope())
        
        // Should return empty array (guest has no user)
        let posts = try await context.listPosts()
        #expect(posts.isEmpty)
    }
}
```

---

### 3. Clarify assignOrgToScope Behavior

**Current Issue:** What happens if organization doesn't exist or user doesn't have access?

**Refinement:** Document error handling and behavior

**Add to Section 2.3.2:**

```swift
/// Load organization from route params and add to scope
/// Use this for multi-tenant applications where resources belong to organizations
/// 
/// **Behavior:**
/// - Loads organization by slug from route params (e.g., `/orgs/:slug/posts`)
/// - Adds organization to scope if found
/// - Continues without organization if not found (your choice)
/// - Does NOT return 404 - use requireOwnership plug for that
///
/// **Requirements:**
/// - Organization model must exist
/// - Organizations table must have `slug` column
/// - Use in routes like: `scope("/orgs/:slug", through: [requireAuth(), assignOrgToScope()])`
///
/// **Example:**
/// ```swift
/// scope("/orgs/:slug/posts", through: [requireAuth(), assignOrgToScope()]) {
///     GET("/posts") { conn in
///         let scope = conn.assigns["current_scope"] as! UserScope
///         // scope.user is guaranteed to exist (requireAuth)
///         // scope.organization is optional (may be nil if org not found)
///         
///         let context = PostsContext(conn: conn, scope: scope)
///         let posts = try await context.listPostsForOrganization()
///         return Response.render("posts/index", ["posts": posts])
///     }
/// }
/// ```
///
/// - Returns: Plug that enriches scope with organization context
public func assignOrgToScope() -> Plug {
    return { conn in
        Task {
            // Only process if we have a user scope and org param
            guard let currentScope = conn.assigns["current_scope"] as? UserScope,
                  let orgSlug = conn.params["org"],
                  let user = currentScope.user else {
                return conn  // No user or no org param - continue without org
            }

            // Load organization
            let repo = conn.assigns[SpectroKey.self] as? SpectroClient

            let org = try? await repo?.query(Organization.self)
                .where(\.slug == orgSlug)
                .first()

            var updated = conn

            if let org = org {
                // Enrich scope with organization
                updated.assigns["current_scope"] = currentScope.withOrganization(org)
            }
            // If org not found, continue without it (don't fail)

            return updated
        }.value
    }
}
```

---

### 4. Document Role Provider Protocol

**Current Issue:** UserRoleProvider protocol shown but not explained.

**Add to Section 2.4.1:**

```swift
/// Protocol for entities that can provide role information
/// 
/// **Usage:**
/// ```swift
/// extension User: UserRoleProvider {
///     var role: String {
///         // Logic to determine user role
///         // Could be stored in DB or computed from attributes
///         email.contains("admin") ? "admin" : "user"
///     }
/// }
/// ```
/// 
/// **Implement in your User model:**
/// ```swift
/// @Schema("users")
/// struct User {
///     @ID var id: UUID
///     @Column var email: String
///     @Column var role: String  // Store role in DB
///     // ...
/// }
/// 
/// extension User: UserRoleProvider {
///     var role: String { role }
/// }
/// ```
public protocol UserRoleProvider {
    var role: String { get }
}
```

---

### 5. Document Permission Provider Protocol

**Add to Section 2.4.3:**

```swift
/// Protocol for entities that can check permissions
/// 
/// **Usage:**
/// ```swift
/// extension User: PermissionProvider {
///     func hasPermission(_ permission: String) -> Bool {
///         // Logic to check permissions
///         // Could be stored in DB or computed from roles
///         switch permission {
///         case "posts.create": return true
///         case "posts.delete": return role == "admin"
///         default: return false
///         }
///     }
/// }
/// ```
/// 
/// **Implement in your User model:**
/// ```swift
/// @Schema("users")
/// struct User {
///     @ID var id: UUID
///     @Column var permissions: [String]  // JSON array of permissions
///     // ...
/// }
/// 
/// extension User: PermissionProvider {
///     func hasPermission(_ permission: String) -> Bool {
///         permissions.contains(permission)
///     }
/// }
/// ```
public protocol PermissionProvider {
    func hasPermission(_ permission: String) -> Bool
}
```

---

## 📋 Updated Acceptance Criteria

### Add New Criteria:

**Organization Handling:**
- [ ] UserScope.organization is optional (can be nil)
- [ ] Apps without organizations can use UserScope without org parameter
- [ ] assignOrgToScope() continues gracefully if org not found
- [ ] assignOrgToScope() doesn't fail if user has no org param

**Testing:**
- [ ] TestApp.withUserScope() creates test connection with user scope
- [ ] TestApp.withGuestScope() creates test connection without user
- [ ] Scope fixtures work for testing with/without organizations
- [ ] Can test multi-tenant scenarios with organization fixtures

**Protocol Implementation:**
- [ ] UserRoleProvider protocol defined for role-based auth
- [ ] PermissionProvider protocol defined for permission-based auth
- [ ] Example implementations provided in documentation

---

## 🎓 Implementation Notes

**Dependencies:**
- Spec 22A (Basic Auth) - must be implemented first
- Spectro ORM for database queries
- Organization model is optional (implement at application level if needed)

**Integration Points:**
- Builds on basic authentication from Spec 22A
- Integrates with fetchCurrentScope() plug
- Works with context layer (contexts accept scope parameter)

**When to Use Organizations:**
- **Multi-tenant SaaS apps** - Each customer has their own organization
- **Team-based apps** - Users belong to teams/organizations
- **Single-tenant apps** - Skip organization features, use simple UserScope

**Performance Considerations:**
- Scope loading is cheap (just reads from session or assigns)
- Organization loading requires 1 additional database query
- Authorization checks are in-memory (no queries after user loaded)

**Security Considerations:**
- Scope prevents data leakage between users/organizations
- requireOwnership() prevents unauthorized access even with valid auth
- Role checks are in-memory (fast)
- Permission checks can be expensive if not cached

---

**Status:** ✅ Ready for implementation (with refinements applied)
