# Routes and middleware

Describe HTTP behavior in Swift and keep request processing explicit.

## Overview

``RoostApp`` uses the route builder and connection types from Nexus. Routes
name a controller action, which accepts a connection and returns the connection
containing its response. Asynchronous actions can call a context, and throwing
actions can report an HTTP error. <doc:Controllers> covers controllers,
`resources`, and permitted parameters in full.

### Return a response

```swift
import Roost

struct GreetingController: Controller {
    enum Action: String, ControllerAction { case show }

    static func action(_ action: Action) -> Plug {
        switch action {
        case .show: show
        }
    }

    static func show(_ conn: Connection) async throws -> Connection {
        let name = conn.params["name"] ?? "world"
        return try conn.json(value: ["greeting": "Hello, \(name)!"])
    }
}

@RouteBuilder
func greetingRoutes() -> [Route] {
    GET("/greeting/:name", GreetingController.self, .show)

    GET("/health") { conn in
        conn.text("ok")
    }
}
```

Include `greetingRoutes()` in your application's `routes` builder. Route
parameters come from `conn.params`; query parameters come from
`conn.queryParams`. `conn.text` and `conn.html` return text responses, while
`conn.json(value:)` encodes an `Encodable & Sendable` value. A closure route,
like `/health` here, suits a small endpoint; application endpoints use
controllers so requests are logged and traced by action.

For a UUID path parameter, use `try conn.requireParam("id")`. An invalid
identifier becomes a 400 response before you query the repository.

### Install middleware

Override `plugs` on the application to choose middleware and its order:

```swift
var plugs: [Plug] {
    [requestId(), roost_requestLogger(), roost_staticFiles()] + browserPlugs()
}
```

This replaces the default request-ID and logging list, so include those helpers
when you still want them. `roost_requestLogger()` logs each request once, with
its controller action and parameters, hiding secrets such as passwords and
tokens. Add `tracing()` for distributed tracing spans. See
<doc:Controllers#Log-and-trace-each-action>. Configure a session store as shown in
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
        resources("/recipes", RecipeAPIController.self, only: [.index, .show])
    }
}
```

The endpoints are `/api/recipes` and `/api/recipes/:id`. A scope can also carry
middleware. Declare a reusable pipeline as a `NamedPipeline` value, so routers in
different files share it and a misspelled name is a compile error:

```swift
let authenticated = NamedPipeline { requireAuth() }

@RouteBuilder
func privateRoutes() -> [Route] {
    scope("/account", pipelines: [authenticated]) {
        GET("/", AccountController.self, .show)
    }
}
```

`requireAuth()` runs after the application has loaded the current user. For a
plug that applies to some of one controller's actions, use the controller's
``Controller/plugs`` instead.

The string-named `pipeline("browser") { ... }` and `scope(_:pipelines:)` with
names are deprecated. An undeclared name now stops the app at startup instead
of serving routes without the pipeline's plugs.

### Follow the request lifecycle

Roost injects application services, installs the configured session store,
runs application middleware, and dispatches the router. The server and
`RoostTest.TestApp` use this same composition.

Each middleware step is wrapped in error handling. If a step throws, the error
response retains the connection returned by the last completed step. Session
writes finish before response hooks run, including on redirects and halted
responses. A failed session write produces an error without advertising an
unsaved session cookie.

Business operations belong in contexts that accept a repository. An action
should permit its input, obtain trusted identity, call the context, and render
or redirect.
See <doc:DataAndMigrations> and <doc:AuthenticationAndSessions>.
