# Moving to Roost.

The framework is now **Roost.** The falcon stays, and the wordmark ends with an
orange dot. Swift identifiers and shell commands omit the punctuation.

This is a breaking source rename. There are no deprecated modules or executable
aliases under the former name. Use this checkout for the renamed APIs; existing
release tags still contain the API from the time they were published.

## Application code

| Before | Now |
| --- | --- |
| `import Peregrine` | `import Roost` |
| `import PeregrineTest` | `import RoostTest` |
| `PeregrineApp` | `RoostApp` |
| `Peregrine.env` | `Roost.env` |
| `PeregrineToken`, `PeregrineMigrator`, etc. | `RoostToken`, `RoostMigrator`, etc. |
| `peregrine_staticFiles()`, `peregrine_csrfProtection()`, etc. | `roost_staticFiles()`, `roost_csrfProtection()`, etc. |
| `// peregrine:routes`, `// peregrine:plugs` | `// roost:routes`, `// roost:plugs` |

Update the SwiftPM dependency identity from `swift-peregrine` to `swift-roost`
and product names to `Roost` and `RoostTest`. The repository is
[`Maartz/swift-roost`](https://github.com/Maartz/swift-roost).

Do not name an application target `Roost`, `RoostTest`, or `RoostCLI`: those names
belong to framework modules. The reading-list example still displays **roost.**,
but its package, target, executable, and application type are `RoostExample`.

## Development commands

Build the CLI with `swift build --product roost`. Replace `peregrine` with `roost`
in scripts and shell aliases. All `PEREGRINE_*` configuration variables are now
`ROOST_*`, including `ENV`, `HOST`, `PORT`, and `ECOSYSTEM_PATH`.

For local development, from the framework checkout:

```sh
unset ROOST_ECOSYSTEM_PATH ROOST_ESW_PATH
export ROOST_FRAMEWORK_PATH="$PWD"
swift build --product roost
export ROOST_CLI="$(swift build --show-bin-path)/roost"
```

`ROOST_FRAMEWORK_PATH` allows an existing checkout to keep its directory name.
When omitted, generated apps look for `$ROOST_ECOSYSTEM_PATH/Roost`.
The reading-list helpers infer this path automatically.
ESW 1.5.0 and Spectro/Nexus 2.0.0 resolve from published packages. Set
`ROOST_ESW_PATH` only when you want to develop against a local ESW checkout.

## Runtime names

The default session cookie is now `_roost_session`. Internal session and auth
keys also use `_roost_`. Existing browser sessions do not carry over; users log in
again. Application records, passwords, and migration history are unchanged by
the framework rename.

The development metrics endpoint is now `/_roost/metrics`, and framework logger
labels use the `roost.` prefix. Update local dashboards or scripts that refer to
the former names. The generated Docker environment uses `ROOST_ENV`,
`ROOST_HOST`, and `ROOST_PORT`.

## Verify your app

Run `swift test`, then exercise sign-in, a form submission, and the app's JSON API.
For the included reading list, use `examples/Roost/check`; for the complete
generator workflow, use `scripts/check_generated_app.py`. Leave the ESW and
ecosystem overrides unset to verify the published companion dependencies.
