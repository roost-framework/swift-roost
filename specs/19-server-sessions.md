# Spec: Server-Side Sessions

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01), Hummingbird PersistDriver

---

## 1. Goal

Cookie-based sessions work but have limits: 4 KB max size, data visible
to the client (even if signed), and every request carries the full
session payload.

Server-side sessions store data on the server and only send a session ID
cookie to the client. This enables:

- Large session data (shopping carts, wizard state).
- Sensitive data that shouldn't leave the server.
- Server-side session invalidation (logout everywhere).

Hummingbird provides the `PersistDriver` protocol with an in-memory
implementation. Roost adds a Postgres-backed driver (via Spectro)
and a session plug that works like Phoenix's session store.

```swift
var plugs: [Plug] {
    [session(store: .postgres), router()]
}
```

---

## 2. Scope

### 2.1 Session Store Protocol

```swift
public protocol SessionStore: Sendable {
    /// Retrieve session data by ID.
    func get(_ id: String) async throws -> [String: String]?

    /// Save session data, returning the session ID.
    func set(_ id: String, data: [String: String], expiry: Duration?) async throws

    /// Delete a session.
    func delete(_ id: String) async throws

    /// Remove all expired sessions.
    func cleanup() async throws
}
```

### 2.2 Built-in Stores

**Memory store** (default for dev/test):

```swift
public final class MemorySessionStore: SessionStore, @unchecked Sendable {
    // Actor-protected dictionary with TTL
    // Automatic cleanup every 60 seconds
}
```

**Postgres store** (for production):

```swift
public final class PostgresSessionStore: SessionStore {
    // Uses Spectro to read/write a `roost_sessions` table
    // Schema: id TEXT PRIMARY KEY, data JSONB, expires_at TIMESTAMPTZ
}
```

The table is auto-created on first use if it doesn't exist.

**Factory:**

```swift
public enum SessionStoreFactory {
    case memory
    case postgres
    case custom(SessionStore)
}
```

### 2.3 Session Plug

```swift
public func session(
    store: SessionStoreFactory = .memory,
    cookieName: String = "_roost_session",
    maxAge: Int = 86400 * 7,  // 1 week
    secure: Bool? = nil,       // auto: true in prod, false in dev
    httpOnly: Bool = true,
    sameSite: SameSite = .lax
) -> Plug
```

Behavior:
1. Read the session ID from the cookie.
2. If present, load session data from the store into `conn.assigns`.
3. After the response, if session data was modified, save it back.
4. If no session exists and data was written, create a new session with
   a random 32-byte base64url ID and set the cookie.

### 2.4 Session API on Connection

```swift
extension Connection {
    /// Read a session value.
    public func getSession(_ key: String) -> String?

    /// Write a session value.
    public func putSession(_ key: String, _ value: String) -> Connection

    /// Delete a session value.
    public func deleteSession(_ key: String) -> Connection

    /// Destroy the entire session (logout).
    public func clearSession() -> Connection

    /// Renew the session ID (prevent fixation attacks).
    public func renewSession() -> Connection
}
```

### 2.5 Session Fixation Protection

`renewSession()` generates a new session ID while preserving the data.
This should be called after login to prevent session fixation attacks.
The `gen.auth` login handler should call this automatically.

### 2.6 Session Cleanup

For the Postgres store, expired sessions are cleaned up:
- Automatically on each request (probabilistic: 1% chance per request).
- Via a `roost session:cleanup` CLI command for cron jobs.

For the memory store, a background Task runs cleanup every 60 seconds.

### 2.7 Migration

The Postgres store needs a `roost_sessions` table:

```sql
CREATE TABLE IF NOT EXISTS roost_sessions (
    id TEXT PRIMARY KEY,
    data JSONB NOT NULL DEFAULT '{}',
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_sessions_expires ON roost_sessions (expires_at);
```

Auto-created on first use. No manual migration required.

---

## 3. Acceptance Criteria

- [ ] `SessionStore` protocol with `get`, `set`, `delete`, `cleanup`
- [ ] `MemorySessionStore` with TTL and auto-cleanup
- [ ] `PostgresSessionStore` backed by Spectro
- [ ] `session()` plug reads/writes session cookie
- [ ] Session ID is a cryptographically random 32-byte string
- [ ] `conn.getSession`, `putSession`, `deleteSession`, `clearSession`
- [ ] `conn.renewSession` generates new ID, preserves data
- [ ] Cookie attributes: httpOnly, secure (auto), sameSite
- [ ] Postgres sessions table auto-created on first use
- [ ] Expired sessions cleaned up (probabilistic + CLI command)
- [ ] Session works across requests (write in POST, read in GET)
- [ ] `gen.auth` calls `renewSession` after login
- [ ] `.memory` is default for dev/test, `.postgres` for production use
- [ ] `swift test` passes

---

## 4. Non-goals

- No Redis session store (add later as a separate package).
- No session encryption (data is server-side, not exposed to client).
- No session sharing across server instances (use Postgres for that).
- No typed session values (strings only — serialize/deserialize yourself).
- No session size limits (server-side storage is bounded by the store).
