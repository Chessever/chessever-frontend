# Library chess-database artwork

Generated with the built-in imagegen tool on 2026-10-08. The user requested the original database concept with a stronger indication of stored chess games. The focal object is a complete tiered database cylinder, with a Staunton knight and a small checker fragment integrated into its front. The approved My Prep grayscale palette and quiet diagonal board field provide the shared visual language.

Final asset: [hub_library_icon.webp](../assets/pngs/hub_library_icon.webp), 768 × 256 WebP, quality 90, 4,444 bytes. This replaces the rejected archive-sheet artwork using the original bundled filename. The original database image was a subject reference, and My Prep was a style reference. Versioned duplicate assets are removed.

## Framing and design recheck

- Both card formats retain the original 108.sp default height and bottom-left label alignment. The original card layout code is restored. The 3:1 artwork is drawn at 80.sp high, aligned top-right, with the essential database contour fully visible in both widths. Artwork adds no height to the container.
- The complete cylinder, top ellipse, lower rim, knight and checker fragment occupy approximately x=67–85%, y=11–58%. Image pixels fade after y=60% and along the quiet left edge, so the subject remains intact and full-row cards have no hard image seam.
- Captions remain exactly one line without ellipses. The original single-line slot and label baselines are retained; the caption and its arrow scale down together only when needed to fit the available width. The original accessibility height calculation is retained.
- The database cue is the user's explicit direction. Its contained chess symbol describes the subject rather than adding a generic icon tile. Existing app typography, palette, card outlines, interactions and navigation remain. No new badges, fake UI, text baked into the artwork, saturation, glow, cast shadow, noisy overlay or entrance reveal.
- Reviewed the native widget renders at Small and Full row phone widths in both themes. All 22 study-card and paired-art tests pass across widths 160, 173, 358 and 720, normal/doubled text size, and both themes. They assert the original default height, aligned title positions, large artwork frame, complete subject bounds, single-line captions with all words visible, working taps, and registration/loading of both existing asset paths in the app bundle. Scoped analysis of the changed Dart files passes with no issues.
- Per project rules the live app is not launched or driven. On-device check: stop and relaunch the app to refresh the image bundle. In My Space Edit, toggle Library between Small and Full row; confirm its original height and label alignment, complete database and chess knight, and single-line caption in both themes.

## Generation prompt

```text
Use case: stylized-concept.
Asset type: replacement raster artwork for the Library navigation card in the ChessEver mobile app, one wide 3:1 image.
Input images: Image 1 is the old Library database symbol, a semantic reference. Image 2 is the approved My Prep artwork, a style and palette reference. Do not copy either source's cropping.
Primary request: restore the immediately recognizable DATABASE idea from Image 1, refined into a beautiful small chess-game database illustration. The one focal object is a classic database cylinder with THREE clearly readable stacked storage bands and an elliptical top, with one clean Staunton KNIGHT silhouette integrated on its front. The silhouette is the chess-game cue. A tiny restrained 2-by-2 checker fragment may sit behind the knight inside the cylinder face; this is part of the object, not a separate board or icon. It must read instantly as a chess database, rather than a chessboard, sheet collection, tournament or chess analysis.
Style/medium: crisp flat editorial 2D geometry, matte black, charcoal and muted silver, restrained depth from tonal planes only. Match My Prep's quiet illustrated world. Keep the database's recognizable contour, but refine the heavy white stroke of the old source into a balanced muted-silver lip and precise two tier separators. Substantial readable forms, no tiny details.
Composition/framing: critical: 3:1 wide canvas. The app draws this source at 240 by 80 units, aligned top-right in both Small and Full row cards, with the native title below y=60 units. Place the ENTIRE database, all outer rims and the knight within x=65%-94%, y=6%-58% of the source. Prefer database bounds x=71%-92%, y=8%-56%, a compact complete cylinder about 1.2 times wider than tall. The compact card clips only the far left negative space, and the image fades at the bottom after y=60%. Leave breathing room above and right; NO cropped cylinder edge. The bottom 40% is quiet near-black, with no pieces, bands or bright lines. The left 60% is restrained black negative space. The database is the focal object, not a giant zoomed-in symbol.
Backdrop: a very subdued diagonal charcoal chessboard field on the far right may echo My Prep, but remain secondary and dark. No page edges or diagram-sheet stack.
Palette: same neutral near-black #0c0c0e, charcoal #202023, graphite #36363a, muted silver #858589, sparse pale gray #b4b4b7. No new hue or saturated accent; no bright white giant outline.
Constraints: return only the artwork, not a UI mockup. No labels, lettering, numbers, coordinates, watermark, brand mark or outer card border. No archive of chess diagrams, paper sheets, books, trophies, floating icons, folder plus cylinder collage, extra chess pieces, branching arrows, noise, glow, gradients, shadows, beveled 3D object, or photography. The classic tiered database silhouette and the chess knight are the whole message.
```

## Final refinement prompt

```text
Use case: precise-object-edit.
Asset type: final Library background for the ChessEver app, wide 3:1.
Input image: edit target, the supplied grayscale database illustration.
Primary request: KEEP this clear classic database cylinder with the integrated Staunton knight and checker fragment. Make only the composition correction needed for the small navigation card: move the complete cylinder UP and uniformly shrink it about 10%, keeping its proportions. The ENTIRE object, including the top ellipse, bottom rim and knight base, must fit within x=67%-89%, y=5%-57% of the canvas. It currently sits too low. Leave a clear margin above; no silhouette may be clipped. Nothing recognizable or silver may extend below y=57%.
Preserve the cylinder design, clean tier separator, recognizable knight, neutral black/charcoal/silver palette, matte 2D style, subdued diagonal board field, wide 3:1 aspect and quiet black left field. The bottom 40% is dark context only, clear of the native title. Do not enlarge any component independently, distort the knight, or vertically squash the database.
No new objects, paper sheets, books, arrows, labels, text, numbers, watermark, outer border, glow, cast shadow or UI mockup. Return only the corrected artwork.
```
