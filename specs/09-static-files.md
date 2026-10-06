# Spec: Static File Serving

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Roost core (spec 01), Hummingbird

---

## 1. Goal

A Roost app that serves HTML needs to serve CSS, JavaScript, images, and
fonts. Today you'd need to manually configure Hummingbird's file middleware.
Roost should handle this by convention.

Drop files in `Public/`, and they're served. No configuration.

```
MyApp/
  Public/
    css/style.css     → GET /css/style.css
    js/app.js         → GET /js/app.js
    images/logo.png   → GET /images/logo.png
    favicon.ico       → GET /favicon.ico
```

---

## 2. Scope

### 2.1 Static File Plug

A plug that serves files from a configurable directory (default: `Public/`
relative to the working directory). Runs early in the pipeline — if a file
matches, it's served directly and the pipeline halts. If no file matches,
the request passes through to the router.

```swift
public func staticFiles(
    from directory: String = "Public",
    at prefix: String = "/"
) -> Plug
```

### 2.2 Convention

When `roost new` generates a project, it creates a `Public/` directory
with a `.gitkeep`. The default `plugs` pipeline includes `staticFiles()`
when the `Public/` directory exists.

### 2.3 MIME Types

The plug sets the correct `Content-Type` header based on file extension:

| Extension | Content-Type |
|-----------|-------------|
| `.html` | `text/html; charset=utf-8` |
| `.css` | `text/css; charset=utf-8` |
| `.js` | `application/javascript; charset=utf-8` |
| `.json` | `application/json` |
| `.png` | `image/png` |
| `.jpg`, `.jpeg` | `image/jpeg` |
| `.gif` | `image/gif` |
| `.svg` | `image/svg+xml` |
| `.ico` | `image/x-icon` |
| `.woff2` | `font/woff2` |
| `.woff` | `font/woff` |
| `.ttf` | `font/ttf` |
| `.pdf` | `application/pdf` |

Unknown extensions default to `application/octet-stream`.

### 2.4 Security

- **Path traversal prevention**: reject requests containing `..` segments.
- **No directory listing**: requests to directories return 404.
- **Hidden files**: skip files starting with `.` (no `.env` exposure).

### 2.5 Cache Headers

Set `Cache-Control` headers for static assets:

- **Development**: `no-cache` (always fresh during development).
- **Production**: `public, max-age=31536000, immutable` for fingerprinted
  assets (files containing a hash in the name), `public, max-age=3600`
  for non-fingerprinted assets.

### 2.6 CLI Integration

`roost new` generates:

```
Public/
  css/.gitkeep
  js/.gitkeep
  images/.gitkeep
```

---

## 3. Acceptance Criteria

- [ ] Files in `Public/` are served at their relative path
- [ ] Correct `Content-Type` is set for all common web file types
- [ ] Requests for non-existent files pass through to the router (not 404 from static plug)
- [ ] Path traversal (`../`) is rejected with 400
- [ ] Directory requests return 404 (no listing)
- [ ] Hidden files (`.env`, `.git`) are not served
- [ ] `Cache-Control` is `no-cache` in dev environment
- [ ] `Cache-Control` includes `max-age` in prod environment
- [ ] Static files are served before the router runs (early halt)
- [ ] `roost new` generates `Public/` directory structure
- [ ] Plug is configurable: custom directory and URL prefix
- [ ] `staticFiles(from: "Assets", at: "/static")` serves `Assets/foo.css` at `/static/foo.css`
- [ ] Works with `sendFile` under the hood (leverages Nexus's existing file serving)
- [ ] Large files are streamed, not loaded entirely into memory
- [ ] All types are Sendable
- [ ] `swift test` passes

---

## 4. Non-goals

- No asset fingerprinting or compilation (use esbuild, Vite, or similar externally).
- No Gzip/Brotli compression (can be added as a separate plug or reverse proxy concern).
- No ETags or conditional requests (keep it simple for v1).
- No server-side includes or preprocessing.
