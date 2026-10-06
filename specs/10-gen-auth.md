# Spec: Authentication Generator

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01), CLI (specs 02, 04-05), sessions, CSRF (spec 08)

---

## 1. Goal

Authentication is the first thing every web app needs and the first thing
every developer gets wrong. Phoenix solved this with `mix phx.gen.auth` —
a single command that generates a complete, production-ready auth system
that you own and can customize.

Roost should do the same.

```bash
$ roost gen.auth
  create  Sources/MyApp/Models/User.swift
  create  Sources/MyApp/Routes/AuthRoutes.swift
  create  Sources/MyApp/Plugs/RequireAuth.swift
  create  Sources/MyApp/Views/auth/login.esw
  create  Sources/MyApp/Views/auth/register.esw
  create  Sources/Migrations/20260329_CreateUsers.sql
  create  Sources/Migrations/20260329_CreateUserTokens.sql
```

The generated code is not a library — it's scaffolding that lives in your
project. You own it, you can modify it, and it serves as documentation
for how Roost auth patterns work.

---

## 2. Scope

### 2.1 User Model

```swift
@Schema("users")
struct User {
    @ID var id: UUID
    @Column var email: String
    @Column var hashedPassword: String
    @Timestamp var createdAt: Date
}
```

### 2.2 User Token Model

For "remember me" and email confirmation tokens:

```swift
@Schema("user_tokens")
struct UserToken {
    @ID var id: UUID
    @ForeignKey var userId: UUID
    @Column var token: String
    @Column var context: String   // "session", "confirm", "reset"
    @Column var sentTo: String?
    @Timestamp var createdAt: Date
}
```

### 2.3 SQL Migrations

**Users table:**
```sql
CREATE TABLE "users" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "email" TEXT NOT NULL UNIQUE,
    "hashed_password" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX "users_email_index" ON "users" ("email");
```

**User tokens table:**
```sql
CREATE TABLE "user_tokens" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "token" TEXT NOT NULL,
    "context" TEXT NOT NULL,
    "sent_to" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX "user_tokens_user_id_index" ON "user_tokens" ("user_id");
CREATE UNIQUE INDEX "user_tokens_token_context_index" ON "user_tokens" ("token", "context");
```

### 2.4 Auth Routes

Generated routes handle:

| Route | Method | Action |
|-------|--------|--------|
| `/auth/register` | GET | Show registration form |
| `/auth/register` | POST | Create user account |
| `/auth/login` | GET | Show login form |
| `/auth/login` | POST | Authenticate and create session |
| `/auth/logout` | DELETE | Clear session and redirect |

### 2.5 Password Hashing

Use `swift-crypto` or `swift-bcrypt` for password hashing. The generated
code includes helper functions:

```swift
enum Auth {
    static func hashPassword(_ password: String) -> String
    static func verifyPassword(_ password: String, against hash: String) -> Bool
}
```

### 2.6 RequireAuth Plug

A middleware that checks for an authenticated user in the session and either
continues the pipeline or redirects to login:

```swift
public func requireAuth(redirectTo: String = "/auth/login") -> Plug

// Usage in App.swift:
scope("/admin", through: [requireAuth()]) {
    adminRoutes()
}
```

The plug loads the current user from the session token and injects it into
`conn.assigns["currentUser"]`.

### 2.7 Session Token Flow

1. On login: generate a random session token, store in `user_tokens` table
   with context "session", set token in session cookie.
2. On each request: `requireAuth` reads the token from the session, looks
   up the user via `user_tokens`, injects the user into assigns.
3. On logout: delete the token from `user_tokens`, clear the session.

### 2.8 Generated Templates

**login.esw:**
```html
<%!
var conn: Connection
var csrfToken: String
var error: String?
%>
<h1>Log in</h1>
<% if let error { %>
  <div class="alert error"><%= error %></div>
<% } %>
<form method="post" action="/auth/login">
  <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">
  <label>Email <input type="email" name="email" required></label>
  <label>Password <input type="password" name="password" required></label>
  <button type="submit">Log in</button>
</form>
<p>Don't have an account? <a href="/auth/register">Register</a></p>
```

**register.esw:**
```html
<%!
var conn: Connection
var csrfToken: String
var errors: [String]
%>
<h1>Register</h1>
<% for error in errors { %>
  <div class="alert error"><%= error %></div>
<% } %>
<form method="post" action="/auth/register">
  <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">
  <label>Email <input type="email" name="email" required></label>
  <label>Password <input type="password" name="password" required minlength="8"></label>
  <button type="submit">Create account</button>
</form>
<p>Already have an account? <a href="/auth/login">Log in</a></p>
```

### 2.9 Validation Rules

Generated registration validates:
- Email is present and contains `@`
- Email is unique (check database)
- Password is at least 8 characters

Login validates:
- Email exists in database
- Password matches hash

---

## 3. Acceptance Criteria

- [ ] `roost gen.auth` generates all files listed in scope
- [ ] Generated code compiles without modifications
- [ ] User model uses `@Schema` macro with proper column types
- [ ] Passwords are hashed with bcrypt (never stored in plain text)
- [ ] Registration creates a user and logs them in
- [ ] Registration rejects duplicate emails with a clear error
- [ ] Registration rejects passwords shorter than 8 characters
- [ ] Login with correct credentials creates a session
- [ ] Login with wrong credentials shows an error (without revealing which field is wrong)
- [ ] Logout clears the session token from both cookie and database
- [ ] `requireAuth()` plug redirects unauthenticated requests to login
- [ ] `requireAuth()` plug injects `currentUser` into assigns for authenticated requests
- [ ] Session tokens are cryptographically random (32+ bytes)
- [ ] Session tokens are stored hashed in the database (not plain text)
- [ ] Old session tokens are cleaned up on logout
- [ ] Generated migrations create proper indexes
- [ ] Generated templates include CSRF tokens
- [ ] Generated code follows Roost conventions (`conn.repo()`, `@RouteBuilder`, etc.)
- [ ] All generated types are Sendable
- [ ] `swift build` succeeds after generation
- [ ] Command is idempotent — warns if files already exist rather than overwriting

---

## 4. Non-goals

- No OAuth / social login (Google, GitHub, etc.) — add later as separate generator.
- No email confirmation flow — generated code includes the token model but not the mailer.
- No password reset flow — requires a mailer, which is a separate spec.
- No roles or permissions system — that's application-level.
- No API token authentication (bearer tokens) — separate concern from session auth.
- No rate limiting on login attempts — separate spec.
- No multi-factor authentication.
