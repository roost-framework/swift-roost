<div align="center">
  <img src="website/assets/roost-mark.png" alt="The Roost falcon" width="144" height="144">
  <h1>roost<img src="assets/brand/orange-dot.svg" alt="." width="9" height="9"></h1>
  <p><strong>A good home for your Swift app.</strong></p>
  <p>A web framework inspired by Phoenix.<br>Built with Nexus, Spectro, and ESW.</p>
  <p>
    <a href="https://maartz.github.io/swift-roost/">Website</a> ·
    <a href="https://maartz.github.io/swift-roost/playground.html">Playground</a> ·
    <a href="#the-development-experience">The DX</a> ·
    <a href="#project-status">Project status</a>
  </p>
</div>

---

Roost brings the parts of a Swift web application together: routes, data,
templates, forms, authentication, and tests. The aim is familiar if you have
built with Phoenix: clear conventions, useful generators, and application code
you can follow from a request to the database.

**Less wiring. More building.**

## Start with a small change

[Open the playground →](https://maartz.github.io/swift-roost/playground.html)

Edit a counter, greet someone, or flip a Boolean. Change a supported value in
the Swift pane and run the example to update its preview. Copy or download the
source when you want to keep it.

The website offers **browser-only guided examples**. Its previews run in
JavaScript; it does not compile Swift or upload your code. The separate local
Roost Playground uses the real Swift compiler and ESW Live, and is still an
unpublished development project.

## A little Swift

The **Roost development API** starts with an application and its routes:

```swift
import Roost

@main
struct Hello: RoostApp {
    @RouteBuilder var routes: [Route] {
        GET("/") { conn in
            conn.text("Hello, Roost.")
        }

        GET("/hello/:name") { conn in
            try conn.json(value: [
                "hello": conn.params["name"] ?? "world"
            ])
        }
    }
}
```

Add middleware when the app needs it. Introduce a database when the domain needs
one. Keep business operations in contexts and let routes handle HTTP.

> **The rename is in progress.** The public default branch still exports
> `Peregrine`, `PeregrineTest`, and `peregrine`. The `Roost` names above, the
> updated generators below, and their setup guide are not published yet.
> The website and guided playground are live now.

## The development experience

The current Roost development workflow connects authentication and an
ownership-scoped resource in a few commands:

```sh
roost new ReadingRoom
cd ReadingRoom
roost gen auth
roost gen resource Bookmark title:string url:string read:bool --both --scope user_id
```

After database setup and migration, you have HTML pages and a JSON API calling
the same context. The generator supplies the model, input validation, routes,
ESW views, SQL migration, and tests. Ownership comes from the signed-in user.
Roost's migration commands delegate to Spectro, which applies and tracks the
versioned SQL files.

The reading-list demo on the [website](https://maartz.github.io/swift-roost/#example)
shows the direction: save a link, keep entered values when validation fails,
mark it as read, and keep each reader's queue private. The website demo is a
disposable browser preview; the local example is a PostgreSQL-backed Swift app.

| Part                          | What it gives your app                                                                     |
| ----------------------------- | ------------------------------------------------------------------------------------------ |
| Routes and middleware         | Swift handlers with explicit request and response flow.                                    |
| Contexts                      | A home for domain operations shared by HTML, JSON, and tests.                              |
| Spectro models and migrations | Typed PostgreSQL access and versioned schema changes.                                      |
| ESW templates                 | Server-rendered HTML compiled into Swift.                                                  |
| Browser integration           | Forms, CSRF protection, sessions, flash messages, and validation responses.                |
| The test harness              | In-process requests, browser cookie jars, and repository injection in the development API. |

## The stack

Roost builds on three focused Swift projects:

| Project                                           | Responsibility                                                                 |
| ------------------------------------------------- | ------------------------------------------------------------------------------ |
| [Nexus](https://github.com/Spectro-ORM/Nexus)     | HTTP connections, routing, middleware, and the Hummingbird adapter.            |
| [Spectro](https://github.com/Spectro-ORM/Spectro) | PostgreSQL models, queries, repositories, transactions, and migrations.        |
| [ESW](https://github.com/Spectro-ORM/ESW)         | HTML templates compiled by SwiftPM; ESW Live powers the local playground work. |

Roost provides the application lifecycle, conventions, generators, browser
integration, and testing tools that connect them.

## Project status

Roost is in active development. The rename from Peregrine and the improved
authenticated-resource workflow are being prepared for publication.

- The development framework supports **Nexus 2.0.0 and Spectro 2.0.0**. The
  public default branch still has the earlier dependency requirements in
  [Package.swift](Package.swift).
- The full multi-resource template workflow needs ESW's development fixes.
  It cannot yet be installed entirely from published releases.
- The local playground needs the companion development checkouts. Downloading
  a sample from the website does not install that toolchain.
- Phoenix is the inspiration. This project does not claim Phoenix or LiveView
  feature parity.

The main development focus is an authenticated PostgreSQL app with HTML,
JSON, migrations, and tests. Other APIs have uneven coverage: SMTP delivery,
the channel upgrade route, Valkey PubSub, and the PostgreSQL job queue still
contain stubs. TLS and HTTP/2 configuration also need bootstrap integration.
Keep those boundaries in mind when evaluating deployment.

## Explore the source

The public source still uses the earlier names while the rename is prepared:

| Directory                             | Contents                                                                   |
| ------------------------------------- | -------------------------------------------------------------------------- |
| [Framework](Sources/Peregrine)        | Application lifecycle, middleware, sessions, migrations, and integrations. |
| [CLI](Sources/PeregrineCLI)           | Project generators, development server, builds, and migration commands.    |
| [Test helpers](Sources/PeregrineTest) | In-process application and response helpers.                               |
| [Tests](Tests/PeregrineTests)         | Framework behavior checks.                                                 |
| [Website](website)                    | Static GitHub Pages site and guided playground.                            |
| [Specifications](specs)               | Design notes; these describe intent and may precede implementation.        |

For Swift work, start with the manifest and the implementation on the branch
you are using. The existing [Todo tutorial](guides/tutorial-todo-app.md) describes
the earlier API and is being revised alongside the rename.

To work on the website, no Swift or JavaScript build toolchain is needed:

```sh
python3 -m http.server 4077 --bind 127.0.0.1 --directory website
```

Open [localhost:4077](http://localhost:4077). The [website guide](website/README.md)
covers checks, preview behavior, and GitHub Pages deployment.

## Contributing

Start with a small, runnable improvement to the development loop. Include the
Swift version and companion package revisions when reporting a build problem.
For framework changes, run `swift test` and describe the application workflow
you exercised. For website changes, run the checks in its guide and review the
result at desktop and mobile widths.

Follow [project development](https://github.com/Maartz/swift-roost) or
[try a small change](https://maartz.github.io/swift-roost/playground.html).
