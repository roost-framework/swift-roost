# CLI and generators

Create connected application files, then make the domain code your own.

## Overview

Build the CLI and keep `ROOST_FRAMEWORK_PATH` set as shown in
<doc:GettingStarted>. The commands below use `"$ROOST_CLI"` so no global
installation is required. If the binary is on your `PATH`, use `roost` directly.

### Generate a reading room

From the directory beside the framework:

```sh
"$ROOST_CLI" new ReadingRoom
cd ReadingRoom
"$ROOST_CLI" gen auth
"$ROOST_CLI" gen resource Bookmark title:string url:string read:bool --both --scope user_id
```

Use an app name distinct from `Roost`, `RoostTest`, and `RoostCLI`. Those names
belong to framework modules.

The resource command creates a Spectro model, repository-backed context, input
type, SQL migration, ESW views, HTML and JSON handlers, and input tests. It also
registers routes in the generated application. Authentication is generated
first so the ownership foreign key can reference the users table.

### Configure the local database

For a local PostgreSQL role matching your shell user:

```sh
export DB_USER="$USER"
export DB_PASSWORD=""
export DB_HOST=localhost
export DB_PORT=5432
unset DB_NAME

PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" PGHOST="$DB_HOST" PGPORT="$DB_PORT" createdb reading_room_dev
PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" PGHOST="$DB_HOST" PGPORT="$DB_PORT" createdb reading_room_test

"$ROOST_CLI" migrate up
ROOST_ENV=test "$ROOST_CLI" migrate up
swift test
"$ROOST_CLI" server --port 8080
```

Use your own local credentials if they differ. The `DB_NAME` override is unset
here so development and tests select distinct databases from the generated
base name.

Register at `/auth/register`, then visit `/bookmarks`. The JSON resource is at
`/api/bookmarks`. Its mutating requests use the session cookie and CSRF token.

### Find the generated code

```text
ReadingRoom/
├── Package.swift
├── Sources/
│   ├── ReadingRoom/
│   │   ├── App.swift
│   │   ├── Models/
│   │   ├── Contexts/
│   │   ├── Routes/
│   │   ├── Plugs/
│   │   └── Views/
│   └── Migrations/
├── Public/
└── Tests/ReadingRoomTests/
```

Add business rules to the context or shared input type. Add transport behavior
to routes. Change the typed view and template together when their inputs change.
Generators refuse file overwrites; after generation, the files are yours to edit.

The local `examples/Roost` reading-list app demonstrates this structure with
validation, filtering, private reading queues, and PostgreSQL workflow tests.
Its `./dev` and `./check` helpers own local setup and disposable test databases.

### Choose the output you need

| Command or option | Result |
| --- | --- |
| `new MyApp` | App with database configuration, ESW, and Pico CSS. |
| `new MyAPI --no-db --no-esw` | Starter without database setup or file templates. |
| `new MyApp --tailwind` | Tailwind configuration instead of Pico. |
| `gen resource Post title:string` | HTML CRUD resource. |
| `gen resource Post title:string --json` | JSON resource. |
| `gen resource Post title:string --both` | Both transports sharing one context. |
| `gen resource Post title:string --model-only` | Model, context, migration, and input tests. |
| `gen migration add_post_index` | Empty SQL migration to fill in. |
| `migrate up / down / status` | App-configured migration operations. |
| `server --port 8080` | Build, serve, and watch for edits. |
| `build` | Build the app and its configured CSS assets. |
| `gen dockerfile` | Generate the Linux container build and runtime recipe. |

Run `"$ROOST_CLI" <command> --help` for the command's supported options.
There are no database-create, database-drop, or seed CLI commands in this
version; create databases with PostgreSQL tools or an application helper.
