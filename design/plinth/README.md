# Plinth

An original 2D Staunton chess set for chessground. © ChessEver LLC.

All geometry is authored from scratch in `build_plinth.py` on a 128 grid.
Nothing here is traced, morphed, filtered or recoloured from cburnett, merida,
california, staunty, gioco, maestro or any other set.

## What the cut changes

Plinth replaces the usual airbrushed shading with a **single hard-edged shadow
plane** — one rake of light from the upper left, clipped exactly to each piece's
own contour, plus a flat slab under every real overhang — so the pieces read as
cut stone rather than as rendered plastic. It then puts that mass where it earns
its keep: every piece stands on the **same two-step chamfered plinth**, and the
identifying form (cross, coronet, merlons, mitre, horse) owns the top half of
the square, so the stems stay short and nothing is spent on decoration that
disappears at 40px.

## Contents

| Path | What |
| --- | --- |
| `svg/` | 12 source SVGs, `viewBox 0 0 128 128` |
| `webp/` | 128px WebP (1x) |
| `webp/2.0x` `3.0x` `4.0x` | 256 / 384 / **512** WebP |
| `plinth-specimen.png` | the six white pieces on alternating bone/sage squares |
| `plinth-board.png` | starting position |
| `build_plinth.py` | the geometry — edit here, never the SVGs |
| `export_plinth.py` | rasterises WebP + both previews |

## Specification

- **Grid** `128 × 128`, centre line `x = 64`, ground line `y = 118`.
- **Height ladder** (top of piece): K 5, Q 8.6, N 9, B 11.3, R 14, P 16.4.
- **Base widths** (half-width of the ground slab): R 50, K 49, Q 48, N 48,
  B 45, P 39.
- **Strokes** silhouette `4.6`, internal structure `2.8`, all joins and caps
  round. Corners are authored crisp and softened only by the joins.
- **Palette**

  | | body | shadow plane | outline | structure |
  | --- | --- | --- | --- | --- |
  | white | `#EEF0F2` | `#BDC6CF` | `#13161A` | `#13161A` |
  | black | `#30363D` | `#1A1E23` | `#090B0D` | `#828D9A` |

  The black piece is flat cool graphite, never pure black, and its internal
  structure inverts to light so the same drawing reads on a dark body. The
  knight's eye gets one extra step of lift (`#B4BDC7`) because at 40px it is
  the single feature that says *horse*.
- **Board used in the previews** bone `#E9E3D1`, sage `#77896E`.

## Rebuilding

```bash
python3 build_plinth.py && python3 export_plinth.py
```

`export_plinth.py` needs `rsvg-convert` (librsvg), ImageMagick and `cwebp`.

## Dropping it into chessground

The WebP tree already matches the chessground layout (`wK.webp` … `bP.webp`
at the root, with `2.0x/`, `3.0x/`, `4.0x/` beside it). To ship it:

1. `cp -R design/plinth/webp third_party/chessground/assets/piece_sets/plinth`
2. add `- assets/piece_sets/plinth/` (and the three scale folders) to the
   chessground `pubspec.yaml` asset list
3. add the `plinth` value to the `PieceSet` enum in
   `third_party/chessground/lib/src/piece_set.dart`
