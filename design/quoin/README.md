# Quoin

An original 2D Staunton chess set for chessground. © ChessEver LLC.

A *quoin* is the wedge a printer drives into a chase to lock a forme of type,
and the dressed cornerstone a mason sets at the angle of a wall. Both meanings
are the brief: this is Staunton treated as a typeface, one new cut, and the
identifying forms are architecture rather than ornament.

All geometry is authored from raw coordinates in `build_quoin.py`. Nothing here
is traced, morphed, filtered or recoloured from cburnett, merida, california,
staunty, gioco, maestro or any other set.

## What the cut changes

Quoin draws every piece as a stack of separately outlined **turnings** (foot,
shaft, collar, head) rather than as one traced contour, so the silhouette
reads as stacked mass and the same chamfered foot and the same collar ring
recur across all six pieces the way stems and terminals recur across a
typeface. Against a generic Staunton it is plumper through the shaft, far
flatter in the fill (one soft cylindrical rake from the upper left, keyed to
each piece's own width, and nothing else: no plate shadow, no bloom, no
gradient in the colour), and it spends its entire detail budget on the
identifying form: three merlons, five coronet prongs, the mitre's slit, the
horse's dish and jaw.

## Contents

| Path | What |
| --- | --- |
| `svg/` | the 12 source pieces, `viewBox 0 0 45 45` |
| `webp/` | **512 px WebP**, transparent |
| `webp/flutter/` | 128 px, plus `2.0x` `3.0x` `4.0x` for a Flutter asset bundle |
| `quoin-specimen.png` | the six white pieces on alternating bone / sage squares |
| `quoin-board.png` | the starting position |
| `quoin-40px.png` | all twelve rendered at 40 px, shown 4x nearest-neighbour |
| `build_quoin.py` | the geometry: edit here, never the SVGs |
| `export_quoin.py` | rasterises the WebP and both previews |
| `preview.py` | working proof sheets, including the 40 px legibility row |

## Specification

- **Grid** `45 × 45`, centre line `x = 22.5`, ground line `y = 39.9`.
- **Height ladder** (top of piece, so lower is taller):
  K `2.9`, Q `4.9`, B `6.1`, N `6.6`, R `9.6`, P `11.2`.
- **Base ladder** (half-width at the ground):
  K `13.0`, N `12.6`, Q `12.4`, R `12.4`, B `10.6`, P `8.8`.
- **Turnings.** Four helpers build everything: `foot` (chamfer, straight wall,
  rounded ground edge, as one element, because a chamfer plus a plinth plus a
  step stacked separately reads as a barcode at 40 px), `shaft` (concave, holds
  its width then kicks out), `collar` (the ring that separates head from
  shaft), `ball` (finial and pearls).
- **Strokes** silhouette `1.35`, dark-body silhouette `1.70`, inverted inner
  structure `1.15`. All joins and caps round; corners are authored crisp and
  softened only by the joins.
- **Light.** One rake from the upper left. Two single-hue alpha falloffs
  clipped to the piece, their endpoints anchored to that piece's own horizontal
  span so a wide king and a narrow pawn turn at the same relative point. The
  middle third of every piece stays at true body tone.
- **Palette**

  | | body | outline | inner structure | detail |
  | --- | --- | --- | --- | --- |
  | white | `#F0F1EE` | `#141A1F` | (the outline itself) | `#141A1F` |
  | black | `#272C2E` | `#0A0D0C` | `#7F8A89` | `#CCD3D2` |

  The dark piece is a green-grey graphite, never pure black and deliberately
  not the stock indigo-slate. Its internal structure inverts to light: the same
  drawing re-struck thin in a pale ink, clipped to the silhouette so only the
  inner half of each contour survives and the outer rim stays dark against the
  board.
- **Board in the previews** bone `#F0E7D3`, sage `#5F7D63`.

## Verified

- Every piece clears the viewBox on all four sides (tightest margin: the king
  at `2.0`).
- Left and right margins are identical on all twelve, and the eleven symmetric
  pieces mirror to an alpha RMSE of `0.0013` (antialias noise). The knight is
  asymmetric by design.
- All six read at 40 px in both colours; see `preview.py`.

## Rebuilding

```bash
python3 build_quoin.py && python3 export_quoin.py
```

`export_quoin.py` needs `rsvg-convert` (librsvg), ImageMagick and `cwebp`.
