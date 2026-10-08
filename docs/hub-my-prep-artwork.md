# My Prep background replacement

Generated with the built-in imagegen tool on 2026-10-08. The approved neutral black, charcoal and silver mood is retained. The clipboard and magnifier are replaced by a flat chess preparation motif with one knight, two pawns and a branching route. This is decorative illustration, not a legal position or live analysis.

Final asset: [hub_my_prep_icon.webp](../assets/pngs/hub_my_prep_icon.webp), 768 × 256 WebP, quality 90. It replaces the existing bundled asset. Only My Prep uses top-right alignment; the existing theme opacity and readability ramp are retained.

## Composition and validation

- A compact card shows the right half of the wide source. A long card exposes more of the subdued left field. The essential motif stays above the label area in both crops.
- Reviewed static crop studies at compact and full-row phone widths in both themes, with the existing light-theme opacity and label ramps. These are artwork previews, not app screenshots.
- The refinement removes the raised knight base and moves every piece and route junction into the upper half, clearing the native title.
- Design-law recheck: the approved grayscale palette overrides the default palette rules; the board is the actual subject, not a background grid. No new typeface, icon pack, containers around icons, badges, fake UI, copy baked into the art, shadows, glows, noisy overlays, entrance animations or dead controls are introduced. Existing native labels, spacing, interactions and routes remain the product controls. Essential silhouettes survive both card crops and labels retain the existing contrast ramps.
- Scoped `flutter analyze --no-pub lib/widgets/hub_context_art.dart lib/widgets/hub_illustration.dart` passed with no issues; all five existing `test/hub_paired_hearts_test.dart` widget tests passed, including both themes at normal and doubled text scale. Final compressed-asset previews passed at 824px and 360px preview widths with no browser console errors. The 4,192-byte replacement is smaller than the previous 4,470-byte asset.
- The app is not built, launched or driven. Device check: open My Space, enter Edit, toggle My Prep between Small and Full row, and inspect both themes.

## Generation prompt

```text
Use case: stylized-concept.
Asset type: replacement full-bleed raster background for the My Prep navigation card in the ChessEver mobile app. Generate ONE wide landscape image, 3:1 aspect ratio.
Input image: reference only for the approved neutral-black, charcoal and muted-silver palette and calm graphic simplicity. Replace its clipboard and magnifying glass completely.
Primary request: a refined chess preparation illustration: one clearly drawn, flat, sparse chessboard study fragment with a recognizable two-dimensional Staunton knight and two small pawns, plus a single understated branching move route across a few board squares. The branching route is the visual idea of preparing alternative openings. Make this feel composed and beautiful, with clean substantial graphic shapes and a readable silhouette at tiny card size.
Style/medium: polished flat editorial chess illustration, precise matte cut-paper-like planes with very limited tonal depth. Strictly two-dimensional, no physical board or realistic pieces. The board is a contextual chess diagram, never an app window or a framed interface.
Composition/framing: exceptionally important: the image will fill a 358 by 108 horizontal card and a 173 by 108 compact card. The compact card crops to approximately the RIGHT HALF of the image. Keep the entire essential knight and branching choice motif within the rightmost 40% of the image, centered around 75% across and 34% down. It should remain recognizable inside that right-half crop. Keep the top silhouette safely inside the canvas, with at least 8% headroom. The board can extend and crop tastefully at the right edge, but no essential chess piece or route junction may be cut. Broad subdued charcoal board planes spread through the right half; the LEFT HALF is restrained black negative space. Both formats carry native text at bottom-left: keep the bottom 36% very dark, quiet, with no bright detail there. Visual focus in the upper-right, not a centered symbol.
Lighting/mood: calm, sophisticated, deliberate, understated, same quiet graphic vibe as the reference.
Color palette: ONLY neutral nearly-black #0c0c0e, deep charcoal #202023, graphite #36363a, muted silver-gray #858589 and a few pale gray #b4b4b7 chess highlights. No new hue or saturated accent. Use moderate contrast: enough for 173px card readability without a giant white outline.
Constraints: preserve the approved grayscale mood; replace the poor original subject and composition. One unified composition, not multiple alternatives. No text, letters, numbers, coordinates, logos, watermark, labels, UI controls or outer card border. No clipboard, magnifier, book, trophy, icon tile, silver rounded rectangle, unrelated objects, collage, scattered symbols, full-page grid, glows, gradients, noise, photography, 3D bevels, shadows, ornamental thin lines or tiny fussy details. Native app text is added later.
```

## Final refinement prompt

```text
Use case: style-transfer.
Asset type: final replacement My Prep mobile card background.
Input image: edit target, the supplied wide grayscale chess preparation illustration.
Primary request: keep the palette, board planes, overall mood, wide 3:1 canvas, right-half concentration and left-half negative space. Make ONE targeted composition refinement: compact the entire knight / branching route / two pawns into the UPPER HALF of the image, so no piece, branch or arrowhead goes below 50% canvas height. All live image content must stay comfortably ABOVE the card's native bottom-left title in both compact and long card crops.
Composition: knight centered around x=69%, its top at 12% canvas height and base at 46%; two understated small pawn endpoints toward x=82% and x=91%, their tops at 11% and 32%, their bases at 26% and 48%. A single clean understated fork travels from the knight toward those endpoints, wholly above y=48%. Keep all silhouettes fully visible with breathing room. Keep the board perspective and broad tones, but the lower half stays very subdued near-black with no bright objects.
Style: ALL pieces absolutely flat 2D chess-diagram glyphs, one continuous clean silhouette each. REMOVE the separated rectangular slab, cast shadow and any bevel below the knight. No raised objects or physical rendering. Board and glyphs stay matte and crisply illustrated; reduce the arrows' prominence slightly so knight is the main object.
Invariants: same approved grayscale palette, same wide 3:1 output, same right-half composition. No new hues, text, numbers, coordinates, logos, extra objects, border, UI frame, glow, noise, gradient, photography, or 3D. Do not make a mockup; return only the flat raster background.
```
