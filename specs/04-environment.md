# Spec: Environment Configuration

**Status:** Proposed
**Date:** 2026-03-28
**Depends on:** Roost core framework (spec 01)

---

## 1. Goal

Roost apps need to behave differently in development, test, and production
without `#if` flags or manual env var checking scattered through code. Provide
a lightweight environment system — not a config file DSL, just a clear
convention for how environment shapes behavior.

```swift
if Roost.env == .dev {
    // verbose logging, pretty-printed JSON
}
```

---

## 2. Scope

### 2.1 `Environment` Enum

```swift
public enum Environment: String, Sendable {
    case dev
    case test
    case prod
}
```

Read from `ROOST_ENV` env var. Default: `.dev`.

```swift
public enum Roost {
    /// Current environment. Read once at startup from ROOST_ENV.
    public static let env: Environment = {
        guard let raw = ProcessInfo.processInfo.environment["ROOST_ENV"] else {
            return .dev
        }
        return Environment(rawValue: raw) ?? .dev
    }()
}
```

### 2.2 Environment-Aware Defaults

The `RoostApp` default implementations change behavior based on
environment:

| Behavior | dev | test | prod |
|----------|-----|------|------|
| Default log level | debug | warning | info |
| Pretty-print JSON | yes | no | no |
| Error detail in responses | full stack trace | message only | generic "Internal Server Error" |
| Startup banner | yes | no | yes |
| CORS default | `*` (permissive) | `*` | none (must configure) |

### 2.3 `RoostApp` Environment Hook

```swift
extension RoostApp {
    /// Override to configure per-environment behavior.
    /// Called during main() before pipeline construction.
    public func configure(for env: Environment) { }
}
```

Example:

```swift
func configure(for env: Environment) {
    switch env {
    case .prod:
        // force HTTPS, strict CORS
        break
    case .dev:
        // seed sample data
        break
    case .test:
        break
    }
}
```

### 2.4 Database Per Environment

Convention for database naming:

```swift
Database.postgres(database: "donut_shop") // reads ROOST_ENV

// Resolves to:
// dev:  donut_shop_dev   (or donut_shop if DB_NAME is set)
// test: donut_shop_test
// prod: reads DB_NAME (required, no suffix)
```

In dev/test, append `_dev`/`_test` suffix unless `DB_NAME` is explicitly set.
In prod, `DB_NAME` env var is required — no guessing.

---

## 3. Acceptance Criteria

- [ ] `Roost.env` reads from `ROOST_ENV` env var
- [ ] Defaults to `.dev` when env var is unset
- [ ] Accepts "dev", "test", "prod" as valid values
- [ ] Invalid values fall back to `.dev`
- [ ] Error responses show full detail in dev, generic message in prod
- [ ] JSON is pretty-printed in dev only
- [ ] Startup banner is suppressed in test environment
- [ ] `configure(for:)` hook is called during startup
- [ ] Database name convention: `_dev`/`_test` suffix in non-prod unless `DB_NAME` is explicit
- [ ] In prod, missing `DB_NAME` env var is a fatal error with clear message
- [ ] All types compile under Swift 6 strict concurrency

---

## 4. Non-goals

- No `.env` file loading (use `direnv`, `mise`, or shell profiles).
- No YAML/TOML/JSON configuration files.
- No per-environment config structs or builder pattern.
- No secrets management — use env vars or a vault.
- Keep it simple: an enum, a few defaults, one hook. That's it.
