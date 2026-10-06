# Views, layouts, and forms

Render typed ESW views with the current request's layout and CSRF context.

## Overview

Roost re-exports ESW, but file templates need a direct ESW package dependency and
`ESWBuildPlugin` on the application target. `roost new MyApp` configures both.
An app generated with `--no-esw` does not have that setup.

The typed-view APIs below are available in ESW 1.5.0, the minimum version used
by Roost and its generated applications.

### Define a typed view

Put `WelcomeView.swift` beside `welcome.esw` in the app's `Views/` directory:

```swift
import Roost

@ESWTemplate("welcome.esw")
struct WelcomeView {
    let name: String
}
```

The template begins directly with HTML. Its inputs are the Swift properties:

```html
<main>
  <h1>Hello, <%= name %>.</h1>
  <.form action="/greetings" method="post">
    <label for="name">Your name</label>
    <input id="name" name="name" value="<%= name %>" required>
    <button type="submit">Say hello</button>
  </.form>
</main>
```

ESW generates the renderer at build time and escapes ordinary dynamic output.
Unknown Swift names and incompatible types are compiler errors. The component
`<.form>` resolves to Roost's ``Form``.

### Render through the connection

Use this pattern inside an application whose target includes the ESW build
plugin and the two view files above:

```swift
import Roost

@main
struct WelcomeApp: RoostApp {
    let sessionStore: (any SessionStore)? = MemorySessionStore()

    var plugs: [Plug] {
        [requestId(), requestLogger()] + browserPlugs()
    }

    @RouteBuilder var routes: [Route] {
        GET("/") { conn in
            try conn.render(WelcomeView(name: "Ada"), title: "Welcome")
        }

        POST("/greetings") { conn in
            let name = try FormValues(conn.bodyParams)
                .decode("name", as: String.self)
            return try conn.render(WelcomeView(name: name), title: "Hello")
        }
    }
}
```

`conn.render` creates a request-local rendering scope. Local mutating forms
receive the token prepared by the session and CSRF middleware. A missing token
or invalid form configuration throws ``ViewRenderingError`` instead of emitting
an unprotected form. Directly calling a form view's `render()` bypasses this
response boundary.

GET forms and external forms do not receive a session token. PUT, PATCH, and
DELETE forms submit a POST with a hidden `_method` field. Form actions and
attributes are validated; attribute values are escaped. Component `content`
is already-rendered HTML, so do not pass unescaped visitor input as content.

### Apply one layout

Set `RoostApp.layout` once. Its ``HTMLLayout`` closure receives the connection,
page title, and rendered content:

```swift
var layout: HTMLLayout? {
    { conn, title, content in
        LayoutView(conn: conn, title: title, content: content).render()
    }
}
```

The generator creates `LayoutView` and `layout.esw` for this pattern. Escape the
title and any other plain data in the layout. Insert the already-rendered page
with ESW's explicit raw-output syntax, as the generated layout does, to avoid
escaping the HTML a second time.

### Retain invalid input

Keep `conn.bodyParams` when handling a form error. ``FormValues`` decodes values
without discarding their original text. An omitted nonoptional Boolean decodes
to `false`; an optional empty value can decode to `nil`. Decoding failures throw
``ValidationErrors``.

The generated resource catches those errors and renders the form again with
the submitted values, field errors, and status `.unprocessableContent` (422).
Its shared input type also performs domain validation through ``Changeset``,
so JSON and HTML callers follow the same rules.

### Use an inline fragment

For a small response that does not contain a request-aware form, an inline
template is enough:

```swift
GET("/fragment") { conn in
    let name = conn.queryParams["name"] ?? "world"
    return conn.html(#heex("<h1>Hello, {name}.</h1>"))
}
```

`conn.html` sends the supplied string directly. It does not apply
`RoostApp.layout` or establish the rendering context used by `Form`.
