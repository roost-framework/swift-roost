# Spec: HTTP/2, TLS, and Response Compression

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01), Hummingbird HTTP/2 and TLS modules

---

## 1. Goal

Three production essentials that Hummingbird already provides — Roost
just needs to expose them through `ServerConfig` and the plug pipeline.

1. **HTTP/2** — multiplexed connections, header compression, server push.
   Already in the dep tree via `HummingbirdHTTP2`.

2. **TLS** — HTTPS termination without a reverse proxy. Already in the
   dep tree via `HummingbirdTLS`. Useful for development (self-signed
   certs) and simple deployments.

3. **Response compression** — gzip/deflate for text responses. Not in
   Hummingbird, but straightforward with a plug using `zlib`.

```swift
// In your app:
var server: ServerConfig {
    .init(
        host: "0.0.0.0",
        port: 443,
        tls: .init(certificatePath: "cert.pem", keyPath: "key.pem"),
        http2: true
    )
}

var plugs: [Plug] {
    [compress(), router()]
}
```

---

## 2. Scope

### Part A: HTTP/2

#### 2.1 ServerConfig Extension

```swift
public struct ServerConfig: Sendable {
    public var host: String
    public var port: Int
    public var tls: TLSConfig?
    public var http2: Bool  // default: false, auto-enabled when TLS is set

    public struct TLSConfig: Sendable {
        public var certificatePath: String
        public var keyPath: String
    }
}
```

When `tls` is set:
- HTTP/2 is automatically enabled via ALPN negotiation.
- HTTP/1.1 remains available as fallback.
- The `http2` flag can force HTTP/2 even without TLS (h2c) for local dev.

#### 2.2 Adapter Changes

Update `NexusHummingbird` adapter to configure Hummingbird's HTTP/2
channel handler when `http2` is true. This should require minimal
changes — Hummingbird's `HummingbirdHTTP2` module handles the protocol.

### Part B: TLS

#### 2.3 Certificate Configuration

Support two modes:

1. **File paths** — PEM-encoded certificate and private key files.
2. **Self-signed (dev only)** — `roost server --tls` generates an
   ephemeral self-signed certificate for local HTTPS development.

```swift
// Production: real certificates
var server: ServerConfig {
    .init(
        tls: .init(certificatePath: "/etc/ssl/cert.pem", keyPath: "/etc/ssl/key.pem")
    )
}
```

```bash
# Development: self-signed
$ roost server --tls
  Generated self-signed certificate for localhost
  Roost running on https://127.0.0.1:8080
```

#### 2.4 HTTPS Redirect Plug

A plug that redirects HTTP requests to HTTPS:

```swift
public func httpsRedirect() -> Plug
```

In production, redirect all HTTP requests to their HTTPS equivalent with
a 301 Moved Permanently. In dev, no-op (don't break local HTTP).

### Part C: Response Compression

#### 2.5 Compression Plug

```swift
public func compress(
    minBytes: Int = 860,
    level: CompressionLevel = .default,
    types: Set<String> = defaultCompressibleTypes
) -> Plug
```

Parameters:
- `minBytes` — don't compress responses smaller than this (overhead not
  worth it). Default 860 bytes (one TCP segment).
- `level` — compression level (1-9 for gzip, `.default` = 6).
- `types` — MIME types to compress. Default: text/*, application/json,
  application/javascript, application/xml, image/svg+xml.

#### 2.6 Algorithm Selection

Check the request's `Accept-Encoding` header:

1. Prefer `gzip` (widest support).
2. Fall back to `deflate`.
3. If neither is accepted, skip compression.

Set `Content-Encoding` and `Vary: Accept-Encoding` on compressed responses.

#### 2.7 Implementation

Use Foundation's `Data` compression or `zlib` directly:

```swift
import struct Foundation.Data

// Using zlib via C interop (available on all Swift platforms)
let compressed = try data.compressed(using: .zlib)
```

Or use `DataProtocol` extensions for streaming compression of large
response bodies.

#### 2.8 Exclusions

Never compress:
- Responses already compressed (`Content-Encoding` already set).
- Binary formats that are already compressed (images, video, zip, wasm).
- Responses smaller than `minBytes`.
- Responses without a body (204, 304).

---

## 3. Acceptance Criteria

### HTTP/2

- [ ] `ServerConfig` accepts `http2: true`
- [ ] HTTP/2 works when TLS is configured (ALPN h2)
- [ ] HTTP/1.1 fallback works
- [ ] h2c (cleartext HTTP/2) works for local dev
- [ ] Existing routes and plugs work unchanged over HTTP/2

### TLS

- [ ] `ServerConfig.TLSConfig` accepts certificate and key paths
- [ ] Server starts with HTTPS when TLS is configured
- [ ] `roost server --tls` generates self-signed cert for dev
- [ ] `httpsRedirect()` plug redirects HTTP to HTTPS in prod
- [ ] `httpsRedirect()` is a no-op in dev
- [ ] Invalid certificate paths produce a clear error

### Compression

- [ ] `compress()` plug gzips text responses
- [ ] Respects `Accept-Encoding` (gzip preferred, deflate fallback)
- [ ] Sets `Content-Encoding: gzip` and `Vary: Accept-Encoding`
- [ ] Skips responses smaller than `minBytes`
- [ ] Skips already-compressed responses
- [ ] Skips binary MIME types (image/png, application/zip, etc.)
- [ ] Configurable compression level
- [ ] Configurable MIME type filter
- [ ] `swift test` passes

---

## 4. Non-goals

- No automatic Let's Encrypt / ACME certificate management.
- No HTTP/3 (QUIC) support.
- No Brotli compression (gzip and deflate only).
- No streaming compression for chunked responses (compress full body only).
- No server push (HTTP/2 push is deprecated by browsers).
