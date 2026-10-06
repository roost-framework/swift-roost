# Spec: Asset Pipeline & Default Styling

**Status:** Proposed
**Date:** 2026-03-29
**Depends on:** Static file serving (spec 09), CLI (specs 02, 04-05)

---

## 1. Goal

Generated Roost pages should look professional out of the box. No unstyled
HTML. No "add your own CSS" hand-waving. `roost new` gives you a beautiful
starting point, and `roost gen.auth` produces login pages you wouldn't be
embarrassed to ship.

Two modes:

- **Default: Pico CSS** — a classless CSS framework. Semantic HTML looks great
  with zero CSS classes. One `<link>` tag, no build step. Perfect for "no
  wasted motion."

- **Optional: Tailwind CSS** — via `--tailwind` flag. Downloads the Tailwind
  standalone CLI (no Node required, same approach as Phoenix). Full
  customization for production apps.

---

## 2. Scope

### Part A: Pico CSS (Default)

#### 2.1 Color Themes

Pico CSS offers color-themed variants. Roost defaults to **orange**
(matching the framework's brand) but supports all Pico colors via a flag:

```bash
$ roost new MyApp                    # default: orange
$ roost new MyApp --color pumpkin    # pumpkin theme
$ roost new MyApp --color blue       # blue theme
```

Available colors (from Pico v2):

`amber`, `blue`, `cyan`, `fuchsia`, `green`, `grey`, `indigo`, `jade`,
`lime`, `orange`, `pink`, `pumpkin`, `purple`, `red`, `sand`, `slate`,
`violet`, `yellow`, `zinc`

CDN pattern: `https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.{color}.min.css`

#### 2.2 Integration with `roost new`

When `roost new MyApp` runs:

1. Downloads the Pico CSS file for the chosen color into
   `Public/css/pico.min.css`.
2. Generates `layout.esw` with the correct `<link>` tag.
3. Creates `Public/css/app.css` with minimal custom styles (a place for
   app-specific overrides).

Generated `layout.esw`:
```html
<%!
var conn: Connection
var title: String
var content: String
%>
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><%= title %> — MyApp</title>
    <link rel="stylesheet" href="/css/pico.min.css">
    <link rel="stylesheet" href="/css/app.css">
</head>
<body>
    <main class="container">
        <%- content %>
    </main>
</body>
</html>
```

#### 2.3 Generated Page Quality

All generators (`gen.html`, `gen.auth`) produce semantic HTML that Pico
styles automatically:

- `<form>` with `<label>` + `<input>` → styled form fields
- `<button>` → styled button
- `<table>` with `<thead>` + `<tbody>` → styled table
- `<article>` → styled card
- `<nav>` → styled navigation
- `<details>` → styled accordion
- `<dialog>` → styled modal

No CSS classes required. The generated templates are clean, readable HTML.

#### 2.4 Dark Mode

Pico supports `data-theme="light"` and `data-theme="dark"` on the `<html>`
tag. The generated layout defaults to `"light"`. Apps can add a toggle by
switching the attribute.

### Part B: Tailwind CSS (Optional)

#### 2.5 Tailwind Flag

```bash
$ roost new MyApp --tailwind
```

This changes the generated project:

1. Downloads the Tailwind standalone CLI binary for the current platform
   into `.build/tailwindcss` (not committed to git).
2. Creates `tailwind.config.js` with content paths pointing to ESW templates.
3. Creates `Public/css/input.css` with Tailwind directives.
4. Adds a build step that compiles CSS before `swift build`.
5. The generated `.gitignore` includes `.build/tailwindcss`.

#### 2.6 Tailwind CLI Binary

The standalone CLI is a single binary — no Node.js required. This is the
same approach Phoenix uses:

```
https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-{os}-{arch}
```

Platforms:
- `tailwindcss-macos-arm64` (Apple Silicon)
- `tailwindcss-macos-x64` (Intel Mac)
- `tailwindcss-linux-x64` (Linux AMD64)
- `tailwindcss-linux-arm64` (Linux ARM64)

#### 2.7 Tailwind Config

Generated `tailwind.config.js`:

```js
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./Sources/**/*.esw", "./Sources/**/*.swift"],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

Generated `Public/css/input.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

#### 2.8 Tailwind Build Integration

`roost build` compiles CSS:

```bash
$ roost build
  Running tailwindcss...
  Building Swift...
  Build complete.
```

Under the hood:
```
.build/tailwindcss -i Public/css/input.css -o Public/css/app.css --minify
```

The `--watch` variant runs both Tailwind and Swift in parallel (see spec 13).

---

## 3. Acceptance Criteria

### Pico CSS (Default)

- [ ] `roost new MyApp` downloads Pico CSS orange into `Public/css/pico.min.css`
- [ ] `--color blue` downloads the blue variant instead
- [ ] All 19 Pico color names are accepted
- [ ] Invalid color names produce a clear error
- [ ] Generated `layout.esw` includes `<link>` to `/css/pico.min.css`
- [ ] Generated `Public/css/app.css` exists for custom overrides
- [ ] Generated HTML from `gen.html` looks styled (semantic HTML)
- [ ] Generated HTML from `gen.auth` looks styled (forms, buttons)
- [ ] `data-theme="light"` is set on `<html>` by default
- [ ] No CSS classes are required in generated templates
- [ ] Pico CSS file is served via `staticFiles()` plug

### Tailwind CSS (Optional)

- [ ] `roost new MyApp --tailwind` downloads the Tailwind CLI binary
- [ ] Correct binary is downloaded for the current OS/arch
- [ ] `tailwind.config.js` is generated with correct content paths
- [ ] `Public/css/input.css` is generated with Tailwind directives
- [ ] `.gitignore` excludes `.build/tailwindcss`
- [ ] `roost build` compiles Tailwind CSS before Swift build
- [ ] Generated CSS output is minified in production
- [ ] `--tailwind` and `--color` flags are mutually exclusive (clear error)

### Both

- [ ] `--no-esw` flag skips all CSS setup
- [ ] Downloaded files are cached (not re-downloaded on every command)
- [ ] Offline-friendly: works if CSS file was previously downloaded
- [ ] `swift test` passes

---

## 4. Non-goals

- No Sass/SCSS support (use Tailwind or plain CSS).
- No CSS bundling or minification beyond what Tailwind provides.
- No JavaScript bundling (use `<script>` tags or external tooling).
- No asset fingerprinting or digest hashing (reverse proxy concern).
- No CDN `<link>` fallback — always serve from `Public/` for offline dev.
- No hot module replacement for CSS (use `--watch` with full rebuild).
