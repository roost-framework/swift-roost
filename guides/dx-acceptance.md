# Authenticated Todo acceptance workflow

The target is a generated app that can register two users, create and edit Todos
through HTML forms and JSON, reject cross-user access, display validation errors,
and run the same routes under tests. A second resource checks ESW template naming.

Implementation checklist:

- [x] Share Nexus string sessions with Roost server sessions; persist flash before redirects.
- [x] Protect cookie-authenticated JSON requests with CSRF by default.
- [x] Generate repository-backed contexts and scoped CRUD for every operation.
- [x] Generate typed forms that preserve invalid input and render 422 field errors.
- [x] Generate auth using framework hashing, session renewal and indexed token lookup.
- [x] Wire generated routes, browser middleware, tests and migrations into a fresh app.
- [x] Refuse file overwrites and ensure ordered migration filenames.
- [x] Use the app's database configuration for CLI and release migrations.
- [x] Add isolated repository injection, cookie sessions and forms to RoostTest.
- [x] Execute a generated app against an isolated local PostgreSQL database.
- [x] Add generated-app CI and a Linux release check.
- [x] Complete the local Linux release build and runtime smoke test.

Existing work in sibling ESW, Nexus and Spectro repositories is preserved. The
only additional sibling change is renaming ESW's `ESWCompilerCLI/main.swift` to
`ESWCompilerCLI.swift`, with identical contents: Linux rejects `@main` in a file
named `main.swift`. Local ecosystem integration is reported separately from
validation of published dependency versions. No SwiftPM dependency checkout was
edited.

The existing schema types and PostgreSQL compatibility remain in place. No
production database is used. Tests own a uniquely named database and remove it
after completion. Production migrations remain an explicit command.

Verified 2026-10-04, before the framework rename: a fresh generation passed the full
macOS HTTP and PostgreSQL acceptance flow, including rollback of writes made via
TestApp. The baseline suite passed 429 runtime tests and 4 CLI tests both
with local ecosystem sources and with published dependencies. A Linux ARM64
optimized app build also passed. Its release payload (binary, public assets and
migrations) passed the full HTTP acceptance and migration up/status/down/up in
`swift:6.3.3-noble-slim`, against an isolated PostgreSQL 18 container. The container
ran with `PEREGRINE_ENV=prod` and without the source or build tree mounted.
The Linux release CLI also built and successfully ran `new`, `gen auth`, and
`gen resource ... --both --scope user_id` in the slim image. Its Linux-specific
CoreFoundation and FoundationNetworking imports are explicit.

The generated-app CI workflow is checked in but has not been run on GitHub in
this session. Its Linux x86-64 execution remains to be verified there.

Nexus release update, before the framework rename: the framework requires
published Nexus 2.0.0, verified at commit
`1fc010e02ac912ceca1c31a3304fca115117fc89`. All 433 baseline tests passed
with that published version. The PostgreSQL acceptance flow passed again on
macOS and Linux ARM64 with that same Nexus revision, including the Linux release
payload in the slim runtime image. Runtime linking resolved `libz.so.1` correctly.
Ecosystem CI defaults to the `2.0.0` tag. CI and generated Dockerfiles explicitly
install Nexus's Linux zlib dependencies. That acceptance run used local ESW and
Spectro sources for the generated-app flow.

Release coordination at that time: ESW 1.4.0 used basename-only output names,
so generated multi-resource apps needed a local ESW checkout with namespaced
output and the Linux entry-point rename. Spectro 2.0.0 supplied the rollback
fixes. ESW 1.5.0 now includes the template changes; the release verification
below supersedes that local-checkout requirement.

Compiler warnings in that run: repeated template basenames triggered ESW `#fileID`
warnings, and ESW/Spectro reference SwiftSyntax through different GitHub owner
URLs. Neither warning failed that acceptance run.

## Roost rename verification

The renamed framework passed the existing 433 tests with local ecosystem sources.
With published dependencies, 434 tests passed: 429 runtime tests and 5 CLI tests,
including a new check rejecting application names that collide with framework
modules. The reading-list example passed all 6 tests against an owned PostgreSQL
database under its new `RoostExample` module name.

A fresh `roost new` application compiled and passed the full macOS acceptance
workflow: auth, CSRF, flash, HTML forms, JSON, updates, two-user isolation, a second
resource, transaction rollback, and migration rollback/reapply. The running
reading-list app also passed a login and API probe using `_roost_session`.

The Linux evidence above predates the rename. The renamed CI workflow and its
Linux build have not been executed in this session. Source changes are still
local; the GitHub repository has been renamed to `Maartz/swift-roost`.

## Spectro 2.0.0 release verification

Roost now requires published Spectro 2.0.0, verified at tag commit
`b13c41cdda2e73fb2a7000399c7d8f450ab05f0e`. Nexus resolves to 2.0.0 at
`1fc010e02ac912ceca1c31a3304fca115117fc89`. The framework passed all 434 tests
with published dependencies, including published ESW 1.4.0.

The reading-list example passed all 6 PostgreSQL tests using published Spectro
and Nexus, with only ESW selected from local source. At that stage, its manifest
located the containing framework and sibling ESW checkout without helper
environment variables; the editor and command-line build resolved the same
Spectro/Nexus release versions. `./dev` and `./check` stopped requiring local
Spectro or Nexus checkouts. ESW's later release removes the remaining default
source override, as recorded below.

The restarted demo passed sign-in, HTML, JSON, and session-cookie probes. Spectro's
migration status reports all three existing migrations applied. CI's ecosystem
job now defaults both Spectro and Nexus to the `2.0.0` tag; hosted CI has not been
run in this session.

A fresh generated app also passed its 4 tests, an optimized macOS release build,
and the full PostgreSQL/HTTP acceptance flow. The release ran from a directory
containing only its executable, public assets, and migrations with `ROOST_ENV=prod`.
Authentication, CSRF, forms, JSON, two-user isolation, and migration rollback/reapply
passed against the published Spectro and Nexus 2.0.0 packages. The owned acceptance
database was removed afterward. This release check did not rerun Linux.

## ESW 1.5.0 release verification

Verified on macOS on 2026-10-05. The published ESW 1.5.0 tag resolves to
`8ff401e6efdf20cfc52d27cbfaf0fd0686e38337`. The framework manifest, generated
application manifests, and reading-list example require ESW 1.5.0 or later.
The example no longer silently selects a sibling ESW checkout. Explicit
`ROOST_ESW_PATH` and `ROOST_ECOSYSTEM_PATH` overrides remain available for
companion development.

With both overrides unset, all three manifests resolved ESW 1.5.0, Spectro
2.0.0, and Nexus 2.0.0 as remote source-control dependencies. Validation passed:

- 440 framework tests and 5 CLI tests.
- 8 reading-list tests against an owned PostgreSQL database, including typed
  views, request-aware forms, shared layouts, browser workflows, and ownership.
- A freshly generated application with authentication and two resources built
  successfully, applied all four Spectro migrations, and passed its 4 tests,
  including repository injection and transaction rollback.
- Its optimized macOS release passed the full HTTP acceptance flow from a
  separate directory containing only the executable, public assets, and
  migrations. Authentication, CSRF, flash, form validation, HTML/JSON updates,
  two-user ownership isolation, and the second resource all passed. The
  compiled app also rolled back and reapplied a migration; the owned database
  was removed afterward.
- Both DocC catalogs built with warnings treated as errors, for local browsing
  and the `/swift-roost/docs` hosting prefix. Each archive's 620 internal
  documentation destinations resolved.

The README, example instructions, tutorial, rename guide, and DocC quickstart
now use released companion packages. Only the renamed Roost framework still
needs a development checkout. CI's ecosystem job now defaults ESW to its
`1.5.0` tag. Linux and hosted GitHub Actions were not rerun for this update.

To reproduce from the framework checkout with local PostgreSQL available:

```sh
unset ROOST_ESW_PATH ROOST_ECOSYSTEM_PATH
swift test
./examples/Roost/check
python3 scripts/check_generated_app.py --release
python3 scripts/build_docs.py
```

## Roost 2.0.0 / Spectro 2.1.0 release preflight

The release candidate raises the Spectro minimum to 2.1.0, reports `roost
--version` as 2.0.0, and generates applications requiring published Roost 2.0.0.
The renamed source is merged with the published website and Linux fixes.

Before Spectro's 2.1.0 tag was available, macOS validation used an immutable
snapshot of its release-preparation commit
`4a75b08911b41cbbd3feb724c8527a32f98b16b6`, ESW 1.5.0 at
`8ff401e6efdf20cfc52d27cbfaf0fd0686e38337`, and Nexus 2.0.0 at
`1fc010e02ac912ceca1c31a3304fca115117fc89`. These were selected through the
existing ecosystem override; this is source compatibility evidence, not proof
that a published Spectro 2.1.0 package resolves.

- All 445 framework and CLI tests passed with Swift 6.4.
- The reading-list example passed all eight PostgreSQL tests from a clean copy
  outside the synced checkout; its owned test database was removed.
- A fresh generated app compiled, applied four migrations to an owned local
  PostgreSQL database, and passed its four tests, including rollback isolation.
- Its optimized executable passed the HTTP authentication, CSRF, flash,
  validation, HTML/JSON, two-user ownership, and second-resource checks.
- The copied release executable rolled back and reapplied a migration. The
  owned database was removed when acceptance completed.
- Generated manifests keep the published dependency as their default, with no
  hardcoded checkout path. `--published-framework` now checks a fresh app against
  the released Roost version reported by the CLI, with local overrides removed.
- The browser playground's eight checks and static-site checks passed. DocC
  conversion passed after the release guide updates; it does not exercise the
  database or network workflows.

Publication still requires the remote Spectro 2.1.0 tag, followed by verification
against published packages and the Roost release tag. Hosted Roost CI has not
run for this candidate yet.
