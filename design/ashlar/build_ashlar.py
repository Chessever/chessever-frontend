#!/usr/bin/env python3
"""
Ashlar - an original 2D Staunton chess set for chessground.
(c) ChessEver LLC. All geometry authored from scratch on a 128 grid.

Nothing here is traced, morphed, filtered or recoloured from cburnett, merida,
california, staunty, gioco, maestro, plinth or any other set.

THE CUT
  A display-grotesque cut of Staunton. The letterforms are the standard ones;
  what changes is the cut. Waists are plumper and stems shorter than cburnett,
  so each piece carries its mass low and its identifying form owns the top half
  of the square. The light is one rake from the upper left, drawn as a single
  terminator per piece that bows with that piece's own swells and is clipped to
  its contour - two flat tones, no gradient, no airbrush. Every change of
  diameter is a straight chamfer, and all six stand on one three-plane foot
  (top surface, chamfer, wall), so the family reads as one lathe.

GRID
  128 x 128, centre line x = 64, ground line y = 117.
  Foot: body -> top surface at y = 104 -> chamfer 104 to 110 -> wall 110 to 117.

HEIGHT LADDER (top of piece)
  K 6   N 12   Q 21   B 14   R 28   P 40

BASE HALF-WIDTH (ground slab)
  K 42   Q 41   R 40   N 40   B 37   P 31
"""

import math
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent
SVG_DIR = ROOT / "svg"

CX = 64.0
GROUND = 117.0

# ---------------------------------------------------------------- palette ---
# Cool stone, flat. White is two tones. Black is two tones with the LIT plane
# painted rather than the shaded one, so the dark drawing is authored for dark
# instead of being a recolour of the light one.

WHITE = dict(fill="#E8EAEE", plane="#BFC6D1", line="#14171B", detail="#14171B")
BLACK = dict(fill="#262A31", plane="#4A515C", line="#0C0F13", detail="#828B98")

BOARD_LIGHT = "#DFD8C4"
BOARD_DARK = "#56705A"
PAPER = "#191B17"

W_LINE = 5.0       # silhouette
W_DETAIL = 3.0     # interior structure


# ------------------------------------------------------------- primitives ---


def foot(B):
    """The shared Ashlar foot, right half, top to bottom: cove onto the top
    surface, one straight chamfer, then the wall. Only B changes across the
    family - one lathe profile, six diameters."""
    return (f"C {CX + B - 13} 100 {CX + B - 13} 102 {CX + B - 13} 104 "
            f"L {CX + B - 8} 104 L {CX + B} 110 L {CX + B} {GROUND} ")


def foot_left(B):
    """The same foot, left half, bottom to top."""
    return (f"L {CX - B} {GROUND} L {CX - B} 110 L {CX - B + 8} 104 "
            f"L {CX - B + 13} 104 ")


def crescent(cx, cy, r, lit):
    """Sphere shading under the same rake. lit=False paints the lower-right
    shadow crescent (white); lit=True paints the upper-left lit crescent
    (black). The terminator bows into the shadow so the lit face stays
    generous, the way a real sphere reads."""
    a1, a2 = math.radians(-53.0), math.radians(139.0)
    p1 = (cx + r * math.cos(a1), cy + r * math.sin(a1))
    p2 = (cx + r * math.cos(a2), cy + r * math.sin(a2))
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    k = 0.30 * r
    c1 = (p1[0] + dx / 3 + 0.7071 * k, p1[1] + dy / 3 + 0.7071 * k)
    c2 = (p1[0] + 2 * dx / 3 + 0.7071 * k, p1[1] + 2 * dy / 3 + 0.7071 * k)
    f = lambda p: "%.2f %.2f" % p
    if not lit:
        return f"M {f(p1)} A {r} {r} 0 1 1 {f(p2)} C {f(c2)} {f(c1)} {f(p1)} Z"
    return f"M {f(p2)} A {r} {r} 0 0 1 {f(p1)} C {f(c1)} {f(c2)} {f(p2)} Z"


def rake(curve, side):
    """Close an open top-to-bottom terminator into a fillable half-plane.
    side='right' is the shadow for white, side='left' the lit face for black."""
    x0 = curve.split()[1]
    edge = 136 if side == "right" else -8
    return f"M {x0} -8 {curve[curve.index('C'):]} L {edge} 124 L {edge} -8 Z"


# -------------------------------------------------------------- geometry ----
# outline  the single closed silhouette, filled and stroked
# details  interior structure strokes, drawn over the shading
# marks    interior filled shapes (the knight's eye and nostril)
# spheres  (cx, cy, r) laid down first so the body's own stroke seats them
# term     this piece's terminator - the rake of light

KING = dict(
    outline=(
        "M 58 6 L 70 6 L 70 16 L 82 16 L 82 27 L 70 27 L 70 34 "     # cross, R
        "C 78 34 83 31 85 26 "                                       # cup rim R
        "C 88 36 86 46 80 52 "                                       # cup wall
        "L 84 55 L 84 61 L 76 65 "                                   # collar
        "C 80 75 86 85 88 96 "                                       # body
        + foot(42) + foot_left(42) +
        "C 40 96 42 85 48 75 C 49 71 50 68 52 65 "
        "L 44 61 L 44 55 L 48 52 "
        "C 42 46 40 36 43 26 "
        "C 45 31 50 34 58 34 "
        "L 58 27 L 46 27 L 46 16 L 58 16 Z"                          # cross, L
    ),
    details=(
        "M 45 29 C 54 36 74 36 83 29",   # the dish inside the cup
        "M 48 52 L 80 52",               # cup seated on the collar
        "M 44 61 L 84 61",               # collar underside
        "M 22 110 L 106 110",            # foot chamfer
    ),
    marks=(),
    spheres=(),
    term=("M 60 -8 C 69 6 71 20 66 30 C 61 41 59 49 66 57 "
          "C 73 67 79 82 75 96 C 72 106 71 112 72 124"),
)

QUEEN = dict(
    outline=(
        "M 31 43 C 43 30 85 30 97 43 "                               # coronet
        "C 96 50 92 55 87 59 "                                       # flank
        "L 87 62 L 87 68 L 80 72 "                                   # collar
        "C 84 80 88 88 88 96 "
        + foot(41) + foot_left(41) +
        "C 40 96 40 88 44 80 C 46 76 47 74 48 72 "
        "L 41 68 L 41 62 L 41 59 "
        "C 36 55 32 50 31 43 Z"
    ),
    details=(
        "M 41 59 L 87 59",
        "M 41 68 L 87 68",
        "M 23 110 L 105 110",
    ),
    marks=(),
    spheres=((32, 37, 7.5), (47, 28, 7.5), (64, 24, 8.0),
             (81, 28, 7.5), (96, 37, 7.5)),
    term=("M 60 -8 C 68 14 66 28 63 38 C 60 48 60 56 66 62 "
          "C 72 72 76 82 72 96 C 69 106 68 112 69 124"),
)

ROOK = dict(
    outline=(
        "M 31 28 L 45 28 L 45 46 L 57 46 L 57 28 L 71 28 L 71 46 "   # merlons
        "L 83 46 L 83 28 L 97 28 L 97 46 "
        "L 102 46 L 102 54 L 92 59 L 86 63 "                         # cornice
        "C 88 74 89 86 88 96 "                                       # shaft
        + foot(40) + foot_left(40) +
        "C 40 96 39 86 42 74 C 42 70 42 66 42 63 "
        "L 36 59 L 26 54 L 26 46 L 31 46 Z"
    ),
    details=(
        "M 26 46 L 102 46",              # top of the cornice / crenel floor
        "M 26 54 L 102 54",              # underside of the cornice
        "M 24 110 L 104 110",
    ),
    marks=(),
    spheres=(),
    term=("M 60 -8 C 70 8 68 26 64 40 C 60 50 60 58 67 66 "
          "C 74 78 74 86 71 96 C 69 106 68 112 69 124"),
)

BISHOP = dict(
    outline=(
        "M 56 34 C 58 30 70 30 72 34 "                               # apex
        "L 77 42 L 68 47 L 76 53 "                                   # the slit
        "C 82 60 86 67 87 74 "                                       # shoulder
        "L 91 78 L 91 84 L 84 88 "                                   # mitre rim
        "C 85 92 86 98 86 104 "
        "L 93 104 L 101 110 L 101 117 "
        "L 27 117 L 27 110 L 35 104 L 42 104 "
        "C 42 98 43 92 44 88 "
        "L 37 84 L 37 78 L 41 74 "
        "C 42 67 46 58 56 34 Z"
    ),
    details=(
        ("M 70 49 L 56 63", 4.4),        # the slit carried into the mitre
        "M 37 78 L 91 78",               # mitre rim
        "M 27 110 L 101 110",
    ),
    marks=(),
    spheres=((64, 21, 8.0),),
    term=("M 58 -8 C 66 12 61 28 58 42 C 55 54 60 64 64 74 "
          "C 69 86 70 96 68 106 C 67 112 67 116 67 124"),
)

KNIGHT = dict(
    # Four constraints hold this head together.
    #  1. Between the brow and the nose the contour sits BELOW the chord
    #     joining them, so the profile dishes instead of snouting.
    #  2. The muzzle ends on a tall blunt face and never tapers to a point.
    #  3. The ear is a narrow SPIKE; behind it the mane rises to a rounded
    #     HUMP. The contrast of spike against hump is what reads as a horse -
    #     two spikes read as a fin, and no hump at all leaves no notch at all,
    #     because the tangents simply smooth through.
    #  4. Below that hump the mane falls to the base in one convex sweep.
    outline=(
        "M 70 8 "
        "C 67 14 65 21 63 28 "          # the ear's front edge into the forehead
        "C 57 29 51 32 47 35 "          # brow ridge, proud
        "C 40 44 27 50 19 54 "          # the dish, well below the chord
        "L 14 57 "                      # the muzzle's top plane
        "C 11 62 11 72 15 78 "          # blunt nose, tall vertical front face
        "C 18 81 22 83 28 84 "          # rolling under to the lip and chin
        "C 34 86 43 90 49 94 "          # the jaw, long and heavy
        "C 53 97 55 100 54 104 "        # throat into the chest
        "L 38 104 L 24 110 L 24 117 "
        "L 104 117 L 104 110 L 92 104 "
        "C 99 78 97 44 88 25 "          # the mane sweeping up to its crest
        "C 85 28 81 31 77 32 "          # falling into the notch
        "Z"                             # the ear's back edge
    ),
    details=(
        "M 69 15 L 73 27",                          # inside the ear
        "M 16 75 C 21 79 26 81 31 81",              # mouth
        "M 39 54 C 47 62 51 76 48 90",              # cheek into the jaw
        "M 78 34 C 87 50 91 72 87 94",              # mane
        "M 85 56 L 78 58",
        "M 24 110 L 104 110",
    ),
    marks=(
        "M 41 43 C 46 41 51 45 50 49 C 49 53 42 53 41 47 Z",     # eye
        "M 15 69 C 19 69 20 73 17 74 C 14 75 13 69 15 69 Z",     # nostril
    ),
    spheres=(),
    term=("M 72 -8 C 80 14 74 34 64 46 C 56 60 54 76 56 90 "
          "C 58 100 60 104 58 124"),
    extra=("M 13 71 C 17 78 24 83 32 86 C 39 89 45 93 49 100 "
           "C 43 95 37 92 30 90 C 22 87 15 80 13 71 Z"),
)

PAWN = dict(
    outline=(
        "M 51 69 L 77 69 L 81 74 L 81 80 L 75 84 "
        "C 76 92 77 96 78 100 "
        + foot(31) + foot_left(31) +
        "C 50 98 51 92 53 84 "
        "L 47 80 L 47 74 Z"
    ),
    details=(
        "M 47 80 L 81 80",
        "M 33 110 L 95 110",
    ),
    marks=(),
    spheres=((64, 54, 14.0),),
    term=("M 60 -8 C 68 18 68 44 64 62 C 61 76 62 86 67 98 "
          "C 69 106 68 112 69 124"),
)

PIECES = dict(K=KING, Q=QUEEN, R=ROOK, B=BISHOP, N=KNIGHT, P=PAWN)
ORDER = ["K", "Q", "R", "B", "N", "P"]
NAMES = dict(K="King", Q="Queen", R="Rook", B="Bishop", N="Knight", P="Pawn")


# ----------------------------------------------------------------- render ---


def piece_body(code, colour, uid):
    """The piece as a fragment. `uid` keeps clipPath ids unique per document."""
    c = WHITE if colour == "w" else BLACK
    g = PIECES[code]
    lit = colour == "b"
    cid = f"ash-{uid}"

    out = [f'<defs><clipPath id="{cid}"><path d="{g["outline"]}"/></clipPath>']
    for i, (sx, sy, r) in enumerate(g["spheres"]):
        out.append(f'<clipPath id="{cid}-s{i}">'
                   f'<circle cx="{sx}" cy="{sy}" r="{r}"/></clipPath>')
    out.append("</defs>")
    out.append('<g stroke-linejoin="round" stroke-linecap="round">')

    # 1. spheres first, so the body's own contour seats them
    for i, (sx, sy, r) in enumerate(g["spheres"]):
        out.append(f'<circle cx="{sx}" cy="{sy}" r="{r}" fill="{c["fill"]}" '
                   f'stroke="{c["line"]}" stroke-width="{W_LINE}"/>')
        out.append(f'<g clip-path="url(#{cid}-s{i})">'
                   f'<path d="{crescent(sx, sy, r, lit)}" fill="{c["plane"]}"/>'
                   "</g>")

    # 2. flat fill
    out.append(f'<path d="{g["outline"]}" fill="{c["fill"]}"/>')

    # 3. one rake of light, clipped to the piece's own contour
    shade = rake(g["term"], "left" if lit else "right")
    if not lit and g.get("extra"):
        shade += " " + g["extra"]
    out.append(f'<g clip-path="url(#{cid})">'
               f'<path d="{shade}" fill="{c["plane"]}"/></g>')

    # 4. the contour
    out.append(f'<path d="{g["outline"]}" fill="none" '
               f'stroke="{c["line"]}" stroke-width="{W_LINE}"/>')

    # 5. interior structure, clipped so nothing spills past the contour
    out.append(f'<g clip-path="url(#{cid})">')
    for d in g["details"]:
        path, wt = d if isinstance(d, tuple) else (d, W_DETAIL)
        out.append(f'<path d="{path}" fill="none" stroke="{c["detail"]}" '
                   f'stroke-width="{wt}"/>')
    for m in g["marks"]:
        out.append(f'<path d="{m}" fill="{c["detail"]}"/>')
    out.append("</g>")

    out.append("</g>")
    return "".join(out)


def piece_svg(code, colour):
    name = f"{colour}{code}"
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" '
            'width="128" height="128">'
            f"<title>Ashlar {name}</title>"
            "<desc>Ashlar chess set (c) ChessEver LLC. Original geometry, "
            "authored on a 128 grid.</desc>"
            f'{piece_body(code, colour, name)}</svg>')


def write_pieces():
    SVG_DIR.mkdir(parents=True, exist_ok=True)
    for colour in ("w", "b"):
        for code in ORDER:
            (SVG_DIR / f"{colour}{code}.svg").write_text(
                piece_svg(code, colour), encoding="utf-8")
    print(f"wrote 12 svg -> {SVG_DIR}")


# --------------------------------------------------------------- specimen ---

FONT = "Charter, Georgia, Times New Roman, serif"


def specimen():
    """The six white pieces at size on alternating cream/green squares, and the
    same six at 40px so the readability claim is testable, not asserted."""
    cell, pad, small, gap = 132, 36, 40, 22
    w = pad * 2 + cell * 6
    row2 = pad + cell + 54
    h = row2 + small + 58

    s = [f'<svg xmlns="http://www.w3.org/2000/svg" '
         'xmlns:xlink="http://www.w3.org/1999/xlink" '
         f'viewBox="0 0 {w} {h}" width="{w}" height="{h}">',
         f'<rect width="{w}" height="{h}" fill="{PAPER}"/>', "<defs>"]
    for code in ORDER:
        s.append(f'<g id="w{code}">{piece_body(code, "w", "s" + code)}</g>')
    s.append("</defs>")

    for i, code in enumerate(ORDER):
        x = pad + i * cell
        s.append(f'<rect x="{x}" y="{pad}" width="{cell}" height="{cell}" '
                 f'fill="{BOARD_LIGHT if i % 2 == 0 else BOARD_DARK}"/>')
        s.append(f'<use xlink:href="#w{code}" href="#w{code}" '
                 f'transform="translate({x} {pad}) scale({cell / 128:.6f})"/>')

    for i, code in enumerate(ORDER):
        x = pad + i * (small + gap)
        s.append(f'<rect x="{x}" y="{row2}" width="{small}" height="{small}" '
                 f'fill="{BOARD_LIGHT if i % 2 == 0 else BOARD_DARK}"/>')
        s.append(f'<use xlink:href="#w{code}" href="#w{code}" '
                 f'transform="translate({x} {row2}) scale({small / 128:.6f})"/>')

    s.append(f'<text x="{pad + 6 * (small + gap) + 16}" y="{row2 + 26}" '
             f'fill="#A3ABB0" font-family="{FONT}" font-size="15">'
             "40 px, actual size</text>")
    s.append(f'<text x="{pad}" y="{h - 20}" fill="#E8EAEE" '
             f'font-family="{FONT}" font-size="26">Ashlar</text>')
    s.append(f'<text x="{pad + 106}" y="{h - 20}" fill="#9AA29A" '
             f'font-family="{FONT}" font-size="15">'
             "a display-grotesque cut of Staunton   ·   "
             "© ChessEver LLC</text>")
    s.append("</svg>")
    return "".join(s)


# ------------------------------------------------------------------ board ---

START = ["rnbqkbnr", "pppppppp", "........", "........",
         "........", "........", "PPPPPPPP", "RNBQKBNR"]


def board():
    cell, pad = 96, 24
    w = cell * 8 + pad * 2

    s = [f'<svg xmlns="http://www.w3.org/2000/svg" '
         'xmlns:xlink="http://www.w3.org/1999/xlink" '
         f'viewBox="0 0 {w} {w}" width="{w}" height="{w}">',
         f'<rect width="{w}" height="{w}" fill="{PAPER}"/>', "<defs>"]
    for colour in ("w", "b"):
        for code in ORDER:
            s.append(f'<g id="{colour}{code}">'
                     f'{piece_body(code, colour, "b" + colour + code)}</g>')
    s.append("</defs>")

    for r in range(8):
        for f in range(8):
            s.append(f'<rect x="{pad + f * cell}" y="{pad + r * cell}" '
                     f'width="{cell}" height="{cell}" '
                     f'fill="{BOARD_LIGHT if (r + f) % 2 == 0 else BOARD_DARK}"/>')

    for r, row in enumerate(START):
        for f, ch in enumerate(row):
            if ch == ".":
                continue
            ref = ("w" if ch.isupper() else "b") + ch.upper()
            s.append(f'<use xlink:href="#{ref}" href="#{ref}" '
                     f'transform="translate({pad + f * cell} {pad + r * cell}) '
                     f'scale({cell / 128:.6f})"/>')

    s.append("</svg>")
    return "".join(s)


if __name__ == "__main__":
    write_pieces()
    (ROOT / "ashlar-specimen.svg").write_text(specimen(), encoding="utf-8")
    (ROOT / "ashlar-board.svg").write_text(board(), encoding="utf-8")
    print("wrote ashlar-specimen.svg, ashlar-board.svg")
