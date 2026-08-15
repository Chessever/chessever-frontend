# Ashlar

An original 2D Staunton chess set for chessground. © ChessEver LLC.

All geometry is authored from scratch in `build_ashlar.py` on a 128 grid.
Nothing here is traced, morphed, filtered or recoloured from cburnett, merida,
california, staunty, gioco, maestro, plinth or any other set.

## What the cut changes

Ashlar keeps the standard Staunton letterforms but cuts them plumper and
shorter-stemmed than cburnett, so every piece carries its mass low and its
identifying form (cross, coronet, merlons, mitre, horse) owns the top half of
the square instead of a decorative stem. And in place of the airbrushed
roundness most sets use, it renders one rake of light from the upper left as a
single terminator per piece that bows with that piece's own swells and is
clipped to its own contour: two flat tones, no gradient, so the modelling still
holds at 40px where a soft shade turns to mud.

## Contents

| Path | What |
| --- | --- |
| `svg/` | 12 source SVGs, `viewBox 0 0 128 128`, self-contained |
| `webp/` | **512px WebP**, lossless |
| `webp/chessground/{1.0x,2.0x,3.0x,4.0x}` | 128 / 256 / 384 / 512 for chessground |
| `ashlar-specimen.png` | the six white pieces on cream/green, plus the same six at 40px |
| `ashlar-board.png` | starting position |
| `build_ashlar.py` | the geometry. Edit here, never the SVGs |
| `export_ashlar.py` | rasterises WebP and both previews |

Rebuild:

```bash
python3 build_ashlar.py && python3 export_ashlar.py
```

## Specification

- **Grid** `128 × 128`, centre line `x = 64`, ground line `y = 117`.
- **Foot** one three-plane profile shared by all six: top surface at `y = 104`,
  chamfer `104 → 110`, wall `110 → 117`, with only the ground half-width
  changing per piece. One lathe, six diameters.
- **Height ladder** (top of piece): K 6, N 8, Q 16, B 13, R 28, P 40.
- **Base half-width**: K 42, Q 41, R 40, N 40, B 37, P 31.
- **Strokes** silhouette `5.0`, interior structure `3.0`, all joins and caps
  round. Interior strokes are clipped to the contour so nothing spills.
- **Palette** two flat tones per colour, no third value, no gradient.

  | | body | plane | outline | interior |
  | --- | --- | --- | --- | --- |
  | white | `#E8EAEE` | `#BFC6D1` shadow | `#14171B` | `#14171B` |
  | black | `#262A31` | `#4A515C` lit | `#0C0F13` | `#828B98` |

  Black is not a recolour of white: white gets its lower-right **shadow** plane
  painted, black gets its upper-left **lit** plane painted, from the same
  terminator, and its interior structure is a light hairline rather than a dark
  one.

## Notes on the drawing

- **King** Latin cross, dished cup, collar band, flared body.
- **Queen** five separated pearls proud of a coronet; same collar, body and foot
  as the king, no cross. The pearls are spaced so the gaps survive 40px.
- **Rook** three merlons with 12-unit crenels over a cornice that genuinely
  overhangs the shaft. Crenels narrower than that close up at 40px.
- **Bishop** ball finial, mitre, and a slit cut as a real notch in the contour
  and carried inward as a groove. A drawn line alone disappears at 40px.
- **Knight** four constraints, all recorded in the source: the brow-to-nose
  contour sits below the chord joining them (dish, not snout); the muzzle ends
  on a tall blunt face; the ear is a narrow spike set against a rounded mane
  hump, never a second spike; and the mane falls to the base in one convex
  sweep.
- **Pawn** ball, collar, taper, foot. Nothing invented.

## Using it in chessground

The SVGs are self-contained (no external refs, no fonts, ids namespaced per
file), so they drop in as-is. For the Flutter side, `webp/chessground/` matches
the density-bucket layout used by the other sets in
`third_party/chessground/assets/piece_sets/`.
