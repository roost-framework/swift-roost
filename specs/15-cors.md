# Spec: CORS Support

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01)

---

## 1. Goal

APIs need to be callable from browser JavaScript on different origins.
Hummingbird already ships `CORSMiddleware` — Roost wraps it as a
plug with sensible defaults and framework-idiomatic configuration.

```swift
var plugs: [Plug] {
    [cors(allowOrigin: "https://myapp.com"), router()]
}
```

One line. No manual header management.

---

## 2. Scope

### 2.1 Plug API

```swift
public func cors(
    allowOrigin: CORSOrigin = .originBased,
    allowMethods: [HTTPRequest.Method] = [.get, .post, .put, .patch, .delete],
    allowHeaders: [HTTPField.Name] = [.contentType, .authorization, .accept],
    exposeHeaders: [HTTPField.Name] = [],
    maxAge: Int = 86400,
    allowCredentials: Bool = false
) -> Plug
```

### 2.2 Origin Modes

```swift
public enum CORSOrigin: Sendable {
    /// Reflect the request's Origin header back (any origin allowed).
    case originBased

    /// Allow only a specific origin.
    case exact(String)

    /// Allow multiple specific origins.
    case allowList(Set<String>)

    /// Custom validation function.
    case custom(@Sendable (String) -> Bool)

    /// Wildcard `*` — incompatible with credentials.
    case any
}
```

### 2.3 Preflight Handling

For `OPTIONS` requests with an `Origin` header:

1. Validate the origin against the configured policy.
2. Set `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`,
   `Access-Control-Allow-Headers`, `Access-Control-Max-Age`.
3. If `allowCredentials`, set `Access-Control-Allow-Credentials: true`.
4. Return 204 No Content. Halt the connection (don't run the router).

### 2.4 Simple/Actual Request Handling

For non-preflight requests with an `Origin` header:

1. Validate the origin.
2. Set `Access-Control-Allow-Origin` on the response.
3. If `exposeHeaders` is non-empty, set `Access-Control-Expose-Headers`.
4. If `allowCredentials`, set `Access-Control-Allow-Credentials: true`.
5. Continue to the next plug (don't halt).

### 2.5 Hummingbird Integration

Under the hood, delegate to Hummingbird's `CORSMiddleware` through the
NexusHummingbird adapter, or reimplement as a Nexus plug (simpler, no
adapter changes needed). Given the plug is ~60 lines, a native Nexus
implementation is preferred for consistency.

### 2.6 Environment Awareness

In dev mode, default to `.originBased` (accept any origin) so local
frontend development works without configuration. In prod, require
explicit origin configuration — log a warning if `.originBased` or
`.any` is used in production.

---

## 3. Acceptance Criteria

- [ ] `cors()` plug with configurable origin, methods, headers, max-age
- [ ] Preflight `OPTIONS` requests return 204 with correct CORS headers
- [ ] Actual requests get `Access-Control-Allow-Origin` header
- [ ] `.originBased` reflects the request origin
- [ ] `.exact` only allows the specified origin
- [ ] `.allowList` accepts multiple origins
- [ ] `.any` sets `*` (incompatible with credentials)
- [ ] `allowCredentials: true` sets `Access-Control-Allow-Credentials`
- [ ] `exposeHeaders` sets `Access-Control-Expose-Headers`
- [ ] Requests without `Origin` header pass through unmodified
- [ ] Dev mode defaults to `.originBased`
- [ ] Prod mode warns if `.originBased` or `.any` is used
- [ ] `swift test` passes

---

## 4. Non-goals

- No per-route CORS configuration (apply at the plug pipeline level).
- No CORS for WebSocket upgrades (handled separately by the browser).
- No automatic CSRF integration (CORS and CSRF are complementary).
