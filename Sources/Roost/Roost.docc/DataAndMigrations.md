# Data, contexts, and migrations

Use Spectro repositories for domain operations and Spectro migrations for schema changes.

## Overview

Configure a database on ``RoostApp``:

```swift
let database: Database? = Database.postgres(database: "reading_room")
```

With no `DB_NAME` override, that becomes `reading_room_dev` in development,
`reading_room_test` in tests, and `reading_room` in production. Set `DB_NAME`
explicitly for deployment. See <doc:ConfigurationAndDeployment> for the full
configuration precedence.

### Give contexts a repository

Generated contexts store `any Repo`. Request handlers obtain it with
`conn.repo()`, which honors a repository injected by the test harness before
falling back to the application's Spectro client.

For the generated `Bookmark` model, an ownership-scoped context reads like this:

```swift
struct BookmarksContext: Sendable {
    let repo: any Repo

    func listBookmarks(scopeId: UUID) async throws -> [Bookmark] {
        try await repo.query(Bookmark.self)
            .where({ $0.userId == scopeId })
            .orderBy(\.createdAt, .asc)
            .all()
    }
}
```

This snippet assumes the `Bookmark` generated in <doc:CLIAndGenerators>.
Keep the ownership predicate inside the context. Direct callers and HTTP
handlers then use the same rule. Generated scoped reads, updates, and deletes
check the owner before accessing or changing a record.

`conn.spectro` accesses the application's concrete client. Prefer `conn.repo()`
in contexts and routes that should support transaction-owned repositories in
tests. A database must be configured, or a repository injected, before calling
these helpers.

### Validate at the domain boundary

A generated input type is shared by HTML and JSON. Form decoding preserves raw
values; domain validation checks the typed value again before persistence.
``Changeset`` collects ``ValidatorRule`` results, and `requireValid()` either
returns the value or throws ``ValidationErrors``.

For a small input:

```swift
struct NewBookmark: Sendable {
    let title: String

    func validated() async throws -> Self {
        var changeset = Changeset(data: self)
        await changeset.validate(using: [
            .required("title") { $0.title },
            .length("title", { $0.title }, max: 160)
        ])
        return try changeset.requireValid()
    }
}
```

Normalize input deliberately before validation. Never accept an ownership field
from the submitted body in place of the authenticated identity.

### Write a migration

``RoostMigrator`` delegates execution, status, and rollback to Spectro's
migration manager. It is not a separate migration engine.

SQL files live in `Sources/Migrations/`. The CLI generates ordered filenames
so referenced tables can be created before their dependents. Each file has an
up and a down section:

```sql
-- migrate:up
CREATE TABLE "reading_tags" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL
);

-- migrate:down
DROP TABLE "reading_tags";
```

Create an empty migration with:

```sh
"$ROOST_CLI" gen migration create_reading_tags
```

Fill in both sections of the generated file. Spectro applies each migration
transactionally and tracks its version in `schema_migrations`.

Spectro 2.1 also offers Swift declarations through the optional
`SpectroMigrations` product. Roost's generators and `RoostMigrator` continue
to use Spectro's SQL workflow. To opt into Swift declarations, add the separate
migration executable described in [Spectro's migration guide](https://github.com/Spectro-ORM/Spectro/blob/2.1.0/docs/MIGRATIONS.md).
Keep the IDs and SQL history of migrations already applied to your database.

### Run against the app's configuration

From the generated app root:

```sh
"$ROOST_CLI" migrate up
"$ROOST_CLI" migrate status
ROOST_ENV=test "$ROOST_CLI" migrate up
```

The CLI invokes the app's migration command, so the CLI and server use the same
database configuration. Create the development and test databases first.
Starting a server does not apply migrations automatically.

For a disposable development database, `"$ROOST_CLI" migrate down` rolls back
the latest migration. It executes the file's down section, which may remove
data; inspect that SQL before using it.

### Run the release binary

A compiled application also accepts the migration command:

```sh
ROOST_ENV=prod DB_NAME=reading_room .build/release/ReadingRoom migrate up
```

Supply the target database credentials in the environment. Run from the
application directory, or ship `Sources/Migrations/` beside the executable.
See <doc:ConfigurationAndDeployment> and <doc:TestingYourApp>.
