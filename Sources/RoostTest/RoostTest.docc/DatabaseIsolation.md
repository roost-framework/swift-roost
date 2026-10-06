# Database test isolation

Give each workflow clear ownership of its database client and transaction.

## Overview

Generated apps select the test environment inside ``TestApp``. With no explicit
`DB_NAME`, a configured base database name receives `_test`. An explicit
`DB_NAME` overrides that suffix, so verify it before running database tests.

Create the test database and run its migrations before exercising persistence.

### Inject one transaction repository

``withTestRollback(repository:_:)`` opens a transaction, runs the body, and
rolls back its writes even when the body succeeds. It propagates a real test or
database error after rollback.

For an existing `repository` and generated `ReadingRoom` application:

```swift
try await withTestRollback(repository: repository) { transaction in
    let app = try await TestApp(ReadingRoom.self, repository: transaction)
    let context = BookmarksContext(repo: transaction)
    // Call context operations and request handlers using this same transaction.
    // Assert their results before the closure returns.
    _ = context
    await app.shutdown()
}
```

The important property is shared ownership: contexts and the HTTP pipeline use
the same repository. `TestApp` skips creating its own database client when a
repository is injected. Route handlers using `conn.repo()` honor that injection;
handlers reaching directly for `conn.spectro` require an app-owned client.

The caller still owns the injected repository and its underlying client.
The harness does not shut them down.

### Use a disposable database for transaction-owning flows

Spectro rejects nested transactions. Registration and other operations that
start their own transaction cannot run inside `withTestRollback`.

Use an independently owned test database for those flows. The local reading-list
example's `./check` helper creates one, applies migrations, runs tests, and
removes that owned database afterward. The generated-app acceptance script uses
a similar ownership boundary.

### Close an app-owned client

When the harness creates a client from the app's database configuration, await
`app.shutdown()` after the test and in its error path. See <doc:TestingHTTP> for
the complete cleanup pattern.

Keep separate tests from sharing mutable database state accidentally.
Serialization alone does not restore a database; use rollback or owned
disposable databases according to the workflow's transaction behavior.
