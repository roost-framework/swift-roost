# Spec 22A Refinements - Basic Authentication

**Date:** 2026-04-07  
**Status:** Ready for Implementation

---

## 🎯 Overview

Spec 22A (Basic Authentication) was extracted from the original monolithic Spec 22. This document provides refinements and clarifications.

---

## ✅ What Changed from Original Spec 22

### Removed from Spec 22A (Moved to Spec 22B)
- ❌ AuthScope protocol (now in Spec 22B)
- ❌ UserScope and SessionScope implementations (now in Spec 22B)
- ❌ ScopeConfig and ScopeMetadata (now in Spec 22B)
- ❌ fetchCurrentScope plug (now in Spec 22B)
- ❌ assignOrgToScope plug (now in Spec 22B)
- ❌ Scope helpers and fixtures (now in Spec 22B)
- ❌ requireRole, requireOwnership, requirePermission plugs (now in Spec 22B)
- ❌ Generator hooks (now in Spec 22B)

### Kept in Spec 22A
- ✅ Password hashing (bcrypt)
- ✅ Session authentication helpers
- ✅ API token authentication
- ✅ requireAuth and requireApiAuth plugs
- ✅ UserToken schema
- ✅ Basic authorization

---

## 🔧 Specific Refinements

### 1. Document Silent Failure in loadUser()

**Current Issue:** Line ~107 in Spec 22A uses `try? await conn.loadUser(User.self)` which silently fails.

**Refinement:** Add documentation explaining this is intentional (guest access pattern)

**Add to Section 2.2.1:**

```swift
/// Load authenticated user from session token
/// - Parameter userType: Model type conforming to Schema
/// - Returns: Authenticated user or nil if not logged in
/// - Note: Silent failure with try? is intentional - supports guest access patterns
///       Use requireAuth() plug to enforce authentication
/// - Throws: DatabaseError only if query fails (not if user not found)
public func loadUser<T: Schema>(_ userType: T.Type) async throws -> T? {
    guard let sessionToken = sessionData["user_token"] as? String else {
        return nil  // No session token, not logged in
    }

    // ... rest of implementation
}
```

**Rationale:** Silent failure allows optional authentication - use `requireAuth()` plug to enforce authentication.

---

### 2. Add Token Expiry Checking

**Current Issue:** AuthToken has `expiresAt` but no logic to check expiry during authentication.

**Add to AuthToken implementation:**

```swift
extension AuthToken {
    /// Check if token is expired
    public var isExpired: Bool {
        guard let expiry = expiresAt else {
            return false  // No expiry set
        }
        return expiry < Date()
    }

    /// Check if token is valid (not expired and matches hash)
    /// - Parameter token: Plain text token to verify
    /// - Returns: true if token is valid
    public func isValid(token: String) -> Bool {
        return !isExpired && verify(token: token)
    }
}
```

**Add to authenticateBearerToken implementation:**

```swift
extension Connection {
    public func authenticateBearerToken<T: Schema>(_ userType: T.Type) async throws -> T? {
        // ... existing header checking code ...

        // Find valid API token
        guard let authToken = try? await repo.query(AuthToken.self)
            .where(\.token == hashedToken)
            .where(\.context == "api")
            .where(\.expiresAt == nil || \.expiresAt > Date())  // Check expiry here
            .first() else {
            return nil
        }

        // ... rest of implementation
    }
}
```

**Acceptance Criteria Additions:**
- [ ] `AuthToken.isExpired` checks if token is expired
- [ ] `AuthToken.isValid()` checks both expiry and hash
- [ ] `authenticateBearerToken()` filters out expired tokens

---

### 3. Clarify UserToken.sessionData vs session() Confusion

**Current Issue:** Spec uses both `sessionData` and `session()` methods inconsistently.

**Refinement:** Add documentation to clarify:

```swift
extension Connection {
    /// Session data is accessed via dictionary-like access:
    /// - `conn.sessionData["key"]` - Read from session storage
    /// - `conn.putSession("key", value)` - Write to session storage
    ///
    /// The session() method is NOT used in Roost - we use sessionData instead
    /// to avoid confusion with HTTP sessions.
}
```

---

### 4. Add Example Error Handling

**Add new Section 3.5: Error Handling**

```swift
#### Error Handling

**Common Errors and Recovery:**

**1. AuthError.passwordTooShort**
```swift
do {
    let hash = try Auth.hashPassword("short")
} catch AuthError.passwordTooShort(let minLength) {
    // Show error to user
    return Response.render("register", [
        "error": "Password must be at least \(minLength) characters"
    ])
}
```

**2. Invalid Credentials**
```swift
let user = try? await repo.query(User.self)
    .where(\.email == email)
    .first()

guard let user = user, Auth.verifyPassword(password, against: user.hashedPassword) else {
    // Don't reveal which field is wrong (security best practice)
    var updated = conn
    updated.putSession("login_error", "Invalid email or password")
    return Response.redirect(to: "/auth/login")
}
```

**3. API Token Authentication Failed**
```swift
guard let user = try? await conn.authenticateBearerToken(User.self) else {
    return Response(status: .unauthorized, headers: [
        "WWW-Authenticate": "Bearer realm=\"API\", error=\"invalid_token\""
    ])
}
```

**4. Database Connection Errors**
```swift
do {
    try await conn.loginUser(user)
} catch {
    // Log error for debugging
    Log.error("Failed to login user: \(error)")
    
    // Show user-friendly error
    return Response.render("error", [
        "message": "Unable to log in. Please try again."
    ], status: .internalServerError)
}
```

**Error Recovery Strategies:**

- **Password too short** - Show error with minimum length requirement
- **Invalid credentials** - Generic error message, don't reveal which field is wrong
- **Token expired** - Return 401 with WWW-Authenticate header
- **Database errors** - Log for debugging, show generic error to user
- **Missing session data** - Continue as guest (use requireAuth to enforce)
```

---

## 📋 Updated Acceptance Criteria

### Add New Criteria:

**Token Expiry:**
- [ ] `AuthToken.isExpired` property checks if token is expired
- [ ] `AuthToken.isValid()` checks both expiry and hash
- [ ] `authenticateBearerToken()` filters expired tokens
- [ ] Expired tokens are filtered during all authentication checks

**Error Handling:**
- [ ] Invalid credentials show generic error (don't reveal which field)
- [ ] Database errors are logged and show user-friendly message
- [ ] Token authentication returns proper HTTP status codes
- [ ] Session errors don't crash authentication flow

---

## 🎓 Implementation Notes

**Dependencies:**
- Spectro ORM for UserToken queries
- swift-crypto for bcrypt and SHA256
- Nexus Connection and session system (spec 19)

**Integration Points:**
- Requires User model to exist (implement at application level)
- Requires UserToken table to be created (migration provided)
- Works with CSRF protection (spec 08) for form-based auth

**Performance Considerations:**
- Bcrypt cost factor 12 ≈ 250ms per hash (by design for security)
- Session lookup requires 1 database query (cache in production)
- Token authentication requires 1 database query (cache in production)

**Security Considerations:**
- Passwords are never stored in plain text
- Tokens are hashed with SHA256 before storage
- Constant-time comparison prevents timing attacks
- Generic error messages prevent user enumeration

---

**Status:** ✅ Ready for implementation (with refinements applied)
