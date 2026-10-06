# Library Websites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish Roost-styled single-page websites for Spectro, Nexus, and ESW, link them with the Roost site, and retire the old Spectro and Nexus site repositories.

**Architecture:** Each library repository gets a static `website/` directory (copied and pruned from `swift-roost/website/`) and a `pages.yml` workflow that checks and deploys it to GitHub Pages at `https://roost-framework.github.io/<Repo>/`. A shared `check.py` acts as the test suite: links, fragments, ids, alt text, fonts, forbidden strings, and unused CSS classes. Spectro is built first and reviewed by the user; Nexus and ESW copy its shared files.

**Tech Stack:** Static HTML, CSS, and vanilla JavaScript; Python 3 standard library for checks; GitHub Actions and GitHub Pages; `gh` CLI; Chrome DevTools MCP for visual and accessibility checks.

**Spec:** `docs/superpowers/specs/2026-10-06-library-websites-design.md`

## Global Constraints

- Local clones: `~/Documents/swift-projects/{Spectro,Nexus,esw,Peregrine,spectro-website,nexus-website}`. `Peregrine` is the swift-roost clone and the source of the Roost site.
- Site URLs, exact case: `https://roost-framework.github.io/Spectro/`, `/Nexus/`, `/ESW/`, and Roost at `/swift-roost/`.
- Shared tokens, copied verbatim from Roost: `--paper #f0f4fa`, `--surface #fff`, `--ink #21314a`, `--muted #596980`, `--blue #2855b6`, `--line #d6dfec`, `--code #202f47`, Manrope and IBM Plex Mono fonts with their OFL licences.
- Accents: Spectro violet `#6d4ed8`, Nexus teal `#0e7c7b`, ESW green `#2f7d32`. Roost's `--orange`/`.orange` become `--accent`/`.accent`; the selection colour `#de503333` becomes the accent plus `33`.
- Versions: Roost 2.0, Spectro 2.1 (`2.1.0`), Nexus 2.0 (`2.0.0`), ESW 1.5 (`1.5.0`).
- Requirements lines: Spectro "Swift 6.0+ · macOS 13+ or Linux · PostgreSQL"; Nexus "Swift 6.0+ · macOS 14+, iOS 17+ or Linux"; ESW "Swift 6.3+ · macOS 14+".
- Light theme only. No playground, no hosted DocC, no new JavaScript features beyond Roost's copy buttons and tabs.
- Code samples are used exactly as written in this plan; each was checked against the library sources at its release tag.
- Never stage the user's unrelated working-tree changes (untracked `CLAUDE.md` files, `.aider*` files). Stage explicit paths only.
- The machine's `~/Documents` is iCloud-synced; no Swift builds are needed for this plan.

## Review Focus

- A phone 390 px wide: long code lines scroll inside their code window and the page itself never scrolls sideways. Tested in each site task (Step "Visual and accessibility check").
- JavaScript disabled: all three tour panels and every code sample stay readable, copy buttons stay hidden. Tested by the static grep step in each site task: no tour panel carries `hidden` in the HTML source.
- Keyboard users: the first Tab lands on "Skip to content", and Left/Right arrows move between tour tabs. Tested in the visual check step.
- A link to a tour panel (`…/#query-panel`) opens with that tab selected. Tested in the visual check step.
- A visitor typing the lowercase URL (`/spectro/`): the exact-case URL must work; the lowercase result is recorded and reported, not worked around. Tested in each deploy verification step.

---

### Task 1: Spectro website

**Files (all in `~/Documents/swift-projects/Spectro`):**
- Create: `website/check.py`, `website/index.html`, `website/404.html`, `website/style.css`, `website/script.js`, `website/robots.txt`, `website/sitemap.xml`, `website/.nojekyll`, `website/README.md`, `website/assets/mark.svg`, `website/assets/fonts/*`
- Create: `.github/workflows/pages.yml`

**Interfaces:**
- Consumes: Roost site files in `~/Documents/swift-projects/Peregrine/website/`.
- Produces: `website/check.py`, `website/style.css` (pruned, `--accent`), `website/script.js`, `website/assets/fonts/`, and `.github/workflows/pages.yml`, which Tasks 2 and 3 copy. HTML class vocabulary used by all three sites: `skip-link site-header wrap brand accent nav-github hero hero-copy development status-dot hero-description hero-detail hero-actions button text-link hero-note hello-window code-window window-bar file-dot copy-button response-line response-status hello-result window-caption stack-strip stack-intro stack-name stack-detail version framework-section section-space section-heading eyebrow framework-content principles workflow-section heading-row code-tour tour-tabs tour-tab tour-panel tour-explanation source-label tour-code light-copy light-key light-string syn-key syn-attribute syn-type syn-call syn-string syn-comment workflow-grid workflow-copy terminal-window closing site-footer sr-only`.

- [ ] **Step 1: Write the site checker (the test)**

Create `website/check.py`:

```python
#!/usr/bin/env python3
"""Check the static site's links, fragments, images, fonts, styles, and enhancement targets."""
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import re

ROOT = Path(__file__).resolve().parent
PAGES_ROOT = "/Spectro/"  # Project Pages root used by the 404 document.
FORBIDDEN = ("orange", "Spectro-ORM", "maartz")


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.ids = []
        self.urls = []
        self.targets = []
        self.images = []
        self.classes = set()
        self.feed(text)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            self.ids.append(attrs["id"])
        self.classes.update((attrs.get("class") or "").split())
        self.urls.extend(attrs[key] for key in ("href", "src") if key in attrs)
        self.targets.extend(attrs[key] for key in ("data-copy", "data-panel") if key in attrs)
        for key in ("aria-controls", "aria-labelledby", "aria-describedby", "for"):
            self.targets.extend(attrs.get(key, "").split())
        if tag == "img":
            self.images.append(attrs)


errors = []
if not (ROOT / "index.html").is_file():
    errors.append("missing index.html")

used_classes = set()
for path in ROOT.glob("*.html"):
    page = Page(path.read_text())
    used_classes |= page.classes
    errors.extend(f"{path.name}: duplicate id {key}" for key, count in Counter(page.ids).items() if count > 1)
    errors.extend(f"{path.name}: missing target #{target}" for target in page.targets if target not in page.ids)
    for image in page.images:
        if "alt" not in image:
            errors.append(f"{path.name}: image without alt text: {image.get('src')}")
    for address in page.urls:
        url = urlsplit(address)
        if url.scheme or url.netloc or url.path == PAGES_ROOT:
            continue
        target = ROOT / (url.path or path.name)
        if url.path and not target.exists():
            errors.append(f"{path.name}: missing file {url.path}")
        if url.fragment and target.is_file() and target.suffix == ".html":
            if url.fragment not in Page(target.read_text()).ids:
                errors.append(f"{path.name}: missing fragment {address}")

for path in [*ROOT.glob("*.html"), *ROOT.glob("*.css"), *ROOT.glob("*.js")]:
    text = path.read_text()
    errors.extend(f"{path.name}: contains {word!r}" for word in FORBIDDEN if word in text)

for stylesheet in ROOT.glob("*.css"):
    text = stylesheet.read_text()
    for asset in re.findall(r"url\(['\"]?([^)'\"]+)", text):
        if not urlsplit(asset).scheme and not (stylesheet.parent / asset).is_file():
            errors.append(f"{stylesheet.name}: missing asset {asset}")
    rules = re.sub(r"/\*.*?\*/|url\([^)]*\)", "", text, flags=re.S)
    selectors = " ".join(re.findall(r"([^{}]+)\{", rules))
    for name in sorted(set(re.findall(r"\.(-?[_a-zA-Z][\w-]*)", selectors)) - used_classes):
        errors.append(f"{stylesheet.name}: unused class .{name}")

if errors:
    raise SystemExit("\n".join(errors))
print("Site check passed: links, fragments, images, fonts, styles, and enhancement targets.")
```

- [ ] **Step 2: Run the checker to verify it fails**

Run: `cd ~/Documents/swift-projects/Spectro && python3 website/check.py`
Expected: exit 1 with `missing index.html`.

- [ ] **Step 3: Copy shared assets and adapt the stylesheet**

```bash
cd ~/Documents/swift-projects/Spectro
R=~/Documents/swift-projects/Peregrine/website
mkdir -p website/assets/fonts .github/workflows
cp $R/assets/fonts/* website/assets/fonts/
cp $R/style.css website/style.css
perl -pi -e 's/--orange: #de5033;/--accent: #6d4ed8;/; s/#de503333/#6d4ed833/; s/--orange/--accent/g; s/\.orange\b/.accent/g' website/style.css
sed -n 1,76p $R/script.js > website/script.js
perl -pi -e 's#^// Progressive enhancements\..*#// Progressive enhancements. The page and its code stay readable without JS.#' website/script.js
printf "%s\n" ".terminal-window + .terminal-window {" "  margin-top: 16px;" "}" >> website/style.css
touch website/.nojekyll
```

The appended rule spaces the two install windows on the Spectro page. Expected: `grep -c accent website/style.css` prints 13 or more and `grep -c orange website/style.css` prints 0. `website/script.js` ends with the `hashchange` listener (Roost lines 71-76).

Create `website/assets/mark.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#6d4ed8"/><path d="M21.5 8.5c-1.2-.8-2.8-1-4.2-.4l-6.8 3.2c-1.6.8-2.6 2.4-2.6 4.2v1c0 1.8 1 3.4 2.6 4.2l6.8 3.2c1.4.6 3 .4 4.2-.4" stroke="#fff" stroke-width="2.5" stroke-linecap="round" fill="none"/></svg>
```

- [ ] **Step 4: Write the page**

Create `website/index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#f0f4fa" />
    <meta
      name="description"
      content="Spectro is a PostgreSQL ORM for Swift, inspired by Ecto: property-wrapper schemas, immutable queries, changesets, and preloading. Part of the Roost family."
    />
    <title>Spectro. — Your data, in plain Swift.</title>
    <link rel="canonical" href="https://roost-framework.github.io/Spectro/" />
    <meta property="og:type" content="website" />
    <meta property="og:title" content="Spectro. — Your data, in plain Swift." />
    <meta
      property="og:description"
      content="A PostgreSQL ORM for Swift, inspired by Ecto."
    />
    <meta property="og:url" content="https://roost-framework.github.io/Spectro/" />
    <meta name="twitter:card" content="summary" />
    <link rel="icon" type="image/svg+xml" href="assets/mark.svg" />
    <link
      rel="preload"
      href="assets/fonts/manrope.ttf"
      as="font"
      type="font/ttf"
      crossorigin
    />
    <link rel="stylesheet" href="style.css" />
    <script src="script.js" defer></script>
  </head>
  <body>
    <a class="skip-link" href="#main">Skip to content</a>
    <header class="site-header wrap">
      <a class="brand" href="./" aria-label="Spectro home"
        ><img src="assets/mark.svg" width="42" height="42" alt="" /><span
          >spectro<span class="accent">.</span></span
        ></a
      >
      <nav aria-label="Main navigation">
        <a href="#features">Features</a>
        <a href="#example">Example</a>
        <a href="#install">Install</a>
        <a class="nav-github" href="https://github.com/roost-framework/Spectro"
          >GitHub <span aria-hidden="true">↗</span></a
        >
      </nav>
    </header>
    <main id="main">
      <section class="hero wrap" aria-labelledby="hero-title">
        <div class="hero-copy">
          <a class="development" href="#family"
            ><span class="status-dot" aria-hidden="true"></span> Part of the
            Roost family <span aria-hidden="true">↓</span></a
          >
          <h1 id="hero-title">
            Your data,<br />in plain Swift<span class="accent">.</span>
          </h1>
          <p class="hero-description">A PostgreSQL ORM that feels like Swift.</p>
          <p class="hero-detail">
            Inspired by Ecto. Property-wrapper schemas, queries you can reuse,
            and changesets that check input before it reaches your database.
          </p>
          <div class="hero-actions">
            <a class="button" href="#install"
              >Get started <span aria-hidden="true">↓</span></a
            >
            <a class="text-link" href="https://github.com/roost-framework/Spectro"
              >Explore the source <span aria-hidden="true">↗</span></a
            >
          </div>
          <p class="hero-note">Spectro 2.1 · Swift 6 · PostgreSQL</p>
        </div>
        <div class="hello-window code-window">
          <div class="window-bar">
            <span
              ><span class="file-dot" aria-hidden="true"></span> Users.swift</span
            ><button
              class="copy-button"
              data-copy="hero-code"
              hidden
              aria-label="Copy the Spectro schema and query"
            >
              Copy <span aria-hidden="true">↗</span>
            </button>
          </div>
          <pre
            tabindex="0"
            aria-label="A Spectro schema and query"
          ><code id="hero-code"><span class="syn-key">import</span> Spectro

<span class="syn-attribute">@Schema</span>(<span class="syn-string">"users"</span>)
<span class="syn-key">struct</span> <span class="syn-type">User</span> {
    <span class="syn-attribute">@ID</span> <span class="syn-key">var</span> id: <span class="syn-type">UUID</span>
    <span class="syn-attribute">@Column</span> <span class="syn-key">var</span> name: <span class="syn-type">String</span>
    <span class="syn-attribute">@Column</span> <span class="syn-key">var</span> email: <span class="syn-type">String</span>
}

<span class="syn-key">let</span> users = <span class="syn-key">try await</span> db.<span class="syn-call">repository</span>()
    .<span class="syn-call">query</span>(<span class="syn-type">User</span>.<span class="syn-key">self</span>)
    .<span class="syn-call">where</span> { $0.email.<span class="syn-call">endsWith</span>(<span class="syn-string">"@acme.io"</span>) }
    .<span class="syn-call">orderBy</span>({ $0.name }, .asc)
    .<span class="syn-call">all</span>()</code></pre>
          <div class="response-line">
            <span>ORDER BY name ASC</span><span class="response-status">3 rows</span>
          </div>
          <div class="hello-result">
            <img src="assets/mark.svg" width="42" height="42" alt="" /><span
              >Ada, Grace, Linus<span class="accent">.</span></span
            >
          </div>
          <p class="window-caption">Typed rows, in the order you asked for.</p>
        </div>
      </section>
      <section id="family" class="stack-strip wrap" aria-label="The Roost family">
        <p class="stack-intro">
          Part of Roost.<br /><strong>One Swift stack.</strong>
        </p>
        <a href="https://roost-framework.github.io/swift-roost/"
          ><span class="stack-name"
            >Roost <span aria-hidden="true">↗</span></span
          ><span class="stack-detail"
            >The web framework <span class="version">2.0</span></span
          ></a
        >
        <a href="https://roost-framework.github.io/Nexus/"
          ><span class="stack-name"
            >Nexus <span aria-hidden="true">↗</span></span
          ><span class="stack-detail"
            >HTTP &amp; routing <span class="version">2.0</span></span
          ></a
        >
        <a href="https://roost-framework.github.io/ESW/"
          ><span class="stack-name">ESW <span aria-hidden="true">↗</span></span
          ><span class="stack-detail"
            >HTML, compiled to Swift <span class="version">1.5</span></span
          ></a
        >
      </section>
      <section
        id="features"
        class="framework-section wrap section-space"
        aria-labelledby="features-title"
      >
        <div class="section-heading">
          <p class="eyebrow">WHAT YOU GET</p>
          <h2 id="features-title">
            Typed from table<br />to result<span class="accent">.</span>
          </h2>
        </div>
        <div class="framework-content">
          <div class="principles">
            <article>
              <h3>Schemas from one macro.</h3>
              <p>
                @Schema generates initializers, row mapping, and Encodable
                conformance at compile time from plain property-wrapper structs.
              </p>
            </article>
            <article>
              <h3>Queries are values.</h3>
              <p>
                Every where, join, and orderBy returns a new query, so you can
                branch one and reuse it.
              </p>
            </article>
          </div>
          <div class="principles">
            <article>
              <h3>Changesets check the door.</h3>
              <p>
                Cast only the fields you permit, validate them, and insert or
                update inside a transaction with clear errors.
              </p>
            </article>
            <article>
              <h3>Preloading without N+1.</h3>
              <p>
                Batch-load HasMany, HasOne, BelongsTo, and ManyToMany with one
                extra query per relationship, not one per row.
              </p>
            </article>
          </div>
        </div>
      </section>
      <section
        id="example"
        class="workflow-section section-space"
        aria-labelledby="example-title"
      >
        <div class="wrap">
          <div class="section-heading heading-row">
            <div>
              <p class="eyebrow">A CLOSER LOOK</p>
              <h2 id="example-title">
                Model, query,<br />commit<span class="accent">.</span>
              </h2>
            </div>
            <p>Three short files. The whole idea.</p>
          </div>
          <div class="code-tour">
            <div class="tour-tabs" aria-label="Explore Spectro code">
              <a class="tour-tab" href="#schema-panel" data-panel="schema-panel"
                ><span>01</span> The schema</a
              >
              <a class="tour-tab" href="#query-panel" data-panel="query-panel"
                ><span>02</span> The query</a
              >
              <a
                class="tour-tab"
                href="#transaction-panel"
                data-panel="transaction-panel"
                ><span>03</span> The transaction</a
              >
            </div>
            <section id="schema-panel" class="tour-panel">
              <div class="tour-explanation">
                <h3>Columns you can see.</h3>
                <p>
                  Property wrappers name every column and relationship. The
                  struct is the schema; there is no second file to keep in step.
                </p>
                <span class="source-label">Models.swift</span>
              </div>
              <div class="tour-code">
                <button
                  class="copy-button light-copy"
                  data-copy="schema-code"
                  hidden
                  aria-label="Copy schema example"
                >
                  Copy
                </button>
                <pre tabindex="0"><code id="schema-code">@Schema(<span class="light-string">"users"</span>)
<span class="light-key">struct</span> User {
    @ID <span class="light-key">var</span> id: UUID
    @Column <span class="light-key">var</span> name: String
    @Column <span class="light-key">var</span> email: String
    @Timestamp <span class="light-key">var</span> createdAt: Date
    @HasMany <span class="light-key">var</span> posts: [Post]
}

@Schema(<span class="light-string">"posts"</span>)
<span class="light-key">struct</span> Post {
    @ID <span class="light-key">var</span> id: UUID
    @Column <span class="light-key">var</span> title: String
    @Column <span class="light-key">var</span> views: Int
    @ForeignKey <span class="light-key">var</span> userId: UUID
    @BelongsTo <span class="light-key">var</span> user: User?
    @Timestamp <span class="light-key">var</span> createdAt: Date
}</code></pre>
              </div>
            </section>
            <section id="query-panel" class="tour-panel">
              <div class="tour-explanation">
                <h3>Queries are values.</h3>
                <p>
                  Build a query once, then page it, sum it, or preload its
                  relationships. Preloading costs one query per relationship,
                  not one per row.
                </p>
                <span class="source-label">Queries.swift</span>
              </div>
              <div class="tour-code">
                <button
                  class="copy-button light-copy"
                  data-copy="query-code"
                  hidden
                  aria-label="Copy query example"
                >
                  Copy
                </button>
                <pre tabindex="0"><code id="query-code"><span class="light-key">let</span> db = <span class="light-key">try</span> Spectro(username: <span class="light-string">"postgres"</span>, password: <span class="light-string">"postgres"</span>, database: <span class="light-string">"app"</span>)
<span class="light-key">let</span> repo = db.repository()

<span class="light-key">let</span> popular = repo.query(Post.<span class="light-key">self</span>)
    .where { $0.views &gt;= 1_000 &amp;&amp; $0.title.iContains(<span class="light-string">"swift"</span>) }

<span class="light-key">let</span> page = <span class="light-key">try await</span> popular
    .orderBy({ $0.createdAt }, .desc)
    .page(size: 20, page: 1)
<span class="light-key">let</span> totalViews = <span class="light-key">try await</span> popular.sum { $0.views }

<span class="light-key">let</span> writers = <span class="light-key">try await</span> repo.query(User.<span class="light-key">self</span>)
    .orderBy({ $0.name }, .asc)
    .preload(\.$posts)
    .limit(10)
    .all()</code></pre>
              </div>
            </section>
            <section id="transaction-panel" class="tour-panel">
              <div class="tour-explanation">
                <h3>All or nothing.</h3>
                <p>
                  The changeset keeps only permitted fields, so "admin" is
                  dropped. When the blank rename fails, the transaction rolls
                  back and Ada is never committed.
                </p>
                <span class="source-label">Signup.swift</span>
              </div>
              <div class="tour-code">
                <button
                  class="copy-button light-copy"
                  data-copy="transaction-code"
                  hidden
                  aria-label="Copy transaction example"
                >
                  Copy
                </button>
                <pre tabindex="0"><code id="transaction-code"><span class="light-key">let</span> signup = Changeset&lt;User&gt;.cast(<span class="light-key">nil</span>,
    params: [<span class="light-string">"name"</span>: <span class="light-string">"Ada"</span>, <span class="light-string">"email"</span>: <span class="light-string">"ada@acme.io"</span>, <span class="light-string">"admin"</span>: <span class="light-key">true</span>],
    permitted: [<span class="light-string">"name"</span>, <span class="light-string">"email"</span>])
    .validateRequired([<span class="light-string">"name"</span>, <span class="light-string">"email"</span>])
    .validateFormat(<span class="light-string">"email"</span>, pattern: <span class="light-string">#"^.+@.+\..+$"#</span>)

<span class="light-key">try await</span> db.transaction { tx <span class="light-key">in</span>
    <span class="light-key">let</span> ada = <span class="light-key">try await</span> tx.insert(signup)
    <span class="light-key">let</span> rename = Changeset.cast(ada, params: [<span class="light-string">"name"</span>: <span class="light-string">""</span>], permitted: [<span class="light-string">"name"</span>])
        .validateRequired([<span class="light-string">"name"</span>])
    _ = <span class="light-key">try await</span> tx.update(rename)
}</code></pre>
              </div>
            </section>
          </div>
        </div>
      </section>
      <section
        id="install"
        class="wrap section-space"
        aria-labelledby="install-title"
      >
        <div class="section-heading">
          <p class="eyebrow">INSTALL</p>
          <h2 id="install-title">
            Add it to<br />your package<span class="accent">.</span>
          </h2>
        </div>
        <div class="workflow-grid">
          <div class="workflow-copy">
            <h3>Two lines in Package.swift.</h3>
            <p>
              Add the package, depend on SpectroKit, then import Spectro in your
              code. The spectro command runs migrations; install it with Mint.
            </p>
            <p>Swift 6.0+ · macOS 13+ or Linux · PostgreSQL</p>
            <a class="text-link" href="https://github.com/roost-framework/Spectro#readme"
              >Read the guide <span aria-hidden="true">↗</span></a
            >
          </div>
          <div>
            <div class="code-window terminal-window">
              <div class="window-bar">
                <span
                  ><span class="file-dot" aria-hidden="true"></span>
                  Package.swift</span
                ><button
                  class="copy-button"
                  data-copy="install-code"
                  hidden
                  aria-label="Copy package dependency"
                >
                  Copy <span aria-hidden="true">↗</span>
                </button>
              </div>
              <pre
                tabindex="0"
                aria-label="Spectro package dependency"
              ><code id="install-code">.<span class="syn-call">package</span>(url: <span class="syn-string">"https://github.com/roost-framework/Spectro.git"</span>, from: <span class="syn-string">"2.1.0"</span>)

<span class="syn-comment">// in your target's dependencies</span>
.<span class="syn-call">product</span>(name: <span class="syn-string">"SpectroKit"</span>, package: <span class="syn-string">"Spectro"</span>)</code></pre>
            </div>
            <div class="code-window terminal-window">
              <div class="window-bar">
                <span
                  ><span class="file-dot" aria-hidden="true"></span>
                  Terminal</span
                ><button
                  class="copy-button"
                  data-copy="cli-code"
                  hidden
                  aria-label="Copy Mint install command"
                >
                  Copy <span aria-hidden="true">↗</span>
                </button>
              </div>
              <pre
                tabindex="0"
                aria-label="Install the spectro command"
              ><code id="cli-code">mint install roost-framework/Spectro@2.1.0</code></pre>
            </div>
          </div>
        </div>
      </section>
      <section class="closing wrap" aria-label="Explore Spectro on GitHub">
        <p>Keep your data<br />close to your code<span class="accent">.</span></p>
        <a class="button" href="https://github.com/roost-framework/Spectro"
          >Explore Spectro on GitHub <span aria-hidden="true">↗</span></a
        >
      </section>
    </main>
    <footer class="site-footer wrap">
      <a class="brand" href="./" aria-label="Spectro home"
        ><span>spectro<span class="accent">.</span></span></a
      >
      <p>Typed queries. Written in Swift.</p>
      <div>
        <a href="https://github.com/roost-framework/Spectro">GitHub ↗</a
        ><a href="https://roost-framework.github.io/swift-roost/">Roost ↗</a
        ><a href="#install">Install</a><a href="#main">Back to top ↑</a>
      </div>
    </footer>
    <p
      id="site-announcement"
      class="sr-only"
      role="status"
      aria-live="polite"
    ></p>
  </body>
</html>
```

- [ ] **Step 5: Write the 404, robots, sitemap, and site README**

Create `website/404.html` from Roost's: `cp ~/Documents/swift-projects/Peregrine/website/404.html website/404.html`, then apply:

```bash
perl -0pi -e 's/Page not found — Roost\./Page not found — Spectro./; s/#de5033/#6d4ed8/; s#<p>ROOST\. / 404</p>#<p>SPECTRO. / 404</p>#; s#<h1>This page flew<br />the nest<span>\.</span></h1>#<h1>No rows<br />found<span>.</span></h1>#; s#That address doesn’t lead to a page\. The framework, examples, and\s+project status are all on the home page\.#That address doesn’t lead to a page. Everything about Spectro is on\n        the home page.#; s#<a href="/swift-roost/">Back to Roost →</a>#<a href="/Spectro/">Back to Spectro →</a>#' website/404.html
grep -nE "Spectro|6d4ed8|No rows" website/404.html
```

Expected: five matching lines (title, colour, heading, paragraph, link), and `grep -ci roost website/404.html` prints 0.

Create `website/robots.txt`:

```
User-agent: *
Allow: /
Sitemap: https://roost-framework.github.io/Spectro/sitemap.xml
```

Create `website/sitemap.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://roost-framework.github.io/Spectro/</loc></url></urlset>
```

Create `website/README.md`:

````markdown
# Spectro website

The public site at **https://roost-framework.github.io/Spectro/**. Plain HTML
and CSS with a small progressive-enhancement script; no build step.

Preview locally:

```sh
python3 -m http.server --directory website 8000
```

Check before pushing:

```sh
node --check website/script.js
python3 website/check.py
```

Pushing changes under `website/` to `main` deploys the site through
`.github/workflows/pages.yml`.

- The look follows the Roost site (`roost-framework/swift-roost`, `website/`).
  Shared tokens and components are copied, not linked; keep them in step by hand.
- Keep version numbers in the hero note, family strip, and install snippets
  aligned with releases.
- Code samples must compile against the latest release tag.
````

- [ ] **Step 6: Prune the stylesheet until the checker passes**

Run: `python3 website/check.py`
Expected first: FAIL, listing `style.css: unused class .<name>` for Roost-only classes (for example `.project-tree`, `.demo-browser`, `.reading-list`, `.status-grid`, `.playground-invitation`, `.dialog-top`, `.api-note`, `.nav-playground`).

For each reported class, delete every rule block whose selector list only targets unused classes, including blocks inside `@media` queries; when a selector list mixes used and unused selectors, delete only the unused selectors; for `.site-header nav a:not(.nav-github):not(.nav-playground)` delete only `:not(.nav-playground)`. Remove `@media` blocks left empty. Re-run until it prints `Site check passed`. Do not change any remaining declaration.

- [ ] **Step 7: Verify the code samples against the release tag**

```bash
cd ~/Documents/swift-projects/Spectro
for p in 'macro Schema' 'struct ID' 'struct Column' 'struct Timestamp' 'struct ForeignKey' 'struct HasMany' 'struct BelongsTo' 'func repository' 'func transaction' 'func query' 'func orderBy' 'func page\(size' 'func sum' 'func preload' 'func limit' 'func all\(' 'func endsWith' 'func iContains' 'func cast' 'func validateRequired' 'func validateFormat' 'func insert' 'func update'; do
  git grep -q -E "$p" 2.1.0 -- Sources && echo "ok      $p" || echo "MISSING $p"
done
```

Expected: every line starts with `ok`.

- [ ] **Step 8: Static checks**

```bash
node --check website/script.js
python3 website/check.py
grep -n 'class="tour-panel"' website/index.html | grep -c hidden
```

Expected: no output from `node`, `Site check passed…`, and `0` (no tour panel is hidden without JavaScript).

- [ ] **Step 9: Visual and accessibility check**

Start a server in the background: `python3 -m http.server --directory website 8731`.
With the Chrome DevTools MCP tools:
1. `new_page` `http://localhost:8731/`, `resize_page` 1280×900, `take_screenshot` (full page). Compare against the Roost site: same header, hero, strip, and tour rhythm; violet accents.
2. `resize_page` 390×844, `take_screenshot`, then `evaluate_script` `() => document.documentElement.scrollWidth <= window.innerWidth`. Expected: `true`.
3. `navigate_page` `http://localhost:8731/#query-panel`, `evaluate_script` `() => document.querySelector('[data-panel="query-panel"]').getAttribute('aria-selected')`. Expected: `"true"`.
4. `press_key` `Tab`, `evaluate_script` `() => document.activeElement.className`. Expected: `"skip-link"`. Focus the first tour tab with `evaluate_script` `() => document.querySelector('.tour-tab').focus()`, `press_key` `ArrowRight`, then check `document.activeElement.dataset.panel`. Expected: `"query-panel"`.
5. `lighthouse_audit` (accessibility category) on `http://localhost:8731/`. Expected: no failed contrast, name, or label audits; score 95 or higher.

Fix anything that fails, re-run Steps 8 and 9, then stop the server.

- [ ] **Step 10: Add the Pages workflow**

Create `.github/workflows/pages.yml`:

```yaml
name: Website

on:
  push:
    branches: [main]
    paths:
      - "website/**"
      - ".github/workflows/pages.yml"
  pull_request:
    paths:
      - "website/**"
      - ".github/workflows/pages.yml"
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: pages-${{ github.ref }}
  cancel-in-progress: false

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Check JavaScript, links, and styles
        run: |
          node --check website/script.js
          python3 website/check.py

  deploy:
    if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'
    needs: check
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pages: write
      id-token: write
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v6
      - uses: actions/configure-pages@v5
      - name: Prepare static files
        run: |
          mkdir -p _site
          cp website/index.html website/404.html website/style.css website/script.js website/robots.txt website/sitemap.xml website/.nojekyll _site/
          cp -R website/assets _site/assets
      - uses: actions/upload-pages-artifact@v4
        with:
          path: _site
      - name: Deploy website
        id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 11: Enable Pages, commit, push, and verify the deployment**

```bash
cd ~/Documents/swift-projects/Spectro
gh api -X POST repos/roost-framework/Spectro/pages -f build_type=workflow --jq .html_url
git add website .github/workflows/pages.yml
git commit -m "docs: add the Spectro website in the Roost style"
git push origin main
gh run list -R roost-framework/Spectro --workflow pages.yml --limit 1
```

Watch the run (`gh run watch <id> -R roost-framework/Spectro --exit-status`). Then:

```bash
for u in https://roost-framework.github.io/Spectro/ https://roost-framework.github.io/Spectro/style.css https://roost-framework.github.io/Spectro/assets/fonts/manrope.ttf https://roost-framework.github.io/Spectro/missing https://roost-framework.github.io/spectro/; do printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' $u)" $u; done
```

Expected: `200` for the first three, `404` for `/missing` (served by the custom 404), and the lowercase result recorded for the final report.

- [ ] **Step 12: User review checkpoint**

Send the user the live URL and the two screenshots, and wait for approval or changes before starting Task 2. Apply requested changes in this repository first, re-run Steps 6-11, and carry the same changes into Tasks 2 and 3.

---

### Task 2: Nexus website

**Files (all in `~/Documents/swift-projects/Nexus`):**
- Create: `website/check.py`, `website/index.html`, `website/404.html`, `website/style.css`, `website/script.js`, `website/robots.txt`, `website/sitemap.xml`, `website/.nojekyll`, `website/README.md`, `website/assets/mark.svg`, `website/assets/fonts/*`, `.github/workflows/pages.yml`

**Interfaces:**
- Consumes: from Task 1, `Spectro/website/{check.py,style.css,script.js,404.html,README.md,assets/fonts/}` and `Spectro/.github/workflows/pages.yml`, after any changes from the Task 1 review.
- Produces: the live Nexus site at `https://roost-framework.github.io/Nexus/`.

- [ ] **Step 1: Copy the checker and confirm it fails**

```bash
cd ~/Documents/swift-projects/Nexus
S=~/Documents/swift-projects/Spectro
mkdir -p website/assets/fonts .github/workflows
cp $S/website/check.py website/check.py
perl -pi -e 's#PAGES_ROOT = "/Spectro/"#PAGES_ROOT = "/Nexus/"#' website/check.py
python3 website/check.py
```

Expected: exit 1 with `missing index.html`.

- [ ] **Step 2: Copy shared files and set the Nexus accent**

```bash
cd ~/Documents/swift-projects/Nexus
S=~/Documents/swift-projects/Spectro
cp $S/website/assets/fonts/* website/assets/fonts/
cp $S/website/script.js website/script.js
cp $S/.github/workflows/pages.yml .github/workflows/pages.yml
cp $S/website/style.css website/style.css
perl -pi -e 's/--accent: #6d4ed8;/--accent: #0e7c7b;/; s/#6d4ed833/#0e7c7b33/' website/style.css
cp $S/website/404.html website/404.html
perl -pi -e 's/Spectro\./Nexus./g; s/#6d4ed8/#0e7c7b/; s#SPECTRO\. / 404#NEXUS. / 404#; s#No rows<br />found#No route<br />matched#; s#Everything about Spectro#Everything about Nexus#; s#href="/Spectro/">Back to Spectro#href="/Nexus/">Back to Nexus#' website/404.html
touch website/.nojekyll
grep -ci spectro website/404.html website/style.css website/script.js
```

Expected: the final grep prints `0` for every file.

Create `website/assets/mark.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#0e7c7b"/><path d="M8 22 L16 8 L24 22" stroke="#fff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/><line x1="11" y1="17" x2="21" y2="17" stroke="#fff" stroke-width="2" stroke-linecap="round"/></svg>
```

- [ ] **Step 3: Write the page**

Create `website/index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#f0f4fa" />
    <meta
      name="description"
      content="Nexus is a composable HTTP middleware pipeline for Swift, inspired by Elixir's Plug: value-type connections, routing, built-in plugs, and tests without a server. Part of the Roost family."
    />
    <title>Nexus. — One connection. Many small steps.</title>
    <link rel="canonical" href="https://roost-framework.github.io/Nexus/" />
    <meta property="og:type" content="website" />
    <meta property="og:title" content="Nexus. — One connection. Many small steps." />
    <meta
      property="og:description"
      content="Composable HTTP middleware for Swift, inspired by Elixir's Plug."
    />
    <meta property="og:url" content="https://roost-framework.github.io/Nexus/" />
    <meta name="twitter:card" content="summary" />
    <link rel="icon" type="image/svg+xml" href="assets/mark.svg" />
    <link
      rel="preload"
      href="assets/fonts/manrope.ttf"
      as="font"
      type="font/ttf"
      crossorigin
    />
    <link rel="stylesheet" href="style.css" />
    <script src="script.js" defer></script>
  </head>
  <body>
    <a class="skip-link" href="#main">Skip to content</a>
    <header class="site-header wrap">
      <a class="brand" href="./" aria-label="Nexus home"
        ><img src="assets/mark.svg" width="42" height="42" alt="" /><span
          >nexus<span class="accent">.</span></span
        ></a
      >
      <nav aria-label="Main navigation">
        <a href="#features">Features</a>
        <a href="#example">Example</a>
        <a href="#install">Install</a>
        <a class="nav-github" href="https://github.com/roost-framework/Nexus"
          >GitHub <span aria-hidden="true">↗</span></a
        >
      </nav>
    </header>
    <main id="main">
      <section class="hero wrap" aria-labelledby="hero-title">
        <div class="hero-copy">
          <a class="development" href="#family"
            ><span class="status-dot" aria-hidden="true"></span> Part of the
            Roost family <span aria-hidden="true">↓</span></a
          >
          <h1 id="hero-title">
            One connection.<br />Many small steps<span class="accent">.</span>
          </h1>
          <p class="hero-description">Composable HTTP middleware for Swift.</p>
          <p class="hero-detail">
            Inspired by Elixir's Plug. Each step takes a connection and returns
            a new one, so a request reads from top to bottom.
          </p>
          <div class="hero-actions">
            <a class="button" href="#install"
              >Get started <span aria-hidden="true">↓</span></a
            >
            <a class="text-link" href="https://github.com/roost-framework/Nexus"
              >Explore the source <span aria-hidden="true">↗</span></a
            >
          </div>
          <p class="hero-note">Nexus 2.0 · Swift 6 · Hummingbird or Vapor</p>
        </div>
        <div class="hello-window code-window">
          <div class="window-bar">
            <span
              ><span class="file-dot" aria-hidden="true"></span> App.swift</span
            ><button
              class="copy-button"
              data-copy="hero-code"
              hidden
              aria-label="Copy the Nexus pipeline example"
            >
              Copy <span aria-hidden="true">↗</span>
            </button>
          </div>
          <pre
            tabindex="0"
            aria-label="A Nexus pipeline with a router"
          ><code id="hero-code"><span class="syn-key">import</span> Nexus
<span class="syn-key">import</span> NexusRouter

<span class="syn-key">let</span> router = <span class="syn-type">Router</span> {
    <span class="syn-call">GET</span>(<span class="syn-string">"/hello/:name"</span>) { conn <span class="syn-key">in</span>
        conn.<span class="syn-call">text</span>(<span class="syn-string">"Hello, \(conn.params["name"] ?? "world")!"</span>)
    }
}

<span class="syn-key">let</span> app = <span class="syn-call">buildPipeline</span> {
    <span class="syn-call">requestId</span>()
    <span class="syn-call">requestLogger</span>()
    router
}</code></pre>
          <div class="response-line">
            <span>GET /hello/nexus</span><span class="response-status">200 OK</span>
          </div>
          <div class="hello-result">
            <img src="assets/mark.svg" width="42" height="42" alt="" /><span
              >Hello, nexus!</span
            >
          </div>
          <p class="window-caption">Three plugs. One response.</p>
        </div>
      </section>
      <section id="family" class="stack-strip wrap" aria-label="The Roost family">
        <p class="stack-intro">
          Part of Roost.<br /><strong>One Swift stack.</strong>
        </p>
        <a href="https://roost-framework.github.io/swift-roost/"
          ><span class="stack-name"
            >Roost <span aria-hidden="true">↗</span></span
          ><span class="stack-detail"
            >The web framework <span class="version">2.0</span></span
          ></a
        >
        <a href="https://roost-framework.github.io/Spectro/"
          ><span class="stack-name"
            >Spectro <span aria-hidden="true">↗</span></span
          ><span class="stack-detail"
            >PostgreSQL &amp; migrations <span class="version">2.1</span></span
          ></a
        >
        <a href="https://roost-framework.github.io/ESW/"
          ><span class="stack-name">ESW <span aria-hidden="true">↗</span></span
          ><span class="stack-detail"
            >HTML, compiled to Swift <span class="version">1.5</span></span
          ></a
        >
      </section>
      <section
        id="features"
        class="framework-section wrap section-space"
        aria-labelledby="features-title"
      >
        <div class="section-heading">
          <p class="eyebrow">WHAT YOU GET</p>
          <h2 id="features-title">
            Small pieces.<br />Clear flow<span class="accent">.</span>
          </h2>
        </div>
        <div class="framework-content">
          <div class="principles">
            <article>
              <h3>Plugs on value types.</h3>
              <p>
                A plug is a function from connection to connection. Every step
                returns a new copy and never mutates shared state.
              </p>
            </article>
            <article>
              <h3>Compose, route, halt.</h3>
              <p>
                Chain plugs into pipelines, route with path parameters and
                scopes, and halt early instead of throwing HTTP errors.
              </p>
            </article>
          </div>
          <div class="principles">
            <article>
              <h3>Batteries included.</h3>
              <p>
                Signed sessions, CSRF protection, static files, CORS, Basic
                auth, compression, request IDs, and logging ship as plugs.
              </p>
            </article>
            <article>
              <h3>Test without a server.</h3>
              <p>
                NexusTest builds a connection in one line, so you call any plug
                or pipeline directly and check the result.
              </p>
            </article>
          </div>
        </div>
      </section>
      <section
        id="example"
        class="workflow-section section-space"
        aria-labelledby="example-title"
      >
        <div class="wrap">
          <div class="section-heading heading-row">
            <div>
              <p class="eyebrow">A CLOSER LOOK</p>
              <h2 id="example-title">
                Plug, route,<br />test<span class="accent">.</span>
              </h2>
            </div>
            <p>Three short files. The whole idea.</p>
          </div>
          <div class="code-tour">
            <div class="tour-tabs" aria-label="Explore Nexus code">
              <a class="tour-tab" href="#plug-panel" data-panel="plug-panel"
                ><span>01</span> The plug</a
              >
              <a class="tour-tab" href="#router-panel" data-panel="router-panel"
                ><span>02</span> The router</a
              >
              <a class="tour-tab" href="#test-panel" data-panel="test-panel"
                ><span>03</span> The test</a
              >
            </div>
            <section id="plug-panel" class="tour-panel">
              <div class="tour-explanation">
                <h3>Halt, don't throw.</h3>
                <p>
                  Without a token, the plug answers 401 and halts, so later
                  plugs are skipped. With one, it assigns the user to a new
                  copy of the connection.
                </p>
                <span class="source-label">RequireToken.swift</span>
              </div>
              <div class="tour-code">
                <button
                  class="copy-button light-copy"
                  data-copy="plug-code"
                  hidden
                  aria-label="Copy plug example"
                >
                  Copy
                </button>
                <pre tabindex="0"><code id="plug-code"><span class="light-key">import</span> Nexus

<span class="light-key">enum</span> CurrentUser: AssignKey { <span class="light-key">typealias</span> Value = String }

<span class="light-key">let</span> requireToken: Plug = { conn <span class="light-key">in</span>
    <span class="light-key">guard let</span> auth = conn.getReqHeader(<span class="light-string">"Authorization"</span>),
          auth.hasPrefix(<span class="light-string">"Bearer "</span>) <span class="light-key">else</span> {
        <span class="light-key">return</span> conn.respond(status: .unauthorized, body: .string(<span class="light-string">"Missing token"</span>))
    }
    <span class="light-key">let</span> token = String(auth.dropFirst(<span class="light-string">"Bearer "</span>.count))
    <span class="light-key">return</span> conn.assign(CurrentUser.<span class="light-key">self</span>, value: token)
}</code></pre>
              </div>
            </section>
            <section id="router-panel" class="tour-panel">
              <div class="tour-explanation">
                <h3>Routes are plugs too.</h3>
                <p>
                  Path parameters arrive on the connection. Scopes run their own
                  plugs first, so the admin routes sit behind Basic auth.
                </p>
                <span class="source-label">API.swift</span>
              </div>
              <div class="tour-code">
                <button
                  class="copy-button light-copy"
                  data-copy="router-code"
                  hidden
                  aria-label="Copy router example"
                >
                  Copy
                </button>
                <pre tabindex="0"><code id="router-code"><span class="light-key">import</span> Nexus
<span class="light-key">import</span> NexusRouter

<span class="light-key">struct</span> User: Encodable, Sendable { <span class="light-key">let</span> id: String; <span class="light-key">let</span> name: String }

<span class="light-key">let</span> api = Router {
    GET(<span class="light-string">"/users/:id"</span>) { conn <span class="light-key">in</span>
        <span class="light-key">let</span> id = conn.params[<span class="light-string">"id"</span>] ?? <span class="light-string">""</span>
        <span class="light-key">return try</span> conn.json(value: User(id: id, name: <span class="light-string">"Ada"</span>))
    }
    scope(<span class="light-string">"/admin"</span>, through: [basicAuth { _, pass <span class="light-key">in</span> pass == <span class="light-string">"s3cret"</span> }]) {
        GET(<span class="light-string">"/stats"</span>) { conn <span class="light-key">in try</span> conn.json(value: [<span class="light-string">"users"</span>: 1]) }
    }
}

<span class="light-key">let</span> app = pipeline([requestId(), requestLogger(), api.asPlug()])</code></pre>
              </div>
            </section>
            <section id="test-panel" class="tour-panel">
              <div class="tour-explanation">
                <h3>No port required.</h3>
                <p>
                  NexusTest builds the connection. Call the plug or the whole
                  app as a function and check what comes back.
                </p>
                <span class="source-label">AppTests.swift</span>
              </div>
              <div class="tour-code">
                <button
                  class="copy-button light-copy"
                  data-copy="test-code"
                  hidden
                  aria-label="Copy test example"
                >
                  Copy
                </button>
                <pre tabindex="0"><code id="test-code"><span class="light-key">import</span> Testing
<span class="light-key">import</span> Nexus
<span class="light-key">import</span> NexusTest

@Test <span class="light-key">func</span> rejectsMissingToken() <span class="light-key">async throws</span> {
    <span class="light-key">let</span> result = <span class="light-key">try await</span> requireToken(TestConnection.build(path: <span class="light-string">"/me"</span>))
    #expect(result.isHalted)
    #expect(result.response.status == .unauthorized)
}

@Test <span class="light-key">func</span> greetsByName() <span class="light-key">async throws</span> {
    <span class="light-key">let</span> result = <span class="light-key">try await</span> app(TestConnection.build(path: <span class="light-string">"/hello/nexus"</span>))
    #expect(result.response.status == .ok)
    #expect(result.requestId != <span class="light-key">nil</span>)
}</code></pre>
              </div>
            </section>
          </div>
        </div>
      </section>
      <section
        id="install"
        class="wrap section-space"
        aria-labelledby="install-title"
      >
        <div class="section-heading">
          <p class="eyebrow">INSTALL</p>
          <h2 id="install-title">
            Add it to<br />your package<span class="accent">.</span>
          </h2>
        </div>
        <div class="workflow-grid">
          <div class="workflow-copy">
            <h3>Pick the pieces you need.</h3>
            <p>
              Nexus is the core. Add NexusRouter for routing, NexusHummingbird
              or NexusVapor to serve requests, and NexusTest to your test
              target.
            </p>
            <p>Swift 6.0+ · macOS 14+, iOS 17+ or Linux</p>
            <a class="text-link" href="https://github.com/roost-framework/Nexus#readme"
              >Read the guide <span aria-hidden="true">↗</span></a
            >
          </div>
          <div class="code-window terminal-window">
            <div class="window-bar">
              <span
                ><span class="file-dot" aria-hidden="true"></span>
                Package.swift</span
              ><button
                class="copy-button"
                data-copy="install-code"
                hidden
                aria-label="Copy package dependency"
              >
                Copy <span aria-hidden="true">↗</span>
              </button>
            </div>
            <pre
              tabindex="0"
              aria-label="Nexus package dependency"
            ><code id="install-code">.<span class="syn-call">package</span>(url: <span class="syn-string">"https://github.com/roost-framework/Nexus.git"</span>, from: <span class="syn-string">"2.0.0"</span>)

<span class="syn-comment">// in your target's dependencies</span>
.<span class="syn-call">product</span>(name: <span class="syn-string">"Nexus"</span>, package: <span class="syn-string">"Nexus"</span>),
.<span class="syn-call">product</span>(name: <span class="syn-string">"NexusRouter"</span>, package: <span class="syn-string">"Nexus"</span>),
.<span class="syn-call">product</span>(name: <span class="syn-string">"NexusHummingbird"</span>, package: <span class="syn-string">"Nexus"</span>)

<span class="syn-comment">// in your test target</span>
.<span class="syn-call">product</span>(name: <span class="syn-string">"NexusTest"</span>, package: <span class="syn-string">"Nexus"</span>)</code></pre>
          </div>
        </div>
      </section>
      <section class="closing wrap" aria-label="Explore Nexus on GitHub">
        <p>Build a pipeline<br />you can read<span class="accent">.</span></p>
        <a class="button" href="https://github.com/roost-framework/Nexus"
          >Explore Nexus on GitHub <span aria-hidden="true">↗</span></a
        >
      </section>
    </main>
    <footer class="site-footer wrap">
      <a class="brand" href="./" aria-label="Nexus home"
        ><span>nexus<span class="accent">.</span></span></a
      >
      <p>Plug-shaped. Written in Swift.</p>
      <div>
        <a href="https://github.com/roost-framework/Nexus">GitHub ↗</a
        ><a href="https://roost-framework.github.io/swift-roost/">Roost ↗</a
        ><a href="#install">Install</a><a href="#main">Back to top ↑</a>
      </div>
    </footer>
    <p
      id="site-announcement"
      class="sr-only"
      role="status"
      aria-live="polite"
    ></p>
  </body>
</html>
```

- [ ] **Step 4: Write robots, sitemap, and site README**

Create `website/robots.txt`:

```
User-agent: *
Allow: /
Sitemap: https://roost-framework.github.io/Nexus/sitemap.xml
```

Create `website/sitemap.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://roost-framework.github.io/Nexus/</loc></url></urlset>
```

Create `website/README.md` by copying Spectro's and renaming:

```bash
S=~/Documents/swift-projects/Spectro
cp $S/website/README.md website/README.md
perl -pi -e 's/Spectro website/Nexus website/; s#github\.io/Spectro/#github.io/Nexus/#' website/README.md
grep -c Spectro website/README.md
```

Expected: `0`.

- [ ] **Step 5: Run the checker and prune**

Run: `python3 website/check.py`
Expected: `Site check passed…`. If it reports unused classes (the Nexus page uses one install window instead of Spectro's two, which needs no extra class), delete those rules as in Task 1 Step 6 and re-run.

- [ ] **Step 6: Verify the code samples against the release tag**

```bash
for p in 'struct Router' 'func GET' 'func scope' 'func buildPipeline' 'func pipeline' 'func requestId' 'func requestLogger' 'func basicAuth' 'func text\(' 'func json\(' 'func respond\(' 'func getReqHeader' 'func assign' 'protocol AssignKey' 'Plug =' 'func asPlug' 'var params' 'var requestId' 'var isHalted' 'struct TestConnection' 'static func build'; do
  git grep -q -E "$p" 2.0.0 -- Sources && echo "ok      $p" || echo "MISSING $p"
done
```

Expected: every line starts with `ok`.

- [ ] **Step 7: Static checks**

```bash
node --check website/script.js
python3 website/check.py
grep -n 'class="tour-panel"' website/index.html | grep -c hidden
```

Expected: no `node` output, `Site check passed…`, `0`.

- [ ] **Step 8: Visual and accessibility check**

Serve with `python3 -m http.server --directory website 8732` and repeat Task 1 Step 9 against `http://localhost:8732/`, with the deep link `#router-panel` (expected selected) and ArrowRight from the first tab landing on `router-panel`. Expected: no horizontal scroll at 390 px, Lighthouse accessibility 95 or higher with no contrast or label failures, teal accents.

- [ ] **Step 9: Enable Pages, commit, push, and verify**

```bash
cd ~/Documents/swift-projects/Nexus
gh api -X POST repos/roost-framework/Nexus/pages -f build_type=workflow --jq .html_url
git add website .github/workflows/pages.yml
git commit -m "docs: add the Nexus website in the Roost style"
git push origin main
```

Watch the `pages.yml` run to success, then:

```bash
for u in https://roost-framework.github.io/Nexus/ https://roost-framework.github.io/Nexus/style.css https://roost-framework.github.io/Nexus/assets/fonts/manrope.ttf https://roost-framework.github.io/Nexus/missing https://roost-framework.github.io/nexus/; do printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' $u)" $u; done
```

Expected: `200`, `200`, `200`, `404`, and the lowercase result recorded.

---

### Task 3: ESW website

**Files (all in `~/Documents/swift-projects/esw`):**
- Create: `website/check.py`, `website/index.html`, `website/404.html`, `website/style.css`, `website/script.js`, `website/robots.txt`, `website/sitemap.xml`, `website/.nojekyll`, `website/README.md`, `website/assets/mark.svg`, `website/assets/fonts/*`, `.github/workflows/pages.yml`

**Interfaces:**
- Consumes: the same Spectro files as Task 2.
- Produces: the live ESW site at `https://roost-framework.github.io/ESW/`.

- [ ] **Step 1: Copy the checker and confirm it fails**

```bash
cd ~/Documents/swift-projects/esw
S=~/Documents/swift-projects/Spectro
mkdir -p website/assets/fonts .github/workflows
cp $S/website/check.py website/check.py
perl -pi -e 's#PAGES_ROOT = "/Spectro/"#PAGES_ROOT = "/ESW/"#' website/check.py
python3 website/check.py
```

Expected: exit 1 with `missing index.html`.

- [ ] **Step 2: Copy shared files and set the ESW accent**

```bash
cd ~/Documents/swift-projects/esw
S=~/Documents/swift-projects/Spectro
cp $S/website/assets/fonts/* website/assets/fonts/
cp $S/website/script.js website/script.js
cp $S/.github/workflows/pages.yml .github/workflows/pages.yml
cp $S/website/style.css website/style.css
perl -pi -e 's/--accent: #6d4ed8;/--accent: #2f7d32;/; s/#6d4ed833/#2f7d3233/' website/style.css
cp $S/website/404.html website/404.html
perl -pi -e 's/Spectro\./ESW./g; s/#6d4ed8/#2f7d32/; s#SPECTRO\. / 404#ESW. / 404#; s#No rows<br />found#Nothing to<br />render#; s#Everything about Spectro#Everything about ESW#; s#href="/Spectro/">Back to Spectro#href="/ESW/">Back to ESW#' website/404.html
touch website/.nojekyll
grep -ci spectro website/404.html website/style.css website/script.js
```

Expected: `0` for every file.

Create `website/assets/mark.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#2f7d32"/><path d="M13 10 L7 16 L13 22" stroke="#fff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/><circle cx="19" cy="12" r="2" fill="#fff"/><circle cx="25" cy="20" r="2" fill="#fff"/><line x1="26" y1="10" x2="18" y2="22" stroke="#fff" stroke-width="2" stroke-linecap="round"/></svg>
```

- [ ] **Step 3: Write the page**

Create `website/index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#f0f4fa" />
    <meta
      name="description"
      content="ESW compiles HTML templates into Swift functions at build time: typed parameters, typed components, escaping by default, and live views. Part of the Roost family."
    />
    <title>ESW. — Write HTML. Ship Swift.</title>
    <link rel="canonical" href="https://roost-framework.github.io/ESW/" />
    <meta property="og:type" content="website" />
    <meta property="og:title" content="ESW. — Write HTML. Ship Swift." />
    <meta
      property="og:description"
      content="HTML templates compiled into Swift functions."
    />
    <meta property="og:url" content="https://roost-framework.github.io/ESW/" />
    <meta name="twitter:card" content="summary" />
    <link rel="icon" type="image/svg+xml" href="assets/mark.svg" />
    <link
      rel="preload"
      href="assets/fonts/manrope.ttf"
      as="font"
      type="font/ttf"
      crossorigin
    />
    <link rel="stylesheet" href="style.css" />
    <script src="script.js" defer></script>
  </head>
  <body>
    <a class="skip-link" href="#main">Skip to content</a>
    <header class="site-header wrap">
      <a class="brand" href="./" aria-label="ESW home"
        ><img src="assets/mark.svg" width="42" height="42" alt="" /><span
          >esw<span class="accent">.</span></span
        ></a
      >
      <nav aria-label="Main navigation">
        <a href="#features">Features</a>
        <a href="#example">Example</a>
        <a href="#install">Install</a>
        <a class="nav-github" href="https://github.com/roost-framework/ESW"
          >GitHub <span aria-hidden="true">↗</span></a
        >
      </nav>
    </header>
    <main id="main">
      <section class="hero wrap" aria-labelledby="hero-title">
        <div class="hero-copy">
          <a class="development" href="#family"
            ><span class="status-dot" aria-hidden="true"></span> Part of the
            Roost family <span aria-hidden="true">↓</span></a
          >
          <h1 id="hero-title">
            Write HTML.<br />Ship Swift<span class="accent">.</span>
          </h1>
          <p class="hero-description">Templates compiled into Swift functions.</p>
          <p class="hero-detail">
            Familiar EEx and HEEx syntax, checked by the Swift compiler at build
            time. Typed components, escaping by default, and live views when
            you need them.
          </p>
          <div class="hero-actions">
            <a class="button" href="#install"
              >Get started <span aria-hidden="true">↓</span></a
            >
            <a class="text-link" href="https://github.com/roost-framework/ESW"
              >Explore the source <span aria-hidden="true">↗</span></a
            >
          </div>
          <p class="hero-note">ESW 1.5 · Swift 6.3 · Build plugin</p>
        </div>
        <div class="hello-window code-window">
          <div class="window-bar">
            <span
              ><span class="file-dot" aria-hidden="true"></span> users.esw</span
            ><button
              class="copy-button"
              data-copy="hero-code"
              hidden
              aria-label="Copy the ESW template"
            >
              Copy <span aria-hidden="true">↗</span>
            </button>
          </div>
          <pre
            tabindex="0"
            aria-label="An ESW template"
          ><code id="hero-code"><span class="syn-attribute">&lt;%!</span>
<span class="syn-key">var</span> users: [<span class="syn-type">User</span>]
<span class="syn-attribute">%&gt;</span>
<span class="syn-attribute">&lt;%</span> <span class="syn-key">for</span> user <span class="syn-key">in</span> users { <span class="syn-attribute">%&gt;</span><span class="syn-type">&lt;li&gt;</span><span class="syn-attribute">&lt;%=</span> user.name <span class="syn-attribute">%&gt;</span><span class="syn-type">&lt;/li&gt;</span><span class="syn-attribute">&lt;%</span> } <span class="syn-attribute">%&gt;</span></code></pre>
          <div class="response-line">
            <span>Generated by ESWBuildPlugin · abridged</span><span class="response-status">renderUsers(users:)</span>
          </div>
          <pre
            tabindex="0"
            aria-label="The Swift function ESWBuildPlugin generates, abridged"
          ><code><span class="syn-key">func</span> <span class="syn-call">renderUsers</span>(
    users: [<span class="syn-type">User</span>]
) -&gt; <span class="syn-type">String</span> {
    <span class="syn-key">var</span> _buf = <span class="syn-type">ESWBuffer</span>()
    <span class="syn-key">for</span> user <span class="syn-key">in</span> users {
    _buf.<span class="syn-call">append</span>(<span class="syn-string">#"&lt;li&gt;"#</span>)
    _buf.<span class="syn-call">appendEscaped</span>(user.name)
    _buf.<span class="syn-call">append</span>(<span class="syn-string">#"&lt;/li&gt;"#</span>)
    }
    <span class="syn-key">return</span> _buf.<span class="syn-call">finalize</span>()
}</code></pre>
        </div>
      </section>
      <section id="family" class="stack-strip wrap" aria-label="The Roost family">
        <p class="stack-intro">
          Part of Roost.<br /><strong>One Swift stack.</strong>
        </p>
        <a href="https://roost-framework.github.io/swift-roost/"
          ><span class="stack-name"
            >Roost <span aria-hidden="true">↗</span></span
          ><span class="stack-detail"
            >The web framework <span class="version">2.0</span></span
          ></a
        >
        <a href="https://roost-framework.github.io/Nexus/"
          ><span class="stack-name"
            >Nexus <span aria-hidden="true">↗</span></span
          ><span class="stack-detail"
            >HTTP &amp; routing <span class="version">2.0</span></span
          ></a
        >
        <a href="https://roost-framework.github.io/Spectro/"
          ><span class="stack-name"
            >Spectro <span aria-hidden="true">↗</span></span
          ><span class="stack-detail"
            >PostgreSQL &amp; migrations <span class="version">2.1</span></span
          ></a
        >
      </section>
      <section
        id="features"
        class="framework-section wrap section-space"
        aria-labelledby="features-title"
      >
        <div class="section-heading">
          <p class="eyebrow">WHAT YOU GET</p>
          <h2 id="features-title">
            Templates the<br />compiler checks<span class="accent">.</span>
          </h2>
        </div>
        <div class="framework-content">
          <div class="principles">
            <article>
              <h3>Compiled at build time.</h3>
              <p>
                ESWBuildPlugin turns every .esw and .heex file into a plain
                Swift function. No runtime parsing; template typos fail the
                build.
              </p>
            </article>
            <article>
              <h3>Typed components.</h3>
              <p>
                A component tag compiles to a Swift call, so the compiler checks
                every attribute, slot, and argument type.
              </p>
            </article>
          </div>
          <div class="principles">
            <article>
              <h3>Escaped by default.</h3>
              <p>
                Output is HTML-escaped unless you opt in. Layouts and partials
                are ordinary templates you compose as Swift functions.
              </p>
            </article>
            <article>
              <h3>Live when you need it.</h3>
              <p>
                ESWLive keeps state in Swift on the server. A click runs your
                handler and the browser receives only what changed.
              </p>
            </article>
          </div>
        </div>
      </section>
      <section
        id="example"
        class="workflow-section section-space"
        aria-labelledby="example-title"
      >
        <div class="wrap">
          <div class="section-heading heading-row">
            <div>
              <p class="eyebrow">A CLOSER LOOK</p>
              <h2 id="example-title">
                Template, component,<br />live view<span class="accent">.</span>
              </h2>
            </div>
            <p>Three short files. The whole idea.</p>
          </div>
          <div class="code-tour">
            <div class="tour-tabs" aria-label="Explore ESW code">
              <a class="tour-tab" href="#template-panel" data-panel="template-panel"
                ><span>01</span> The template</a
              >
              <a
                class="tour-tab"
                href="#component-panel"
                data-panel="component-panel"
                ><span>02</span> The component</a
              >
              <a class="tour-tab" href="#live-panel" data-panel="live-panel"
                ><span>03</span> The live view</a
              >
            </div>
            <section id="template-panel" class="tour-panel">
              <div class="tour-explanation">
                <h3>Parameters with types.</h3>
                <p>
                  The opening block declares typed parameters. Expressions are
                  escaped; the double-equals form inserts trusted HTML, such as
                  another template. This file becomes renderPostsIndex(title:
                  posts: isAdmin:).
                </p>
                <span class="source-label">Views/posts/index.esw</span>
              </div>
              <div class="tour-code">
                <button
                  class="copy-button light-copy"
                  data-copy="template-code"
                  hidden
                  aria-label="Copy template example"
                >
                  Copy
                </button>
                <pre tabindex="0"><code id="template-code">&lt;%!
<span class="light-key">var</span> title: String
<span class="light-key">var</span> posts: [Post]
<span class="light-key">var</span> isAdmin: Bool = <span class="light-key">false</span>
%&gt;
&lt;h1&gt;&lt;%= title %&gt;&lt;/h1&gt;
&lt;% <span class="light-key">if</span> isAdmin { %&gt;
  &lt;a href=<span class="light-string">"/posts/new"</span>&gt;New post&lt;/a&gt;
&lt;% } %&gt;
&lt;ul&gt;
&lt;% <span class="light-key">for</span> post <span class="light-key">in</span> posts { %&gt;
  &lt;li&gt;&lt;%== renderPostsCard(post: post) %&gt;&lt;/li&gt;
&lt;% } %&gt;
&lt;/ul&gt;</code></pre>
              </div>
            </section>
            <section id="component-panel" class="tour-panel">
              <div class="tour-explanation">
                <h3>Attributes the compiler checks.</h3>
                <p>
                  Define a component once in Swift. Using it in a template
                  compiles to Card.render(title:footer:content:), with named
                  slots passed as arguments.
                </p>
                <span class="source-label">Card.swift · profile.heex</span>
              </div>
              <div class="tour-code">
                <button
                  class="copy-button light-copy"
                  data-copy="component-code"
                  hidden
                  aria-label="Copy component example"
                >
                  Copy
                </button>
                <pre tabindex="0"><code id="component-code"><span class="light-key">struct</span> Card: ESWComponent {
    <span class="light-key">static func</span> render(title: String, footer: String = <span class="light-string">""</span>, content: String = <span class="light-string">""</span>) -&gt; String {
        #heex(<span class="light-string">"""</span>
        &lt;article class="card"&gt;
          &lt;h2&gt;{title}&lt;/h2&gt;
          {ESWValue.safe(content)}
          &lt;footer&gt;{ESWValue.safe(footer)}&lt;/footer&gt;
        &lt;/article&gt;
        <span class="light-string">"""</span>)
    }
}

&lt;!-- Views/profile.heex --&gt;
&lt;.card title={user.name}&gt;
  &lt;p&gt;{user.bio}&lt;/p&gt;
  &lt;:footer&gt;Member since {user.joinedYear}&lt;/:footer&gt;
&lt;/.card&gt;</code></pre>
              </div>
            </section>
            <section id="live-panel" class="tour-panel">
              <div class="tour-explanation">
                <h3>State stays on the server.</h3>
                <p>
                  Each click runs handleEvent and re-renders, and the browser
                  receives only the values that changed. Serve it through your
                  own HTTP adapter.
                </p>
                <span class="source-label">Counter.swift</span>
              </div>
              <div class="tour-code">
                <button
                  class="copy-button light-copy"
                  data-copy="live-code"
                  hidden
                  aria-label="Copy live view example"
                >
                  Copy
                </button>
                <pre tabindex="0"><code id="live-code"><span class="light-key">import</span> ESWLive

<span class="light-key">struct</span> Counter: LiveView {
    <span class="light-key">func</span> mount(_ context: LiveContext) <span class="light-key">async throws</span> -&gt; Int { 0 }

    <span class="light-key">func</span> handleEvent(_ event: LiveEvent, state: Int) <span class="light-key">async throws</span> -&gt; Int {
        <span class="light-key">guard</span> event.name == <span class="light-string">"increment"</span> <span class="light-key">else</span> { <span class="light-key">throw</span> LiveError.invalidEvent }
        <span class="light-key">return</span> state + 1
    }

    <span class="light-key">func</span> render(_ count: Int) -&gt; ESWLiveRender {
        #live(<span class="light-string">"""</span>
        &lt;output id="count"&gt;{count}&lt;/output&gt;
        &lt;button type="button" esw-click="increment"&gt;+1&lt;/button&gt;
        <span class="light-string">"""</span>)
    }
}</code></pre>
              </div>
            </section>
          </div>
        </div>
      </section>
      <section
        id="install"
        class="wrap section-space"
        aria-labelledby="install-title"
      >
        <div class="section-heading">
          <p class="eyebrow">INSTALL</p>
          <h2 id="install-title">
            Add it to<br />your package<span class="accent">.</span>
          </h2>
        </div>
        <div class="workflow-grid">
          <div class="workflow-copy">
            <h3>One plugin does the compiling.</h3>
            <p>
              Depend on ESW, and ESWLive for live views. Attach ESWBuildPlugin
              and put .esw or .heex files in your target; each becomes a render
              function at build time.
            </p>
            <p>Swift 6.3+ · macOS 14+</p>
            <a class="text-link" href="https://github.com/roost-framework/ESW#readme"
              >Read the guide <span aria-hidden="true">↗</span></a
            >
          </div>
          <div class="code-window terminal-window">
            <div class="window-bar">
              <span
                ><span class="file-dot" aria-hidden="true"></span>
                Package.swift</span
              ><button
                class="copy-button"
                data-copy="install-code"
                hidden
                aria-label="Copy package configuration"
              >
                Copy <span aria-hidden="true">↗</span>
              </button>
            </div>
            <pre
              tabindex="0"
              aria-label="ESW package configuration"
            ><code id="install-code">.<span class="syn-call">package</span>(url: <span class="syn-string">"https://github.com/roost-framework/ESW.git"</span>, from: <span class="syn-string">"1.5.0"</span>)

.<span class="syn-call">target</span>(
    name: <span class="syn-string">"App"</span>,
    dependencies: [
        .<span class="syn-call">product</span>(name: <span class="syn-string">"ESW"</span>, package: <span class="syn-string">"esw"</span>),
        .<span class="syn-call">product</span>(name: <span class="syn-string">"ESWLive"</span>, package: <span class="syn-string">"esw"</span>)
    ],
    plugins: [.<span class="syn-call">plugin</span>(name: <span class="syn-string">"ESWBuildPlugin"</span>, package: <span class="syn-string">"esw"</span>)]
)</code></pre>
          </div>
        </div>
      </section>
      <section class="closing wrap" aria-label="Explore ESW on GitHub">
        <p>Your markup,<br />type-checked<span class="accent">.</span></p>
        <a class="button" href="https://github.com/roost-framework/ESW"
          >Explore ESW on GitHub <span aria-hidden="true">↗</span></a
        >
      </section>
    </main>
    <footer class="site-footer wrap">
      <a class="brand" href="./" aria-label="ESW home"
        ><span>esw<span class="accent">.</span></span></a
      >
      <p>Compiled HTML. Written in Swift.</p>
      <div>
        <a href="https://github.com/roost-framework/ESW">GitHub ↗</a
        ><a href="https://roost-framework.github.io/swift-roost/">Roost ↗</a
        ><a href="#install">Install</a><a href="#main">Back to top ↑</a>
      </div>
    </footer>
    <p
      id="site-announcement"
      class="sr-only"
      role="status"
      aria-live="polite"
    ></p>
  </body>
</html>
```

- [ ] **Step 4: Write robots, sitemap, and site README**

Create `website/robots.txt`:

```
User-agent: *
Allow: /
Sitemap: https://roost-framework.github.io/ESW/sitemap.xml
```

Create `website/sitemap.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://roost-framework.github.io/ESW/</loc></url></urlset>
```

```bash
S=~/Documents/swift-projects/Spectro
cp $S/website/README.md website/README.md
perl -pi -e 's/Spectro website/ESW website/; s#github\.io/Spectro/#github.io/ESW/#' website/README.md
grep -c Spectro website/README.md
```

Expected: `0`.

- [ ] **Step 5: Run the checker and prune**

Run: `python3 website/check.py`
Expected: FAIL with `style.css: unused class .hello-result` and `.window-caption` (the ESW hero has no result row). Delete those rules, including their `@media` overrides, as in Task 1 Step 6, and re-run until `Site check passed…`.

- [ ] **Step 6: Verify the samples against the release tag**

```bash
for p in 'struct ESWBuffer' 'func appendEscaped' 'func finalize' 'protocol ESWComponent' 'macro heex' 'macro live' 'protocol LiveView' 'LiveContext' 'LiveEvent' 'invalidEvent' 'ESWLiveRender' 'safe'; do
  git grep -q -E "$p" 1.5.0 -- Sources && echo "ok      $p" || echo "MISSING $p"
done
git grep -q 'esw-click' 1.5.0 -- Sources/ESWLive/Resources && echo "ok      esw-click" || echo "MISSING esw-click"
```

Expected: every line starts with `ok`.

- [ ] **Step 7: Static checks**

```bash
node --check website/script.js
python3 website/check.py
grep -n 'class="tour-panel"' website/index.html | grep -c hidden
```

Expected: no `node` output, `Site check passed…`, `0`.

- [ ] **Step 8: Visual and accessibility check**

Serve with `python3 -m http.server --directory website 8733` and repeat Task 1 Step 9 against `http://localhost:8733/`, with deep link `#component-panel` and ArrowRight from the first tab landing on `component-panel`. Expected: no horizontal scroll at 390 px (the long `render(...)` line scrolls inside its panel), Lighthouse accessibility 95 or higher, green accents.

- [ ] **Step 9: Enable Pages, commit, push, and verify**

```bash
cd ~/Documents/swift-projects/esw
gh api -X POST repos/roost-framework/ESW/pages -f build_type=workflow --jq .html_url
git add website .github/workflows/pages.yml
git commit -m "docs: add the ESW website in the Roost style"
git push origin main
```

Watch the `pages.yml` run to success, then:

```bash
for u in https://roost-framework.github.io/ESW/ https://roost-framework.github.io/ESW/style.css https://roost-framework.github.io/ESW/assets/fonts/manrope.ttf https://roost-framework.github.io/ESW/missing https://roost-framework.github.io/esw/; do printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' $u)" $u; done
```

Expected: `200`, `200`, `200`, `404`, and the lowercase result recorded.

---

### Task 4: Roost site links

**Files:**
- Modify: `~/Documents/swift-projects/Peregrine/website/index.html` (the `<section class="stack-strip wrap"` block)

**Interfaces:**
- Consumes: live URLs from Tasks 1-3.
- Produces: Roost's stack strip pointing at the library sites.

- [ ] **Step 1: Point the strip at the sites**

```bash
cd ~/Documents/swift-projects/Peregrine
perl -0pi -e 's#<a href="https://github.com/roost-framework/Nexus"\n#<a href="https://roost-framework.github.io/Nexus/"\n#; s#<a href="https://github.com/roost-framework/Spectro"\n#<a href="https://roost-framework.github.io/Spectro/"\n#; s#<a href="https://github.com/roost-framework/ESW"\n#<a href="https://roost-framework.github.io/ESW/"\n#; s#PostgreSQL &amp; migrations <span class="version">2\.0</span>#PostgreSQL &amp; migrations <span class="version">2.1</span>#; s#HTML, compiled to Swift</span>#HTML, compiled to Swift <span class="version">1.5</span></span>#' website/index.html
git diff --stat website/index.html
grep -n 'roost-framework.github.io/\(Nexus\|Spectro\|ESW\)/' website/index.html
```

Expected: one file changed, three matching lines in the strip.

- [ ] **Step 2: Check and commit**

```bash
node --check website/script.js
python3 website/check.py
git add website/index.html
git commit -m "docs: link the Roost site to the library websites"
git push origin main
```

Expected: `Site check passed…`. Watch the `Roost website` workflow to success and confirm the three strip links return 200 with `curl`.

---

### Task 5: Retire the old site repositories

**Files:**
- Replace: `~/Documents/swift-projects/spectro-website/index.html`; delete its `styles.css`, `script.js`, `favicon.svg`
- Replace: `~/Documents/swift-projects/nexus-website/index.html`; delete its `styles.css`, `script.js`, `favicon.svg`

**Interfaces:**
- Consumes: live URLs from Tasks 1-2.
- Produces: redirects at `/spectro-website/` and `/nexus.github.io/`, then archived repositories.

- [ ] **Step 1: Write the Spectro redirect**

In `~/Documents/swift-projects/spectro-website`, run `git rm -q styles.css script.js favicon.svg` and overwrite `index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="robots" content="noindex" />
    <title>Spectro has moved</title>
    <link rel="canonical" href="https://roost-framework.github.io/Spectro/" />
    <meta http-equiv="refresh" content="0; url=https://roost-framework.github.io/Spectro/" />
  </head>
  <body>
    <p>
      Spectro’s website has moved to
      <a href="https://roost-framework.github.io/Spectro/">roost-framework.github.io/Spectro</a>.
    </p>
  </body>
</html>
```

- [ ] **Step 2: Write the Nexus redirect**

In `~/Documents/swift-projects/nexus-website`, run `git rm -q styles.css script.js favicon.svg` and overwrite `index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="robots" content="noindex" />
    <title>Nexus has moved</title>
    <link rel="canonical" href="https://roost-framework.github.io/Nexus/" />
    <meta http-equiv="refresh" content="0; url=https://roost-framework.github.io/Nexus/" />
  </head>
  <body>
    <p>
      Nexus’s website has moved to
      <a href="https://roost-framework.github.io/Nexus/">roost-framework.github.io/Nexus</a>.
    </p>
  </body>
</html>
```

- [ ] **Step 3: Commit, push, and verify the redirects**

```bash
for d in spectro-website nexus-website; do
  git -C ~/Documents/swift-projects/$d add index.html
  git -C ~/Documents/swift-projects/$d commit -m "docs: redirect to the new website"
  git -C ~/Documents/swift-projects/$d push origin main
done
```

Watch both `Deploy to GitHub Pages` runs to success, then:

```bash
curl -s https://roost-framework.github.io/spectro-website/ | grep -o 'url=https://roost-framework.github.io/Spectro/'
curl -s https://roost-framework.github.io/nexus.github.io/ | grep -o 'url=https://roost-framework.github.io/Nexus/'
```

Expected: each prints its `url=…` line.

- [ ] **Step 4: Archive both repositories**

```bash
gh repo archive roost-framework/spectro-website --yes
gh repo archive roost-framework/nexus.github.io --yes
gh repo view roost-framework/spectro-website --json isArchived --jq .isArchived
gh repo view roost-framework/nexus.github.io --json isArchived --jq .isArchived
curl -s -o /dev/null -w '%{http_code}\n' https://roost-framework.github.io/spectro-website/
```

Expected: `true`, `true`, and `200` (an archived repository keeps serving its Pages site). If the last check is not `200`, unarchive (`gh repo unarchive … --yes`) and report.

- [ ] **Step 5: Final report**

Report to the user: the three live URLs, the Roost strip change, the redirects and archive state, the lowercase-URL results from Tasks 1-3, and the README problems found while verifying samples (Spectro README samples that don't compile at 2.1.0; Nexus README `package: "swift-nexus"`; ESW README "Generates" block format), offered as follow-ups.
