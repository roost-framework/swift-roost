# Routes and middleware

Describe HTTP behavior in Swift and keep request processing explicit.

## Overview

``RoostApp`` uses the route builder and connection types from Nexus. A handler
accepts a connection and returns the connection containing its response.
Asynchronous handlers can call a context, and throwing handlers can report an
HTTP error.

### Return a response

```swift
import Roost

@RouteBuilder
func greetingRoutes() -> [Route] {
    GET("/greeting/:name") { conn in
        let name = conn.params["name"] ?? "world"
        return try conn.json(value: ["greeting": "Hello, \(name)!"])
    }

    GET("/health") { conn in
        conn.text("ok")
    }
}
```

Include `greetingRoutes()` in your application's `routes` builder. Route
parameters come from `conn.params`; query parameters come from
`conn.queryParams`. `conn.text` and `conn.html` return text responses, while
`conn.json(value:)` encodes an `Encodable & Sendable` value.

For a UUID path parameter, use `try conn.requireParam("id")`. An invalid
identifier becomes a 400 response before you query the repository.

### Install middleware

Override `plugs` on the application to choose middleware and its order:

```swift
var plugs: [Plug] {
    [requestId(), requestLogger(), roost_staticFiles()] + browserPlugs()
}
```

This replaces the default request-ID and logging list, so include those helpers
when you still want them. Configure a session store as shown in
<doc:AuthenticationAndSessions> before using the browser pipeline.

``browserPlugs()`` installs:

1. Body parsing with a 1 MiB limit.
2. Method override for HTML forms.
3. Flash loading.
4. CSRF protection, including cookie-authenticated JSON requests.

For a bearer-only API, build a separate middleware pipeline appropriate to that
authentication mechanism. A JSON content type alone does not make a browser
request exempt from CSRF.

### Group related routes

```swift
@RouteBuilder
func applicationRoutes() -> [Route] {
    scope("/api") {
        GET("/health") { conn in
            try conn.json(value: ["status": "ok"])
        }
    }
}
```

The endpoint is `/api/health`. A scoped route can also carry middleware, for
example `scope("/", plugs: [requireAuth()]) { privateRoutes() }` after the
application has loaded the current user.

### Follow the request lifecycle

Roost injects application services, installs the configured session store,
runs application middleware, and dispatches the router. The server and
`RoostTest.TestApp` use this same composition.

Each middleware step is wrapped in error handling. If a step throws, the error
response retains the connection returned by the last completed step. Session
writes finish before response hooks run, including on redirects and halted
responses. A failed session write produces an error without advertising an
unsaved session cookie.

Business operations belong in contexts that accept a repository. A route should
decode input, obtain trusted identity, call the context, and render or redirect.
See <doc:DataAndMigrations> and <doc:AuthenticationAndSessions>.
