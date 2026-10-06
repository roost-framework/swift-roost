# Spec: Rate Limiting

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01)

---

## 1. Goal

Protect APIs and login endpoints from abuse. A plug that limits requests
per client using a token bucket algorithm. No external dependencies
(Redis, etc.) — in-memory for single-node deployments.

```swift
var plugs: [Plug] {
    [rateLimit(max: 100, windowSeconds: 60), router()]
}
```

Or scoped to specific routes:

```swift
POST("/login") { conn in
    conn |> rateLimit(max: 5, windowSeconds: 300) |> handleLogin
}
```

---

## 2. Scope

### 2.1 Plug API

```swift
public func rateLimit(
    max: Int,
    windowSeconds: Int,
    by: RateLimitKey = .ip,
    message: String = "Too Many Requests"
) -> Plug
```

### 2.2 Rate Limit Key

How to identify clients:

```swift
public enum RateLimitKey: Sendable {
    /// Client IP address (from `X-Forwarded-For` or socket address).
    case ip

    /// A specific header value (e.g. API key).
    case header(HTTPField.Name)

    /// A value from connection assigns (e.g. user ID after auth).
    case assign(String)

    /// Custom extraction function.
    case custom(@Sendable (Connection) -> String?)
}
```

### 2.3 Algorithm: Sliding Window Counter

Use a sliding window counter (simpler than token bucket, good enough for
most use cases):

- Track request counts per key per window.
- When a request arrives, count requests in the current window.
- If count >= max, return 429 Too Many Requests.
- Include standard rate limit headers in all responses.

### 2.4 Response Headers

Always set on responses (even when not rate-limited):

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 73
X-RateLimit-Reset: 1711756860
Retry-After: 42  (only on 429 responses)
```

### 2.5 Rate Limit Response

When the limit is exceeded:

- Status: 429 Too Many Requests
- Body: JSON `{"error": "Too Many Requests"}` for JSON requests,
  plain text for others (follows content negotiation from spec 05).
- Connection is halted.
- `Retry-After` header with seconds until the window resets.

### 2.6 Storage

An actor-based in-memory store with automatic cleanup:

```swift
actor RateLimitStore {
    private var entries: [String: WindowEntry] = [:]

    struct WindowEntry {
        var count: Int
        var windowStart: Date
    }

    func check(key: String, max: Int, window: Int) -> RateLimitResult
    func cleanup() // Remove expired entries, called periodically
}
```

Cleanup runs every 60 seconds via a background `Task` to prevent
unbounded memory growth.

### 2.7 IP Extraction

For `.ip` rate limiting, extract the client IP:

1. Check `X-Forwarded-For` header (first IP in the list).
2. Check `X-Real-IP` header.
3. Fall back to the socket's remote address.

This handles apps behind reverse proxies (nginx, Cloudflare, etc.).

---

## 3. Acceptance Criteria

- [ ] `rateLimit()` plug with configurable max, window, key, message
- [ ] Returns 429 when limit exceeded
- [ ] `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers on all responses
- [ ] `Retry-After` header on 429 responses
- [ ] `.ip` key extracts from `X-Forwarded-For` / `X-Real-IP` / socket
- [ ] `.header` key uses a specific request header
- [ ] `.assign` key uses a connection assign value
- [ ] `.custom` key allows arbitrary extraction
- [ ] Unknown keys (nil from custom) pass through without rate limiting
- [ ] In-memory store with automatic cleanup of expired entries
- [ ] Content negotiation on 429 response (JSON vs plain text)
- [ ] Multiple rate limit plugs can coexist (e.g., global + per-route)
- [ ] `swift test` passes

---

## 4. Non-goals

- No distributed rate limiting (Redis-backed). Single-node only.
- No rate limit by response status (e.g., only count 200s).
- No dynamic rate limit adjustment (fixed per plug instance).
- No rate limit dashboard or analytics.
