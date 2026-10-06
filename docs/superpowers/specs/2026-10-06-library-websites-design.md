# Library websites in the Roost style

Date: 2026-10-06
Status: approved design, pending spec review

## Goal

Give ESW, Spectro, and Nexus each a website that reads as part of the Roost
family while selling the library on its own terms. A visitor who never uses
Roost should understand and adopt Spectro, Nexus, or ESW from its site alone; a
visitor who arrives from Roost should recognise the same family.

Success means:

- Three live single-page sites at `https://roost-framework.github.io/ESW/`,
  `/Spectro/`, and `/Nexus/`, visually consistent with
  `https://roost-framework.github.io/swift-roost/`.
- Every code sample uses APIs that exist in the current release
  (ESW 1.5.0, Spectro 2.1.0, Nexus 2.0.0).
- The Roost site and each library site link to one another.
- The old Spectro and Nexus site URLs lead to the new sites.

## Decisions

| Topic | Decision |
| --- | --- |
| Positioning | Standalone library sites, joined by a shared "Part of Roost" strip. |
| Hosting | A `website/` directory and `pages.yml` workflow in each library repository, mirroring swift-roost. |
| Visual identity | Roost's base (paper, ink, blue, Manrope, IBM Plex Mono, components) with one accent per library. |
| Build approach | Copy Roost's site assets into each repository, prune unused rules, write a new `index.html` per library. No generator. |
| Theme | Light only, matching Roost. |

## Visual system

Shared with Roost, copied verbatim: `--paper #f0f4fa`, `--surface #fff`,
`--ink #21314a`, `--muted #596980`, `--blue #2855b6`, `--line #d6dfec`,
`--code #202f47`, the self-hosted Manrope and IBM Plex Mono fonts with their OFL
licences, spacing, header, buttons, code windows, tabs, stack strip, and footer.

Roost's `--orange` token and `.orange` class become `--accent` and `.accent` in
the library copies. Accent values, chosen to keep each library's former hue
except Nexus, whose orange now belongs to Roost:

| Library | Accent | Contrast on paper | White text on accent |
| --- | --- | --- | --- |
| Spectro | violet `#6d4ed8` | 5.10:1 | 5.63:1 |
| Nexus | teal `#0e7c7b` | 4.54:1 | 5.01:1 |
| ESW | green `#2f7d32` | 4.64:1 | 5.12:1 |

Marks are flat SVGs in the accent colour, redrawn from each former favicon
glyph: Spectro's curve, Nexus's chevron, ESW's `<%`. The same SVG serves as the
header mark and the favicon.

## Page structure

Each site is one `index.html` with these sections, in order.

1. **Header.** Mark, lowercase name with an accent full stop (`spectro.`), and
   navigation: Features, Example, Install, GitHub ↗.
2. **Hero.** Headline in Roost's voice, one-sentence lead, short detail, primary
   action "Get started" (to Install) and text link "Explore the source" (to
   GitHub). A code window shows the library's core idea with its result below:
   - Spectro: a `@Schema` model and a query, with the resulting rows.
   - Nexus: a plug pipeline, with the `200 OK` response line.
   - ESW: a `.esw` template, with the Swift it generates.
3. **Part of Roost strip.** Roost's stack-strip component listing Roost and the
   two sibling libraries, each linking to its site and showing its version.
4. **Features.** Three or four cards drawn from the library README.
   - Spectro: property-wrapper schemas and `@Schema`, immutable queries,
     changesets, relationship preloading.
   - Nexus: value-type `Connection` plugs, composable pipelines and routing,
     sessions/CSRF and other built-in plugs, testing without a server.
   - ESW: compiled templates, typed components, layouts and escaping, live
     rendering.
5. **Example tour.** Roost's tab component with three panels.
   - Spectro: Schema → Query → Transaction.
   - Nexus: Plug → Router → Test.
   - ESW: Template → Components → Live.
6. **Install.** SwiftPM dependency line at the current version; Spectro also
   shows its Mint line for the CLI. Requirements line (Swift 6.3, macOS 14 or
   Linux).
7. **Closing and footer.** Links to documentation and GitHub; footer matching
   Roost's, crediting the Roost family.

Out of scope: a playground, a hosted DocC site, animation beyond what Roost's
`script.js` already provides, dark mode.

## Files per library repository

```
website/
  index.html
  404.html
  style.css        # Roost's stylesheet, pruned, accent token renamed
  script.js        # Roost's script, reduced to copy buttons and tabs
  check.py         # Roost's checker without playground and swift-roost specifics
  robots.txt
  sitemap.xml
  .nojekyll
  README.md        # how to preview and what to keep in sync with releases
  assets/
    mark.svg
    fonts/         # Manrope, IBM Plex Mono, OFL licences
.github/workflows/pages.yml
```

`pages.yml` copies Roost's workflow: on pushes to `main` touching `website/**`,
run `node --check website/script.js` and `python3 website/check.py`, then deploy
`website/` to GitHub Pages. Each repository's Pages source is switched to GitHub
Actions.

## Changes outside the library repositories

- **swift-roost:** the stack strip and any companion links in `website/` point
  to the new library sites instead of GitHub. Website-only change; no release.
- **spectro-website, nexus.github.io:** replace contents with a redirect page
  (`<meta http-equiv="refresh">`, canonical link, and a visible link) to the new
  URL, wait for deployment, then archive both repositories. They are not
  deleted.
- The local `esw-website` draft is left untouched.

## Content accuracy

Code samples come from each library's README and DocC catalogues, then are
checked against the current release sources: every type, macro, function, and
property shown must exist at the release tag. Version strings on the sites match
the latest tags.

## Testing

Per site, before pushing:

- `python3 website/check.py` passes (files, fragments, ids, alt text).
- `node --check website/script.js` passes.
- Symbol check for code samples, as above.
- Local preview via `python3 -m http.server`, screenshots at 1280 px and 390 px
  wide; no horizontal scroll at 390 px.
- Lighthouse accessibility audit with no contrast or labelling failures.

After deployment:

- Each new site URL returns 200 and renders its stylesheet and fonts.
- Old site URLs show the redirect and land on the new site.
- Links in the Roost and library strips resolve.

## Order of work

1. Spectro site, reviewed by the user as the template for the others.
2. Nexus site.
3. ESW site.
4. Roost site links.
5. Redirects in the old site repositories, then archive them.
