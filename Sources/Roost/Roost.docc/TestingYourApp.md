# Testing your app

Exercise the same request pipeline without starting an HTTP listener.

## Overview

The `RoostTest` product provides `TestApp`, `TestBrowser`, response inspection,
transaction rollback helpers, and in-process channel and SSE tools.

Add the `RoostTest` product to the app's test target. Generated manifests already
do this. Import `Testing` and `RoostTest`, then your app module with `@testable`.

Start with the test in <doc:GettingStarted>. In the documentation navigator,
open **RoostTest** for the detailed guides:

- **Testing HTTP requests** covers request bodies, responses, and owned resources.
- **Testing browser workflows** covers cookie jars, CSRF, redirects, and isolation.
- **Database test isolation** covers repository injection and rollback.

Tests that initialize an app-owned database client must await `app.shutdown()`
on success and failure. Injected repositories remain the caller's responsibility.
Use a test database for operations that begin their own transactions.

Passing in-process tests proves handler and middleware behavior. It does not
verify the HTTP listener, browser JavaScript, actual WebSocket transport,
deployment packaging, or a production database connection. The local
`scripts/check_generated_app.py` acceptance runner covers generated-app behavior
over real HTTP and an owned local PostgreSQL database.
