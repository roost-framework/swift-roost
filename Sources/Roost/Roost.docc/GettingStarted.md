# Getting started

Generate a small app, run its first route, and test it without a database.

## Overview

This guide uses Roost 2.0.0 with published ESW 1.5.0,
Spectro 2.x (from 2.0.0), and Nexus 2.0.0. You need Swift 6.3 or later and macOS 14+ or a
supported Linux environment. On Debian/Ubuntu, Nexus also needs `zlib1g-dev`
at build time and `zlib1g` at runtime.

Generated apps resolve released packages directly. No companion source
checkouts or dependency overrides are required.

### Install the CLI

Install the CLI with [Mint](https://github.com/yonaskolb/Mint):

```sh
brew install mint
mint install roost-framework/swift-roost@2.0.1
roost --version
```

Mint builds the release from source and links `roost` into `~/.mint/bin`; add
that directory to your `PATH`. The first install resolves the framework's full
package graph, so it takes a few minutes. Leave `ROOST_FRAMEWORK_PATH`,
`ROOST_ECOSYSTEM_PATH`, and `ROOST_ESW_PATH` unset to select published versions
of Roost and its companion packages.

Without Mint, for example on Linux, build from a checkout:

```sh
git clone --branch 2.0.1 --depth 1 https://github.com/roost-framework/swift-roost.git
cd swift-roost
swift build -c release --product roost
```

Then copy `.build/release/roost` to a directory on your `PATH`.

### Create an application

Create the app:

```sh
roost new HelloApp --no-db --no-esw
cd HelloApp
roost server --port 8080
```

Open [localhost:8080](http://localhost:8080). The generated app returns a JSON
welcome message. This starter needs no PostgreSQL server or templates.

The development server watches Swift and template files. A successful build
restarts the app. A failed build prints diagnostics and leaves the previous
server available. Refresh the browser after a successful restart; this command
does not provide live state preservation.

### Write a route

Replace `Sources/HelloApp/App.swift` with this complete application:

```swift
import Roost

@main
struct HelloApp: RoostApp {
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

Only the routes are required here. The default application has no database or
sessions and binds to `127.0.0.1:8080`. Nexus provides the connection and route
types re-exported by Roost.

### Test the application

Stop the server with Ctrl-C, then replace the generated welcome test in
`Tests/HelloAppTests/AppTests.swift` to match the new response:

```swift
import Testing
import RoostTest
@testable import HelloApp

@Test func homeResponds() async throws {
    let app = try await TestApp(HelloApp.self, database: .some(nil))
    let response = try await app.get("/")
    #expect(response.status == .ok)
    #expect(response.text == "Hello, Roost.")
    await app.shutdown()
}
```

Run `swift test`. `TestApp` exercises the application's middleware and routes
in-process; it does not bind a network port.

### Choose the next step

- Add JSON handlers and middleware with <doc:RoutingAndMiddleware>.
- Add compiled HTML and request-aware forms with <doc:ViewsAndForms>.
- Generate an authenticated app with <doc:CLIAndGenerators>.
- Try [the browser playground](https://roost-framework.github.io/swift-roost/playground.html)
  for a guided preview without installing Swift. That preview simulates its
  supported examples in JavaScript; it does not execute arbitrary Swift.
