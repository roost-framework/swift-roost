# Spec: Authentication System (Basic)

**Status:** Proposed
**Date:** 2026-04-07
**Depends on:** Roost core (spec 01), Sessions (spec 19), Spectro ORM

---

## 1. Goal

Roost lacks a foundational authentication system. Developers must manually implement password hashing, session management, and token-based authentication, which leads to security vulnerabilities and inconsistent patterns.

This spec implements **core authentication features** that all web applications need:

1. **Password hashing** - bcrypt-based secure password storage
2. **Session authentication** - Login/logout flows with token management
3. **API token authentication** - Bearer token support for API access
4. **Basic authorization** - `requireAuth` plug for protecting routes

This is **Part 1 of 2** for authentication. See Spec 22B for the advanced scope system.

---

## 2. Scope

### 2.1 Password Hashing

#### 2.1.1 Auth Enum

```swift
// In Sources/Roost/Auth/Auth.swift
public enum Auth {
    /// Hash a password using bcrypt (cost factor 12)
    /// - Parameter password: Plain text password (min 8 characters)
    /// - Returns: Bcrypt hash
    /// - Throws: AuthError.passwordTooShort if < 8 chars
    public static func hashPassword(_ password: String) throws -> String

    /// Verify a password against a stored hash
    /// - Parameters:
    ///   - password: Plain text password to verify
    ///   - hash: Stored bcrypt hash
    /// - Returns: true if password matches hash
    public static func verifyPassword(_ password: String, against hash: String) -> Bool

    /// Generate a cryptographically random token (URL-safe base64)
    /// - Parameter bytes: Number of random bytes (default: 32)
    /// - Returns: URL-safe base64-encoded token
    public static func generateToken(bytes: Int = 32) -> String
}
```

**Implementation:**
- Uses `swift-crypto`'s bcrypt with cost factor 12
- Tokens are 32 random bytes, base64url-encoded (no `+`, `/`, `=` chars)
- `verifyPassword` uses constant-time comparison via `CryptoKit`
- All functions are `sendable` and thread-safe

**Error Handling:**
```swift
public enum AuthError: Error {
    case passwordTooShort(minLength: Int)
    case hashingFailed(underlying: Error)
    case invalidHashFormat
}
```

---

### 2.2 Session-Based Authentication

#### 2.2.1 Connection Extensions

```swift
// In Sources/Roost/Auth/SessionAuth.swift
extension Connection {
    /// Load authenticated user from session token
    /// - Parameter userType: Model type conforming to Schema
    /// - Returns: Authenticated user or nil if not logged in
    /// - Throws: DatabaseError if query fails
    public func loadUser<T: Schema>(_ userType: T.Type) async throws -> T? {
        guard let sessionToken = sessionData["user_token"] as? String else {
            return nil
        }

        let repo = assigns[SpectroKey.self] as! SpectroClient

        // Query UserToken with context "session"
        guard let userToken = try await repo.query(UserToken.self)
            .where(\.token == sessionToken)
            .where(\.context == "session")
            .where(\.expiresAt == nil || \.expiresAt > Date())
            .first() else {
            return nil
        }

        // Load user with valid token
        guard let user = try await repo.query(userType)
            .where(\.id == userToken.userId)
            .first() else {
            return nil
        }

        // Cache in assigns
        assigns["currentUser"] = user
        assigns["currentUserId"] = user.id

        return user
    }

    /// Authenticate user and create session
    /// - Parameters:
    ///   - user: User to authenticate
    ///   - remember: If true, session expires in 30 days (default: 7 days)
    /// - Returns: Updated connection with session set
    /// - Throws: DatabaseError if session creation fails
    public func loginUser<T: Schema>(_ user: T, remember: Bool = false) async throws -> Connection {
        let repo = assigns[SpectroKey.self] as! SpectroClient

        // Generate session token
        let token = Auth.generateToken()
        let hashedToken = CryptoKit.SHA256.hash(data: Data(token.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        // Create session token record
        var userToken = UserToken()
        userToken.userId = user.value(forKey: "id") as! UUID
        userToken.token = hashedToken
        userToken.context = "session"
        let expiry = remember ? 30.days : 7.days
        userToken.expiresAt = Date().addingTimeInterval(expiry)

        try await repo.save(userToken)

        // Update session
        var updated = self
        updated.sessionData["user_token"] = token
        updated.sessionData["user_id"] = user.value(forKey: "id")

        return updated
    }

    /// Logout current user (clears session token)
    /// - Returns: Updated connection with session cleared
    /// - Throws: DatabaseError if token deletion fails
    public func logoutUser() async throws -> Connection {
        guard let sessionToken = sessionData["user_token"] else {
            return self  // Already logged out
        }

        let repo = assigns[SpectroKey.self] as! SpectroClient
        let hashedToken = CryptoKit.SHA256.hash(data: Data(sessionToken.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        // Delete session token
        try await repo.query(UserToken.self)
            .where(\.token == hashedToken)
            .delete()

        // Clear session
        var updated = self
        updated.sessionData["user_token"] = nil
        updated.sessionData["user_id"] = nil
        updated.assigns["currentUser"] = nil

        return updated
    }

    /// Get current user from assigns (must call loadUser first)
    /// - Parameter userType: Model type conforming to Schema
    /// - Returns: Authenticated user or nil if not loaded
    public func currentUser<T: Schema>(_ userType: T.Type) -> T? {
        assigns["currentUser"] as? T
    }
}
```

#### 2.2.2 requireAuth Plug

```swift
// In Sources/Roost/Auth/Plugs.swift

/// Require authentication - redirect to login if not authenticated
/// - Parameters:
///   - redirectTo: Path to redirect unauthenticated users to
///   - returnToKey: Session key to store original URL for post-login redirect
/// - Returns: Plug that enforces authentication
public func requireAuth(
    redirectTo: String = "/auth/login",
    returnToKey: String = "auth_return_to"
) -> Plug {
    return { conn in
        Task {
            // Check if user is already loaded
            if let user = conn.currentUser(User.self) {
                return conn
            }

            // Try to load user from session
            guard let _ = try? await conn.loadUser(User.self) else {
                // Not authenticated - redirect to login
                var updated = conn
                updated.putSession(returnToKey, conn.request.uri)
                return Response.redirect(to: redirectTo)
            }

            return conn
        }.value
    }
}

/// Optional authentication - load user if session exists, continue as guest if not
/// - Returns: Plug that optionally loads user
public func optionalAuth() -> Plug {
    return { conn in
        Task {
            // Try to load user, but don't fail if not present
            _ = try? await conn.loadUser(User.self)
            return conn
        }.value
    }
}
```

---

### 2.3 API Token Authentication

#### 2.3.1 AuthToken Model

```swift
// In Sources/Roost/Auth/AuthToken.swift
import SpectroKit

@Schema("user_tokens")
public struct AuthToken {
    @ID var id: UUID
    @ForeignKey var userId: UUID
    @Column var token: String            // SHA256 hash of actual token
    @Column var context: String          // "session", "api", "confirm", "reset"
    @Column var sentTo: String?          // Email/phone for confirmation tokens
    @Timestamp var createdAt: Date
    @Column var expiresAt: Date?

    // API token specific fields
    @Column var name: String?            // Token name (e.g., "iOS App")
    @Column var lastUsed: Date?

    /// Generate a new API token
    /// - Parameters:
    ///   - userId: User ID who owns the token
    ///   - name: Human-readable token name
    ///   - expiresIn: Optional expiry duration
    /// - Returns: Tuple of (plainTextToken, storedRecord)
    public static func generate(
        for userId: UUID,
        name: String,
        expiresIn: Duration?
    ) -> (token: String, record: AuthToken) {
        let token = Auth.generateToken()
        let hashedToken = CryptoKit.SHA256.hash(data: Data(token.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        var record = AuthToken()
        record.userId = userId
        record.token = hashedToken
        record.name = name
        record.context = "api"
        record.expiresAt = expiresIn.map { Date().addingTimeInterval($0) }

        return (token, record)
    }

    /// Verify if a plain-text token matches this stored hash
    /// - Parameter token: Plain text token to verify
    /// - Returns: true if token matches
    public func verify(token: String) -> Bool {
        let hashedToken = CryptoKit.SHA256.hash(data: Data(token.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        return hashedToken == self.token
    }

    /// Check if token is expired
    public var isExpired: Bool {
        guard let expiry = expiresAt else {
            return false  // No expiry set
        }
        return expiry < Date()
    }
}
```

#### 2.3.2 Bearer Token Authentication

```swift
extension Connection {
    /// Authenticate via Bearer token header
    /// - Parameter userType: Model type conforming to Schema
    /// - Returns: Authenticated user or nil if token invalid
    /// - Throws: DatabaseError if query fails
    public func authenticateBearerToken<T: Schema>(_ userType: T.Type) async throws -> T? {
        guard let authHeader = request.headers["Authorization"].first,
              authHeader.hasPrefix("Bearer ") else {
            return nil
        }

        let token = authHeader.dropFirst(7)  // Remove "Bearer "
        let hashedToken = CryptoKit.SHA256.hash(data: Data(token.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        let repo = assigns[SpectroKey.self] as! SpectroClient

        // Find valid API token
        guard let authToken = try await repo.query(AuthToken.self)
            .where(\.token == hashedToken)
            .where(\.context == "api")
            .where(\.expiresAt == nil || \.expiresAt > Date())
            .first() else {
            return nil
        }

        // Update last used timestamp
        var updated = authToken
        updated.lastUsed = Date()
        try await repo.save(updated)

        // Load user
        guard let user = try await repo.query(userType)
            .where(\.id == authToken.userId)
            .first() else {
            return nil
        }

        // Cache in assigns
        assigns["currentUser"] = user
        assigns["currentUserId"] = user.id

        return user
    }
}

/// Require API authentication - fail with 401 if invalid
/// - Parameters:
///   - realm: Authentication realm (default: "API")
///   - scopeKey: Assigns key for scope (default: "current_scope")
/// - Returns: Plug that enforces API authentication
public func requireApiAuth(
    realm: String = "API",
    scopeKey: String = "current_scope"
) -> Plug {
    return { conn in
        Task {
            // Check Authorization header
            guard let authHeader = conn.request.headers["Authorization"].first,
                  authHeader.hasPrefix("Bearer ") else {
                return Response(status: .unauthorized, headers: [
                    "WWW-Authenticate": "Bearer realm=\"\(realm)\""
                ])
            }

            // Authenticate
            guard let user = try? await conn.authenticateBearerToken(User.self) else {
                return Response(status: .unauthorized, headers: [
                    "WWW-Authenticate": "Bearer realm=\"\(realm)\", error=\"invalid_token\""
                ])
            }

            // Store user in assigns
            var updated = conn
            updated.assigns[scopeKey] = user
            updated.assigns["current_user"] = user

            return updated
        }.value
    }
}
```

---

### 2.4 UserToken Schema Migration

```sql
-- Migration: Create user tokens table
-- Created at: 2026-04-07

-- +Migrate UP
BEGIN;

CREATE TABLE "user_tokens" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "token" TEXT NOT NULL,
    "context" TEXT NOT NULL DEFAULT 'api',
    "sent_to" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "expires_at" TIMESTAMPTZ,
    "name" TEXT,
    "last_used" TIMESTAMPTZ
);

CREATE INDEX "user_tokens_user_id_index" ON "user_tokens" ("user_id");
CREATE INDEX "user_tokens_token_context_index" ON "user_tokens" ("token", "context");
CREATE INDEX "user_tokens_expires_at_index" ON "user_tokens" ("expires_at") WHERE "expires_at" IS NOT NULL;

COMMIT;

-- -Migrate DOWN
BEGIN;

DROP INDEX IF EXISTS "user_tokens_expires_at_index";
DROP INDEX IF EXISTS "user_tokens_token_context_index";
DROP INDEX IF EXISTS "user_tokens_user_id_index";
DROP TABLE IF EXISTS "user_tokens";

COMMIT;
```

---

## 3. Usage Examples

### 3.1 Authentication Routes

```swift
// In Sources/MyApp/Routes/AuthRoutes.swift
import Roost

extension RoostApp {
    var authRoutes: [Route] {
        [
            // GET /auth/login - Show login form
            GET("/auth/login") { conn in
                return Response.render("auth/login", [
                    "csrfToken": conn.csrfToken(),
                    "error": conn.sessionData["login_error"]
                ])
            },

            // POST /auth/login - Authenticate user
            POST("/auth/login") { conn in
                let repo = conn.assigns[SpectroKey.self] as! SpectroClient

                // Decode form data
                guard let email = conn.params["email"] as? String,
                      let password = conn.params["password"] as? String else {
                    return Response.redirect(to: "/auth/login")
                }

                // Find user
                guard let user = try? await repo.query(User.self)
                    .where(\.email == email)
                    .first() else {
                    var updated = conn
                    updated.putSession("login_error", "Invalid credentials")
                    return Response.redirect(to: "/auth/login")
                }

                // Verify password
                guard Auth.verifyPassword(password, against: user.hashedPassword) else {
                    var updated = conn
                    updated.putSession("login_error", "Invalid credentials")
                    return Response.redirect(to: "/auth/login")
                }

                // Log in user
                var loggedIn = try await conn.loginUser(user)

                // Redirect to return URL or home
                let returnTo = conn.sessionData["auth_return_to"] as? String ?? "/"

                return Response.redirect(to: returnTo)
            },

            // DELETE /auth/logout - Logout user
            DELETE("/auth/logout") { conn in
                let loggedOut = try await conn.logoutUser()
                return Response.redirect(to: "/")
            },

            // GET /auth/register - Show registration form
            GET("/auth/register") { conn in
                return Response.render("auth/register", [
                    "csrfToken": conn.csrfToken()
                ])
            },

            // POST /auth/register - Create new user
            POST("/auth/register") { conn in
                let repo = conn.assigns[SpectroKey.self] as! SpectroClient

                // Decode form data
                guard let email = conn.params["email"] as? String,
                      let password = conn.params["password"] as? String else {
                    return Response.redirect(to: "/auth/register")
                }

                // Check if user exists
                if try? await repo.query(User.self)
                    .where(\.email == email)
                    .first() != nil {
                    var updated = conn
                    updated.putSession("register_error", "Email already taken")
                    return Response.redirect(to: "/auth/register")
                }

                // Hash password
                let hashedPassword = try Auth.hashPassword(password)

                // Create user
                var user = User()
                user.email = email
                user.hashedPassword = hashedPassword
                let created = try await repo.save(user)

                // Log in user
                let loggedIn = try await conn.loginUser(created)

                return Response.redirect(to: "/")
            }
        ]
    }
}
```

### 3.2 Protected Routes

```swift
// In Sources/MyApp/App.swift
var plugs: [Plug] {
    [
        session(store: .postgres),
        router()
    ]
}

var routes: [Route] {
    [
        // Public routes
        GET("/") { conn in
            Response.render("home", [:])
        },

        // Protected routes (require auth)
        scope("/dashboard", through: [requireAuth()]) {
            GET("/dashboard") { conn in
                let user = conn.currentUser(User.self)!
                return Response.render("dashboard", ["user": user])
            }
        }
    ]
}
```

### 3.3 API Routes

```swift
// In Sources/MyApp/Routes/ApiRoutes.swift
extension RoostApp {
    var apiRoutes: [Route] {
        [
            // API authentication required
            scope("/api/v1", through: [requireApiAuth()]) {
                GET("/api/v1/user") { conn in
                    let user = conn.currentUser(User.self)!
                    return Response.json([
                        "id": user.id,
                        "email": user.email
                    ])
                },

                POST("/api/v1/tokens") { conn in
                    let user = conn.currentUser(User.self)!
                    let repo = conn.assigns[SpectroKey.self] as! SpectroClient

                    guard let name = conn.params["name"] as? String else {
                        return Response(status: .badRequest)
                    }

                    // Generate API token
                    let (token, record) = AuthToken.generate(
                        for: user.id,
                        name: name,
                        expiresIn: 30.days
                    )

                    try await repo.save(record)

                    return Response.json([
                        "token": token,  // Only show once!
                        "name": record.name
                    ], status: .created)
                }
            }
        ]
    }
}
```

---

## 4. Acceptance Criteria

### 4.1 Password Hashing
- [ ] `Auth.hashPassword()` uses bcrypt with cost factor 12
- [ ] `Auth.hashPassword()` throws on passwords < 8 characters
- [ ] `Auth.verifyPassword()` uses constant-time comparison
- [ ] `Auth.generateToken()` produces 32-byte, URL-safe tokens
- [ ] All auth functions are Sendable and thread-safe

### 4.2 Session Authentication
- [ ] `conn.loadUser()` retrieves user from session token
- [ ] `conn.loginUser()` creates UserToken record with context "session"
- [ ] `conn.loginUser()` supports remember-me with extended expiry
- [ ] `conn.logoutUser()` deletes session token from database
- [ ] `conn.currentUser()` returns user from assigns
- [ ] Session tokens are hashed with SHA256 before storage
- [ ] Session tokens have optional expiry with `expiresAt` field
- [ ] Expired sessions are filtered out during authentication

### 4.3 API Token Authentication
- [ ] `AuthToken.generate()` creates token and returns plain text once
- [ ] `AuthToken.verify()` validates token against stored hash
- [ ] `AuthToken.isExpired` checks if token is expired
- [ ] `conn.authenticateBearerToken()` validates Authorization header
- [ ] `conn.authenticateBearerToken()` updates lastUsed timestamp
- [ ] API tokens are hashed with SHA256 before storage
- [ ] API tokens support expiry with `expiresAt` field
- [ ] API tokens support custom names for identification

### 4.4 UserToken Schema
- [ ] UserToken table stores both session and API tokens
- [ ] `context` field distinguishes "session" vs "api" tokens
- [ ] Foreign key to users with CASCADE delete
- [ ] Indexes on userId, token+context, and expiresAt
- [ ] Migration creates and drops table cleanly

### 4.5 Auth Plugs
- [ ] `requireAuth()` plug redirects unauthenticated users to login
- [ ] `requireAuth()` stores return URL in session for post-login redirect
- [ ] `optionalAuth()` plug loads user if session exists, continues as guest if not
- [ ] `requireApiAuth()` plug validates Bearer tokens
- [ ] `requireApiAuth()` returns proper WWW-Authenticate header on 401
- [ ] Plugs work with existing session system (spec 19)

### 4.6 Error Handling
- [ ] Invalid credentials show generic error (don't reveal which field is wrong)
- [ ] Database errors are handled gracefully
- [ ] Missing session data doesn't crash authentication
- [ ] Token verification failures don't leak information

### 4.7 Security
- [ ] Passwords are never stored in plain text
- [ ] Tokens are hashed before storage (session: SHA256, API: SHA256)
- [ ] Expired tokens are filtered during authentication
- [ ] Session tokens have automatic expiry (7 days default, 30 days if remember)
- [ ] API tokens support custom expiry durations
- [ ] Bearer token authentication follows RFC 6750
- [ ] CSRF protection integrated with session auth

### 4.8 Integration
- [ ] Works with Spectro ORM for database operations
- [ ] Works with existing session system (spec 19)
- [ ] Works with existing plug system
- [ ] Works with CSRF protection (spec 08)
- [ ] TestApp provides authentication helpers

### 4.9 Testing
- [ ] TestApp provides authenticated test connections
- [ ] Can test login/logout flows
- [ ] Can test API token authentication
- [ ] Can test protected routes
- [ ] `swift test` passes with authentication tests

---

## 5. Non-goals

- No user management UI (implement at application level)
- No email confirmation or password reset flows (requires mailer integration)
- No multi-factor authentication (MFA/TOTP)
- No role-based access control (see Spec 22B for scope system)
- No permission system (implement at application level)
- No OAuth / social login (Google, GitHub, etc.)
- No account locking or brute-force protection (use rate limiting spec 16)
- No session fixation protection beyond `renewSession()` (covered by spec 19)
- No distributed cache for sessions (use Postgres store for now)

---

## 6. Dependencies

- **swift-crypto** - For bcrypt password hashing and SHA256 token hashing
- **Spectro ORM** - For database operations and schema definitions
- **Nexus** - For Connection model and plug system
- **Session system (spec 19)** - For session storage and management

---

## 7. Migration Notes

This spec introduces new authentication patterns. Migration guide for existing apps:

1. **New apps** - Start using these authentication helpers immediately
2. **Existing apps** - Gradually migrate from manual auth to these helpers
3. **User model** - Ensure you have a `User` model with `email` and `hashedPassword` fields
4. **Database** - Run the UserToken migration before using authentication features
5. **Routes** - Add `requireAuth()` to protected routes

**Before:**
```swift
// Manual authentication (insecure)
guard let userId = conn.sessionData["user_id"],
      let user = try await repo.query(User.self)
          .where(\.id == userId)
          .first() else {
    return Response.redirect(to: "/login")
}
```

**After:**
```swift
// Using requireAuth plug
scope("/admin", through: [requireAuth()]) {
    // conn.currentUser(User.self) is guaranteed to exist here
}
```

---

## 8. Performance Considerations

- **Token hashing** - SHA256 is fast, bcrypt is slow by design (cost factor 12)
- **Database queries** - Authentication requires 2-3 queries per request (cache in production)
- **Session size** - Store minimal data in sessions (user ID only)
- **Token expiry** - Run cleanup job to delete expired tokens periodically

---

## 9. Security Considerations

- **Password hashing** - Bcrypt cost factor 12 balances security and performance (≈250ms)
- **Token storage** - Never store plain text tokens, always hash before storage
- **Timing attacks** - Constant-time comparison for password and token verification
- **Session fixation** - Always regenerate session ID after login
- **HTTPS only** - Session cookies should have `secure` flag in production
- **Password requirements** - Minimum 8 characters (enforced by hashing, not by validation)

---

## 10. Future Enhancements

Possible follow-up features (see Spec 22B):

- **Scope system** - Multi-tenant data isolation with UserScope
- **Role-based auth** - `requireRole()` plug for authorization
- **Permission system** - Fine-grained permissions with `requirePermission()`
- **Generator integration** - Auto-generate authenticated CRUD resources
- **Advanced token management** - Token CRUD UI, revocation, rotation

---

## 11. Testing Examples

```swift
// Tests/AuthenticationTests.swift
import Testing
@testable import MyApp

struct AuthenticationTests {
    @Test("login with valid credentials")
    func validLogin() async throws {
        let app = TestApp(MyApp())
        let repo = app.database

        // Create test user
        var user = User()
        user.email = "test@example.com"
        user.hashedPassword = try Auth.hashPassword("password123")
        let saved = try await repo.save(user)

        // Simulate login request
        var conn = app.connection()
        let loggedIn = try await conn.loginUser(saved)

        // Verify user is loaded
        let currentUser = try #require(conn.currentUser(User.self))
        #expect(currentUser.id == saved.id)
    }

    @Test("login with invalid credentials fails")
    func invalidLogin() async throws {
        let app = TestApp(MyApp())

        // Simulate login with wrong password
        var conn = app.connection()
        let user = try await conn.loadUser(User.self)

        // Should return nil
        #expect(user == nil)
    }

    @Test("API token authentication")
    func apiTokenAuth() async throws {
        let app = TestApp(MyApp())
        let repo = app.database

        // Create user and API token
        var user = User()
        user.email = "test@example.com"
        user.hashedPassword = try Auth.hashPassword("password123")
        let saved = try await repo.save(user)

        let (token, record) = AuthToken.generate(
            for: saved.id,
            name: "Test Token",
            expiresIn: nil
        )

        try await repo.save(record)

        // Authenticate with token
        var conn = app.connection()
        conn.requestHeaders["Authorization"] = "Bearer \(token)"

        let authenticated = try await conn.authenticateBearerToken(User.self)

        // Should return user
        let authUser = try #require(authenticated)
        #expect(authUser.id == saved.id)
    }

    @Test("requireAuth redirects unauthenticated users")
    func requireAuthRedirect() async throws {
        let app = TestApp(MyApp())

        // Create request without auth
        var conn = app.connection()
        conn.request.uri = "/dashboard"

        let plug = requireAuth()
        let result = plug(conn)

        // Should redirect to login
        #expect(result.status == .seeOther)
        #expect(result.headers["Location"] == "/auth/login")
    }
}
```
