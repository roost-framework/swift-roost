# Spec: Deployment Tooling & Token Signing

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01), CLI (specs 02, 04-05)

---

## 1. Goal

Two related production-readiness features:

**Deployment:** `roost gen.dockerfile` generates a multi-stage Dockerfile
optimized for Swift server apps. Get from "it works on my machine" to
"it works in a container" with one command.

**Token signing:** A `Roost.Token` utility for generating signed,
time-limited tokens — the building block for email confirmation links,
password reset URLs, and API authentication. Phoenix has `Phoenix.Token`;
Roost needs the same.

---

## 2. Scope

### Part A: Dockerfile Generation

#### 2.1 Command

```bash
$ roost gen.dockerfile
  create  Dockerfile
  create  .dockerignore
```

#### 2.2 Generated Dockerfile

Multi-stage build optimized for Swift on Linux:

```dockerfile
# Build stage
FROM swift:6.0-noble AS build
WORKDIR /app
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY . .
RUN swift build -c release

# Runtime stage
FROM ubuntu:noble
RUN apt-get update && apt-get install -y libcurl4 && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/.build/release/<AppName> /usr/local/bin/app
COPY --from=build /app/Public /app/Public
EXPOSE 8080
ENV ROOST_HOST=0.0.0.0
ENV ROOST_PORT=8080
ENV ROOST_ENV=prod
ENTRYPOINT ["app"]
```

Key decisions:
- Uses `swift:6.0-noble` as build image (Ubuntu 24.04).
- Copies `Package.swift` and resolves first for layer caching.
- Runtime image is bare Ubuntu (no Swift runtime — statically linked).
- Copies `Public/` for static file serving.
- Sets environment variables for production defaults.
- `ROOST_HOST=0.0.0.0` so the container accepts external connections.

#### 2.3 Generated .dockerignore

```
.build/
.swiftpm/
.git/
*.xcodeproj
DerivedData/
```

#### 2.4 CLI Behavior

- Discovers app name from Package.swift (reuses `ProjectDiscovery`).
- Warns if files already exist, asks before overwriting.
- Prints next steps: `docker build -t myapp . && docker run -p 8080:8080 myapp`

---

### Part B: Token Signing

#### 2.5 Token API

```swift
public enum RoostToken {
    /// Signs data into a URL-safe token with an optional max age.
    ///
    /// - Parameters:
    ///   - data: The payload to sign (e.g. a user ID string).
    ///   - secret: The signing secret (typically from an env var).
    ///   - maxAge: Optional validity duration in seconds.
    /// - Returns: A URL-safe signed token string.
    public static func sign(
        _ data: String,
        secret: String,
        maxAge: Int? = nil
    ) -> String

    /// Verifies and extracts data from a signed token.
    ///
    /// - Parameters:
    ///   - token: The token string to verify.
    ///   - secret: The signing secret (must match the one used to sign).
    ///   - maxAge: Maximum age in seconds. Returns nil if the token is
    ///     older than this, even if the signature is valid.
    /// - Returns: The original data string, or nil if invalid/expired.
    public static func verify(
        _ token: String,
        secret: String,
        maxAge: Int? = nil
    ) -> String?
}
```

#### 2.6 Token Format

Tokens are structured as: `base64url(payload).base64url(signature)`

Payload is JSON: `{"data": "user_123", "iat": 1711756800}`

Signature is HMAC-SHA256 of the payload using the provided secret.

#### 2.7 Usage Examples

**Email confirmation:**
```swift
// Generate token
let token = RoostToken.sign(user.id.uuidString, secret: secretKey)
let confirmURL = "https://myapp.com/confirm?token=\(token)"
// Send email with confirmURL...

// Verify token (valid for 24 hours)
guard let userId = RoostToken.verify(token, secret: secretKey, maxAge: 86400) else {
    throw NexusHTTPError(.forbidden, message: "Invalid or expired link")
}
```

**Password reset:**
```swift
let token = RoostToken.sign(user.email, secret: secretKey, maxAge: 3600)
// Valid for 1 hour
```

#### 2.8 Secret Key Convention

The signing secret is read from the `ROOST_SECRET` environment variable.
`roost new` generates a random secret and writes it to a `.env.example`
file (not `.env` itself — that's the developer's responsibility).

---

## 3. Acceptance Criteria

### Dockerfile Generation

- [ ] `roost gen.dockerfile` creates `Dockerfile` and `.dockerignore`
- [ ] Generated Dockerfile uses multi-stage build
- [ ] Build stage resolves dependencies before copying source (layer cache)
- [ ] Runtime stage is minimal (no Swift toolchain)
- [ ] `Public/` directory is copied to runtime image
- [ ] Environment variables set sensible production defaults
- [ ] App name is discovered from Package.swift
- [ ] Generated image builds successfully with `docker build`
- [ ] Generated container runs and accepts HTTP requests
- [ ] Command warns if files already exist
- [ ] Command prints next steps after generation
- [ ] Generated `.dockerignore` excludes `.build/`, `.git/`, etc.

### Token Signing

- [ ] `RoostToken.sign` produces a URL-safe string
- [ ] `RoostToken.verify` returns the original data for valid tokens
- [ ] `RoostToken.verify` returns nil for tampered tokens
- [ ] `RoostToken.verify` returns nil for tokens signed with a different secret
- [ ] `maxAge` on verify rejects expired tokens
- [ ] `maxAge` on verify accepts tokens within the time window
- [ ] Tokens without maxAge never expire (signature-only validation)
- [ ] Token format is compact and URL-safe (no `+`, `/`, or `=`)
- [ ] HMAC-SHA256 is used for signing (via swift-crypto)
- [ ] `RoostToken` is an enum (no instances)
- [ ] All types are Sendable
- [ ] `swift test` passes

---

## 4. Non-goals

- No encrypted tokens (signed only — data is readable but tamper-proof).
- No JWT compatibility (JWTs are overengineered for this use case).
- No key rotation mechanism (use a new secret and accept both during transition).
- No Docker Compose generation (that's deployment-specific).
- No cloud-specific deployment (Fly.io, Railway, etc.) — just the Dockerfile.
- No `.env` file generation (only `.env.example`).
