# Project status

Distinguish the implemented application workflow from development integrations.

## Overview

This catalog is generated from the current Roost development checkout. It
documents the renamed framework and its current generators. The public default
branch and older releases may still use the previous names.

The core development path is a PostgreSQL-backed app with authentication,
ownership-scoped resources, HTML and JSON responses, Spectro migrations,
and in-process tests.

### Dependency and release boundaries

The framework and generated applications use published Nexus 2.0.0, Spectro
2.0.0, and ESW 1.5.0. ESW's release includes typed views and namespaced generated
output, so companion source checkouts are optional. The renamed Roost package
still requires this development checkout; follow <doc:GettingStarted>.

The detailed acceptance record is kept in `guides/dx-acceptance.md` in the
checkout. Earlier Linux evidence predates the framework rename; it is separate
from later macOS checks. A documentation build does not rerun that acceptance
workflow or establish production readiness.

### Service implementation status

| Area | Current boundary |
| --- | --- |
| Sessions | Memory store works within one process; persistent or shared storage needs another implementation. |
| PubSub | In-memory implementation is available; the Valkey adapter is unfinished. |
| Jobs | In-memory queue is available; the PostgreSQL store is a stub. |
| Mail | Logger and test deliveries are available; SMTP delivery is a stub. |
| Channels | In-process registry and test helpers exist; the HTTP upgrade route is a stub. |
| TLS / HTTP/2 | Configuration types exist; application bootstrap does not wire them into the server. |
| Live views | The separate local Roost Playground integrates ESW Live; this is not a Phoenix LiveView implementation. |

Reference pages include these public declarations so you can inspect their
contracts. Their presence in the navigator does not mean their external
transport or storage adapter is complete.

### Browser and local playgrounds

The [website playground](https://maartz.github.io/swift-roost/playground.html)
runs three guided JavaScript previews of Swift examples. It does not compile or
execute arbitrary Swift.

The separate local Roost Playground compiles Swift and integrates ESW Live.
Its setup depends on companion development checkouts. It is a different
execution environment from the website, and successful rebuilds reset live
state.
