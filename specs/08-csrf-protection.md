# Spec: CSRF Protection

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Nexus sessionPlug (complete), Roost core (spec 01)

---

## 1. Goal

Any Roost app that serves HTML forms is vulnerable to Cross-Site Request
Forgery unless it validates that form submissions originate from the app itself.
Phoenix includes CSRF protection by default. Rails includes it by default.
Roost should too.

The developer should never think about CSRF. It should be on by default,
invisible when everything is correct, and return a clear 403 when it isn't.

```swift
// In a template — the token is injected automatically:
<form method="post" action="/donuts">
  <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">
  ...
</form>

// In a route — no code needed. The plug validates automatically.
POST("/donuts") { conn in ... }
```

---

## 2. Scope

### 2.1 CSRF Plug

A plug that:

1. **Generates** a CSRF token per session (or per request, configurable) and
   stores it in the session under `_csrf_token`.
2. **Injects** the token into `conn.assigns["csrfToken"]` so templates can
   access it.
3. **Validates** the token on state-changing methods (`POST`, `PUT`, `PATCH`,
   `DELETE`) by comparing the submitted `_csrf_token` form parameter (or
   `x-csrf-token` header) against the session token.
4. **Skips** validation for JSON API requests (`Content-Type: application/json`)
   since APIs use bearer tokens, not cookies.
5. **Returns 403 Forbidden** with a clear error message when validation fails.

```swift
public func csrfProtection(
    except: [String] = []   // paths to skip (e.g. webhooks)
) -> Plug
```

### 2.2 Token Generation

Tokens are cryptographically random, URL-safe strings (32 bytes, base64url
encoded). Generated once per session and rotated on session clear.

```swift
// Internal
static func generateToken() -> String
```

### 2.3 Template Helper

The token is available as `csrfToken` in assigns. A convenience function
generates the hidden input:

```swift
// In templates:
<%= csrfTag %>
// Renders: <input type="hidden" name="_csrf_token" value="abc123...">
```

### 2.4 Integration with RoostApp

When the default `plugs` are used and a session plug is configured, CSRF
protection is included automatically. Apps that override `plugs` can add
`csrfProtection()` manually.

---

## 3. Acceptance Criteria

- [ ] CSRF token is generated and stored in the session on first request
- [ ] Token is available in `conn.assigns["csrfToken"]` for templates
- [ ] POST/PUT/PATCH/DELETE requests without a valid token return 403
- [ ] Token can be submitted via `_csrf_token` form field
- [ ] Token can be submitted via `x-csrf-token` HTTP header
- [ ] JSON requests (`Content-Type: application/json`) skip CSRF validation
- [ ] GET/HEAD/OPTIONS requests skip CSRF validation
- [ ] Paths in the `except` list skip validation
- [ ] Token persists across requests within the same session
- [ ] Token is rotated when the session is cleared
- [ ] `csrfTag` assign produces the correct hidden input HTML
- [ ] 403 response includes a clear "Invalid CSRF token" message
- [ ] Plug is a no-op when no session is configured (no crash)
- [ ] Works with cookie-based sessions
- [ ] All types are Sendable
- [ ] `swift test` passes

---

## 4. Non-goals

- No double-submit cookie pattern (session-based only).
- No per-request token rotation by default (per-session is sufficient).
- No JavaScript helper for AJAX (apps can read the token from a meta tag).
- No SameSite cookie configuration (that's the session plug's concern).
