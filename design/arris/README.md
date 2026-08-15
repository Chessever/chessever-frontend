# Arris

An original 2D Staunton chess set for chessground. © ChessEver LLC.

An *arris* is the edge where two cut faces meet. That edge is the whole idea
here.

All geometry is authored from scratch in `build_arris.py` on a 128 grid.
Nothing is traced, morphed, filtered or recoloured from cburnett, merida,
california, staunty, gioco, maestro or any other set.

## What the cut changes

Arris throws out the modelled shading of a generic Staunton and replaces it
with a single hard bevel: the silhouette is re-stroked twice, displaced up-left
and down-right and clipped to itself, so one constant-width lit arris and one
shaded arris ride every contour, including the insides of the rook's crenels
and the king's cross arms, while the fill behind them stays perfectly flat. It
also swaps the usual applied bead-and-torus collars for chamfers cut straight
into the column, and spends its height on a low base disc and a genuinely
slender stem, so the identifying form on top is the widest thing on the piece.

## Contents

| Path | What |
| --- | --- |
| `svg/` | the 12 source pieces, `viewBox 0 0 128 128` |
| `webp/` | 512 px WebP, lossless |
| `webp/256`, `webp/128` | smaller raster sizes |
| `arris-specimen.png` | the six white pieces on alternating cream/green, plus the same six at 40 px actual size |
| `arris-board.png` | starting position |
| `build_arris.py` | the geometry. Edit here, never the SVGs |
| `export_arris.py` | rasterises WebP and both previews |

## Specification

- **Grid** 128 x 128, centre line `x = 64`, ground line `y = 117`.
- **Foot** base slab face 117 to 109, one chamfer 109 to 103, then a fast
  concave pull-in onto the stem. One step, never two.
- **Height ladder** (top of piece): K 7, Q 13.5, B 16.9, N 18, R 27, P 36.
  Wide enough that the pieces separate by height alone at 40 px.
- **Base half-width**: K 40, Q 39, R 38, N 37, B 35, P 28.
- **Stem half-width**: K 15, Q 14.5, R 16, B 13, P 10.
- **Strokes** silhouette 5.0, interior structure 3.2, arris rim 4.2, rim
  displacement 3.5. All joins and caps round. One weight per role, held across
  all twelve pieces.
- **Palette**

  | | fill | lit arris | shaded arris | contour |
  | --- | --- | --- | --- | --- |
  | white | `#ECEDE7` | `#FCFCF9` | `#CDD1C8` | `#14161A` |
  | black | `#212322` | `#3E423E` | `#0C0D0C` | `#070807` |

  Both values are the same stone, cool and neutral. Interior detail is
  `#14161A` on white and `#494E48` on black; the knight's eye and nostril are
  `#767C74` on black, because on a dark piece a carved eye is a highlight and
  not a hole.

## Interior detail budget

Rook and pawn carry none. King and queen carry one line each, closing the rim
band that the silhouette chamfer opens. Bishop carries the slit. Knight carries
four marks: eye, nostril, mouth, jaw. Nothing else earns its place at 40 px.

## Verification

`build_arris.py` is checked by rendering each piece at 256 px and asserting
that no piece touches the edge of its viewBox, and that every symmetric piece
mirrors about `x = 64` to within rasteriser noise. The knight is the only
piece that is asymmetric by design.

## Using it in chessground

chessground paints pieces as CSS background images, so the SVGs drop straight
in:

```css
.cg-wrap piece.king.white   { background-image: url('svg/wK.svg'); }
.cg-wrap piece.queen.white  { background-image: url('svg/wQ.svg'); }
/* ...and so on for rook, bishop, knight, pawn, both colours */
```

Use the WebP only where a raster is genuinely wanted. The SVGs stay crisp at
every board size and are smaller.
