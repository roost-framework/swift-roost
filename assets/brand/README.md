# Roost.

[`roost-mark.png`](roost-mark.png) is the primary mark: a peregrine falcon
in a dive, drawn in warm vermilion on a transparent background. The broad swept
wing carries the silhouette at small sizes. The repository README pairs it with
native text so the wordmark follows the reader's light or dark theme.

Use the original PNG, keep its proportions, and retain space around the mark.
It is raster artwork, not an SVG. The color direction is warm vermilion
(`#E45436`); transparency is preserved in the delivered asset.

The wordmark is **Roost.**, with the final dot in warm orange (`#DE5033`). The
reading-list example uses the same dot in its lowercase `roost.` wordmark.
[`orange-dot.svg`](orange-dot.svg) keeps that accent in the GitHub README, which
does not support arbitrary text colors. In code, use `Roost`; in the terminal,
use `roost`. The punctuation belongs to the visual identity.

## Generation record

The falcon artwork is unchanged by the framework rename. The original prompts
below retain the former name as provenance.

Created with the built-in image generation tool. No external source image was
used. The second pass used the first generated mark as its reference.

### Initial prompt

```text
Use case: logo-brand
Asset type: primary logo mark for Peregrine, an open-source Swift web framework. It will appear at 160px in a GitHub README and as a small repository avatar.
Primary request: Design a beautiful, distinctive, exceptionally clean logo of a peregrine falcon in a controlled dive. Create one final emblem only, no presentation board or variations.
Subject: A compact peregrine falcon diving diagonally forward and down, with a clear hooked beak and a confident swept wing. A subtle falcon facial notch in negative space. Distill the bird into three broad, carefully balanced sculptural shapes with generous open negative spaces. A memorable silhouette with the precision of a well-designed typographic ligature; energetic but composed. Bird must read as a falcon, not an eagle badge or generic social-media bird.
Style/medium: premium flat graphic identity, vector-like precision, smooth deliberate curves meeting crisp tapered tips, immaculate edge quality. Mid-century modern identity design made contemporary. Completely flat single color, no rendering effects.
Composition/framing: centered square mark, emblem fills about 75 percent of square canvas, plenty of even transparent margin. Simple enough to be recognized at 32 pixels. No thin lines or fine feather detail.
Color palette: one solid warm vermilion #E45436; open negative space is transparent. This warm color must work on white and near-black surfaces.
Scene/backdrop: genuinely transparent background with alpha, not a white rectangle or a checkerboard painted into the image.
Text: none; no letters, no name, no caption.
Constraints: original design, not the Apple Swift bird or Phoenix framework logo. No gradients, shadows, 3D, texture, outlines, shields, circles, square badges, flames, swoosh lines, mockups, watermarks, or extra decorative objects.
```

### Final refinement prompt

```text
Use case: precise-object-edit
Asset type: final production logo for the Peregrine Swift web framework.
Primary request: Clean up this exact falcon logo into a perfectly flat, crisp brand mark.
Keep the existing falcon silhouette, wing curves, head and beak geometry, diagonal diving direction, composition, scale, and transparent background unchanged. Do not redesign it.
Change only the finish: remove ALL shading, gradients, mottling, grain, glow, faint stray pixels, and textured or ragged edges. Every interior pixel of the mark should be one uniform warm vermilion color, sRGB #E45436, fully opaque; only contour antialiasing may have partial alpha. Empty areas must have genuine alpha transparency. The result should look like pristine solid vector artwork exported to transparent PNG, not a painted illustration. No text, no outline, no shadow, no background rectangle or painted checkerboard.
```
