# Spec: Error Handling and Error Pages

**Status:** Proposed
**Date:** 2026-03-28
**Depends on:** Roost core framework (spec 01), Environment (spec 04)

---

## 1. Goal

When something goes wrong, the developer and the user should both get useful
information — but not the same information. In dev, show the full error with
a stack trace. In prod, show a clean error page. The framework handles this
by default so developers never ship a stack trace to production.

---

## 2. Scope

### 2.1 Default Error Rescue

Roost's default `main()` wraps the pipeline in `rescueErrors()` (already
exists in Nexus). Extend the behavior so the error response format depends on
environment and content negotiation:

**JSON request (`Accept: application/json`):**

```json
// dev
{
  "error": "NexusHTTPError",
  "status": 404,
  "message": "Donut not found",
  "detail": "DonutRoutes.swift:49 — guard let donut else { throw ... }"
}

// prod
{
  "error": "Not Found",
  "status": 404
}
```

**HTML request (`Accept: text/html`):**

Dev: a styled HTML page with error type, message, request details (method,
path, headers, params), and the pipeline trace showing which plug was
executing.

Prod: a minimal, clean error page. Users can override with custom templates.

### 2.2 Custom Error Pages

Override default error rendering by providing `.esw` templates:

```
Views/
  errors/
    404.esw     ← custom Not Found page
    500.esw     ← custom Server Error page
```

If present, Roost renders these instead of the default. The template
receives:

```html
<%!
var status: Int
var message: String
%>
<h1><%= status %></h1>
<p><%= message %></p>
```

### 2.3 Dev Error Page Content

The dev error page includes:

- **Error type and message** — e.g., `NexusHTTPError: Donut not found`
- **Status code** — 404
- **Request info** — method, path, query params, headers
- **Pipeline trace** — which plugs ran, which plug threw
- **Assigns snapshot** — current conn.assigns at time of error
- **Styling** — dark theme, monospace, readable (inline CSS, no external deps)

### 2.4 Infrastructure vs HTTP Errors

Following Nexus's ADR-004 contract:

| Error Type | Behavior |
|-----------|----------|
| `NexusHTTPError` (4xx/5xx) | Render error page with the specified status |
| Any other `Error` (infra) | Render 500, log the full error server-side |

Infrastructure errors (database down, encoding failure, etc.) always log the
full error on the server regardless of environment. Only the response to the
client changes.

---

## 3. Acceptance Criteria

- [ ] Default error rescue is always active (no opt-in needed)
- [ ] JSON errors include detail in dev, omit in prod
- [ ] HTML errors show styled debug page in dev
- [ ] HTML errors show clean minimal page in prod
- [ ] Custom `Views/errors/404.esw` overrides default 404 page
- [ ] Custom `Views/errors/500.esw` overrides default 500 page
- [ ] Custom error templates receive `status` and `message` assigns
- [ ] Dev error page shows: error type, message, status, request info, pipeline trace
- [ ] Infrastructure errors log full detail server-side in all environments
- [ ] Infrastructure errors never expose internals to the client in prod
- [ ] Content negotiation: JSON request gets JSON error, HTML request gets HTML error
- [ ] Error pages work without a database connection
- [ ] No external CSS/JS dependencies in default error pages

---

## 4. Non-goals

- No error tracking integration (Sentry, Bugsnag, etc.) — users add their own plug.
- No custom error types beyond `NexusHTTPError`.
- No error page hot-reload in dev (restart to see template changes).
