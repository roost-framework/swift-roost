# Spec: Development Server with Watch Mode

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** CLI (specs 02, 04-05), Asset pipeline (spec 12)

---

## 1. Goal

The development loop today is: edit code → `Ctrl+C` → `swift run` → wait for
compile → test. This is painful. Every other framework has solved this:

- **Phoenix:** `mix phx.server` watches files and recompiles on change.
- **Rails:** `bin/dev` runs server + CSS watcher via `Procfile.dev`.
- **Vapor:** no built-in watcher (people use `entr` or `watchexec`).

Roost should make the dev loop fast and automatic:

```bash
$ roost build --watch
  Watching Sources/ and Public/ for changes...
  Building...
  Build complete. (2.1s)
  Roost running on http://127.0.0.1:8080

  [changed] Sources/DonutShop/Routes/DonutRoutes.swift
  Rebuilding...
  Build complete. (0.8s)
  Server restarted.
```

One command. Edit a file. See the result.

---

## 2. Scope

### 2.1 `roost build`

A build command that compiles assets (if Tailwind) and Swift in sequence:

```bash
$ roost build
```

Steps:
1. If `tailwind.config.js` exists: run Tailwind CLI to compile CSS.
2. Run `swift build`.

This replaces `swift build` as the standard build command for Roost
projects, since it handles both assets and Swift.

### 2.2 `roost build --watch`

A development mode that:

1. Performs an initial build (assets + Swift).
2. Starts the compiled server binary.
3. Watches for file changes in configured directories.
4. On change: kills the server, rebuilds, restarts.

```bash
$ roost build --watch
$ roost build --watch --port 4000   # custom port
```

#### Watch Targets

| Path | Triggers |
|------|----------|
| `Sources/**/*.swift` | Swift rebuild + server restart |
| `Sources/**/*.esw` | Swift rebuild + server restart (ESW compiles at build time) |
| `Public/**/*` | No rebuild needed (static files served directly) |
| `tailwind.config.js` | Tailwind rebuild + server restart |
| `Public/css/input.css` | Tailwind rebuild only |

#### Debouncing

File system events are debounced (300ms) to avoid rebuilding multiple times
when saving multiple files at once or when editors create temporary files.

### 2.3 File Watching Implementation

Use `DispatchSource.makeFileSystemObjectSource` (macOS) or `inotify` (Linux)
for native file watching. No external dependencies.

Alternatively, use a polling approach (check modification times every 500ms)
for maximum portability. This is simpler and reliable enough for development.

### 2.4 Process Management

The watch mode manages the server process:

1. **Start:** spawn the compiled binary as a child process, forward stdout/stderr.
2. **Restart:** send SIGTERM to the running process, wait for exit (max 2s),
   then start the new binary.
3. **Stop:** on `Ctrl+C`, kill the child process and exit cleanly.

The server binary path is `.build/debug/{AppName}` (discovered from
Package.swift via `ProjectDiscovery`).

### 2.5 Console Output

Clear, color-coded output so the developer knows what's happening:

```
[roost] Watching for changes...
[roost] Building... done (1.8s)
[roost] Server started on http://127.0.0.1:8080

[roost] Changed: Sources/DonutShop/Routes/DonutRoutes.swift
[roost] Rebuilding... done (0.6s)
[roost] Server restarted.

[roost] Build failed:
            error: type 'Donut' has no member 'nam'
            → Sources/DonutShop/Routes/DonutRoutes.swift:12:42
[roost] Fix the error and save to retry.
```

Key behaviors:
- On **build success**: restart the server silently.
- On **build failure**: show the error, keep the old server running (if still
  alive), wait for the next file change to retry.
- **Don't clear the screen** — errors should remain visible.

### 2.6 Tailwind Watch Integration

When `tailwind.config.js` exists and `--watch` is active:

1. Start Tailwind CLI in watch mode as a separate process:
   ```
   .build/tailwindcss -i Public/css/input.css -o Public/css/app.css --watch
   ```
2. Tailwind watches its own content paths and recompiles CSS automatically.
3. Since CSS is in `Public/`, it's served directly by `staticFiles()` —
   no server restart needed for CSS-only changes.
4. On `Ctrl+C`, kill both the Tailwind process and the server process.

### 2.7 Upgrade of `roost server`

The existing `roost server` command (Sprint 5) becomes an alias for
`roost build --watch`:

```bash
$ roost server           # same as: roost build --watch
$ roost server --port 4000
```

The non-watch `roost build` remains for CI and production builds.

---

## 3. Acceptance Criteria

### `roost build`

- [ ] Compiles Tailwind CSS if `tailwind.config.js` exists
- [ ] Runs `swift build` after CSS compilation
- [ ] Returns non-zero exit code if either step fails
- [ ] Works without Tailwind (Swift-only build)
- [ ] Shows build duration

### `roost build --watch`

- [ ] Performs initial build and starts the server
- [ ] Detects changes to `.swift` files in `Sources/`
- [ ] Detects changes to `.esw` files in `Sources/`
- [ ] Rebuilds and restarts the server on source changes
- [ ] Does NOT restart for changes in `Public/` (static files served live)
- [ ] Debounces rapid file changes (300ms window)
- [ ] Shows which file changed before rebuilding
- [ ] Shows build duration after each rebuild
- [ ] On build failure: shows error, does NOT kill the running server
- [ ] On build failure: retries on next file change
- [ ] Clean shutdown on `Ctrl+C` (kills server process)
- [ ] `--port` flag is forwarded to the server
- [ ] Server stdout/stderr is forwarded to the terminal

### Tailwind Integration

- [ ] Starts Tailwind CLI in watch mode alongside the server
- [ ] Tailwind CSS changes appear without server restart
- [ ] Both processes are killed on `Ctrl+C`
- [ ] Works without Tailwind (Pico-only projects)

### `roost server`

- [ ] Acts as alias for `roost build --watch`
- [ ] Accepts `--port` flag

### General

- [ ] No external dependencies for file watching (uses OS primitives or polling)
- [ ] Works on macOS and Linux
- [ ] Temporary files from editors (`.swp`, `~`, `.tmp`) are ignored
- [ ] `swift test` passes

---

## 4. Non-goals

- No browser auto-reload / live reload (no WebSocket injection into pages).
- No hot module replacement (full rebuild on every change).
- No incremental Swift compilation management (rely on SwiftPM's own caching).
- No `Procfile` or multi-process orchestration beyond Tailwind + server.
- No remote development or tunneling (use ngrok/cloudflared separately).
