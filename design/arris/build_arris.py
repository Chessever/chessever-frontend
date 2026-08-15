#!/usr/bin/env python3
"""
Arris - an original 2D Staunton chess set for chessground.
(c) ChessEver LLC. All geometry authored from scratch on a 128 grid.

Nothing here is traced, morphed, filtered or recoloured from cburnett, merida,
california, staunty, gioco, maestro or any other set.

THE CUT
  An arris is the edge where two cut faces meet, and this set is built on it.
  Every change of diameter is a straight chamfer cut into the column - no
  applied bead or torus rings anywhere - and the light is not a wash or a
  shadow plane but two constant-width rims: the silhouette re-stroked at
  +d,+d and -d,-d and clipped to itself, so the lit edge lands on every
  upper-left-facing arris and the shaded edge on every lower-right-facing
  one, interior notches (crenels, cross arms, the ear) resolving for free.

GRID
  128 x 128, centre line x = 64, ground line y = 117.
  Base disc 117 -> 109, one chamfer 109 -> 103, fast pull-in to the stem.

HEIGHT LADDER (top of piece)   K 7   Q 12.5   B 15.9   N 18   R 27   P 36
BASE HALF-WIDTH                K 40  Q 39     R 38     N 37   B 35   P 28
STEM HALF-WIDTH                K 15  Q 14.5   R 16     -      B 13   P 10
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent
SVG_DIR = ROOT / "svg"

FONT = "Helvetica Neue, Helvetica, Arial, sans-serif"

# ---------------------------------------------------------------- palette ---
# Cool quarried stone. Not vellum-warm, not Merida-flat, not blue.

WHITE = dict(fill="#ECEDE7", lit="#FCFCF9", shade="#CDD1C8",
             line="#14161A", detail="#14161A", mark="#14161A")
BLACK = dict(fill="#212322", lit="#3E423E", shade="#0C0D0C",
             line="#070807", detail="#494E48", mark="#767C74")

BOARD_LIGHT = "#DFD8C4"
BOARD_DARK = "#56705A"
PAPER = "#17191C"

# One silhouette weight, one detail weight, one rim weight, one arris offset,
# held across all twelve pieces.
W_LINE = 5.0
W_DETAIL = 3.2
W_RIM = 4.2
ARRIS = 3.5

# ------------------------------------------------------------- geometry -----

PAWN = dict(
    outline=(
        "M 36 117 L 36 109 L 44 103 "
        "C 47 100 51 97 53 92 "              # pull-in off the base disc
        "C 54 88 55 82 54 76 "               # stem
        "L 49 72 L 49 68 L 54.5 62.5 "       # chamfered collar into the ball
        "A 14.92 14.92 0 1 1 73.5 62.5 "
        "L 79 68 L 79 72 L 74 76 "
        "C 73 82 74 88 75 92 "
        "C 77 97 81 100 84 103 "
        "L 92 109 L 92 117 Z"
    ),
    details=(), marks=(),
)

ROOK = dict(
    outline=(
        "M 26 117 L 26 109 L 34 103 "
        "C 39 100 44 97 46 92 "
        "C 47 88 48 80 48 72 "               # shaft
        "L 36 60 "                           # one hard chamfer out to the tower
        "L 36 27 "
        "L 49 27 L 49 39 L 57 39 L 57 27 "   # three merlons, two crenels
        "L 71 27 L 71 39 L 79 39 L 79 27 "
        "L 92 27 L 92 60 L 80 72 "
        "C 80 80 81 88 82 92 "
        "C 84 97 89 100 94 103 "
        "L 102 109 L 102 117 Z"
    ),
    details=(), marks=(),
)

BISHOP = dict(
    outline=(
        "M 29 117 L 29 109 L 37 103 "
        "C 41 100 46 97 48 92 "
        "C 49 88 51 82 51 72 "
        "L 44 66 L 44 62 L 48 58 "           # collar: out, face, back in
        "C 39 53 37 44 43 36 "               # mitre swells low, then necks in
        "C 48 32 53 30 59 30 "
        "A 7.5 7.5 0 1 1 69 30 "             # ball finial on a necked stem
        "C 75 30 80 32 85 36 "
        "C 91 44 89 53 80 58 "
        "L 84 62 L 84 66 L 77 72 "
        "C 77 82 79 88 80 92 "
        "C 82 97 87 100 91 103 "
        "L 99 109 L 99 117 Z"
    ),
    details=(("M 49 50 L 62 36", 7.0),),     # the slit
    marks=(),
)

QUEEN = dict(
    outline=(
        "M 25 117 L 25 109 L 33 103 "
        "C 38 100 43 97 45 92 "
        "C 47 88 49 80 49.5 68 "
        "L 42 60 L 42 56 L 47 52 "
        "C 44 47 36 41 31.5 36 "             # coronet flare
        "L 31.5 32.1 "
        "A 7.5 7.5 0 1 1 44.49 27.48 "       # five pearls, cut as one edge
        "A 7.5 7.5 0 1 1 57.71 25.07 "
        "A 7.5 7.5 0 1 1 70.29 25.07 "
        "A 7.5 7.5 0 1 1 83.51 27.48 "
        "A 7.5 7.5 0 1 1 96.5 32.1 "
        "L 96.5 36 "
        "C 92 41 84 47 81 52 "
        "L 86 56 L 86 60 L 78.5 68 "
        "C 79 80 81 88 83 92 "
        "C 85 97 90 100 95 103 "
        "L 103 109 L 103 117 Z"
    ),
    details=("M 36.5 44 L 91.5 44",),
    marks=(),
)

KING = dict(
    outline=(
        "M 24 117 L 24 109 L 32 103 "
        "C 37 100 43 97 45 92 "
        "C 47 88 49 80 49 70 "
        "L 42 62 L 42 58 L 47 54 "
        "C 45 49 41 43 36 37 "               # cup
        "L 33 31 "                           # rim chamfer
        "L 58 31 L 58 22 L 46 22 L 46 13 L 58 13 L 58 7 "
        "L 70 7 L 70 13 L 82 13 L 82 22 L 70 22 L 70 31 "
        "L 95 31 L 92 37 "
        "C 87 43 83 49 81 54 "
        "L 86 58 L 86 62 L 79 70 "
        "C 79 80 81 88 83 92 "
        "C 85 97 91 100 96 103 "
        "L 104 109 L 104 117 Z"
    ),
    details=("M 37.5 37 L 90.5 37",),
    marks=(),
)

KNIGHT = dict(
    outline=(
        "M 27 117 L 27 109 L 35 103 L 40 98 "
        "C 41 90 44 82 50 74 "               # chest
        "C 46 71 40 70 34 68 "               # jaw underside into the chin
        "C 30 66 26 64 25 60 "               # lower lip
        "C 22 56 22 51 25 47 "               # muzzle, nose breaks x=22
        "C 32 43 38 37 44 31 "               # dished bridge, set back off chord
        "C 46 29 47 28 49 27 "               # brow
        "C 52 28 57 26 62 26 "               # forehead
        "C 64 26 65 26 66 25 "               # poll
        "L 70 18 L 76 26 "                   # ear
        "C 78 30 80 34 82 39 "               # nape
        "C 84 44 85 50 83 55 "               # mane, two falls cut into the edge
        "C 88 62 90 74 90 86 "
        "C 90 92 89 96 88 98 "
        "L 93 103 L 101 109 L 101 117 Z"
    ),
    details=(
        "M 28 59 L 34 61.5",                             # mouth
        "M 44 46 C 46 55 44 63 39 68",                   # jaw / cheek
    ),
    marks=(
        "M 44 39.5 Q 48 35.5 52.5 39 Q 48 42.5 44 39.5 Z",   # eye
        "M 27 54.5 Q 29.5 52 31 55 Q 29 56.5 27 54.5 Z",     # nostril
    ),
)

PIECES = dict(K=KING, Q=QUEEN, R=ROOK, B=BISHOP, N=KNIGHT, P=PAWN)
ORDER = ["K", "Q", "R", "B", "N", "P"]

# ----------------------------------------------------------------- render ---


def piece_body(code, colour, uid):
    c = WHITE if colour == "w" else BLACK
    g = PIECES[code]
    d = g["outline"]
    cid = f"arris-{uid}"

    out = [f'<defs><clipPath id="{cid}"><path d="{d}"/></clipPath></defs>',
           '<g stroke-linejoin="round" stroke-linecap="round">',
           f'<path d="{d}" fill="{c["fill"]}"/>']

    # The arris pair: the same contour, displaced, clipped to itself.
    out.append(f'<g clip-path="url(#{cid})" fill="none" stroke-width="{W_RIM}">')
    out.append(f'<path d="{d}" stroke="{c["shade"]}" '
               f'transform="translate({-ARRIS} {-ARRIS})"/>')
    out.append(f'<path d="{d}" stroke="{c["lit"]}" '
               f'transform="translate({ARRIS} {ARRIS})"/>')
    out.append('</g>')

    out.append(f'<path d="{d}" fill="none" stroke="{c["line"]}" '
               f'stroke-width="{W_LINE}"/>')

    for item in g["details"]:
        path, w = item if isinstance(item, tuple) else (item, W_DETAIL)
        out.append(f'<path d="{path}" fill="none" stroke="{c["detail"]}" '
                   f'stroke-width="{w}"/>')
    for m in g["marks"]:
        out.append(f'<path d="{m}" fill="{c["mark"]}"/>')

    out.append('</g>')
    return "".join(out)


def piece_svg(code, colour):
    name = f"{colour}{code}"
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" '
            'width="128" height="128">'
            f'<title>Arris {name}</title>'
            '<desc>Arris chess set (c) ChessEver LLC. Original geometry.</desc>'
            f'{piece_body(code, colour, name)}</svg>')


def write_pieces():
    SVG_DIR.mkdir(parents=True, exist_ok=True)
    for colour in ("w", "b"):
        for code in ORDER:
            (SVG_DIR / f"{colour}{code}.svg").write_text(
                piece_svg(code, colour), encoding="utf-8")


# --------------------------------------------------------------- previews ---

def _open(w, h):
    return ('<svg xmlns="http://www.w3.org/2000/svg" '
            'xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'viewBox="0 0 {w} {h}" width="{w}" height="{h}">')


def specimen():
    cell, pad, small, gap = 132, 34, 40, 20
    w = pad * 2 + cell * 6
    row2 = pad + cell + 48
    h = row2 + small + 58

    s = [_open(w, h), f'<rect width="{w}" height="{h}" fill="{PAPER}"/>', '<defs>']
    for code in ORDER:
        s.append(f'<g id="w{code}">{piece_body(code, "w", "s" + code)}</g>')
    s.append('</defs>')

    for i, code in enumerate(ORDER):
        x = pad + i * cell
        sq = BOARD_LIGHT if i % 2 == 0 else BOARD_DARK
        s.append(f'<rect x="{x}" y="{pad}" width="{cell}" height="{cell}" fill="{sq}"/>')
        s.append(f'<use xlink:href="#w{code}" href="#w{code}" '
                 f'transform="translate({x} {pad}) scale({cell/128:.6f})"/>')

    for i, code in enumerate(ORDER):
        x = pad + i * (small + gap)
        sq = BOARD_LIGHT if i % 2 == 0 else BOARD_DARK
        s.append(f'<rect x="{x}" y="{row2}" width="{small}" height="{small}" fill="{sq}"/>')
        s.append(f'<use xlink:href="#w{code}" href="#w{code}" '
                 f'transform="translate({x} {row2}) scale({small/128:.6f})"/>')

    s.append(f'<text x="{pad + 6*(small+gap) + 16}" y="{row2 + small - 11}" '
             f'fill="#9AA29A" font-family="{FONT}" font-size="16">'
             '40 px, actual size</text>')
    s.append(f'<text x="{pad}" y="{h - 22}" fill="#7C837C" '
             f'font-family="{FONT}" font-size="13" letter-spacing="0.6">'
             'Arris. Original geometry, © ChessEver LLC.</text>')
    s.append('</svg>')
    return "".join(s)


START = ["rnbqkbnr", "pppppppp", "........", "........",
         "........", "........", "PPPPPPPP", "RNBQKBNR"]


def board():
    cell, pad = 96, 22
    w = cell * 8 + pad * 2
    s = [_open(w, w), f'<rect width="{w}" height="{w}" fill="{PAPER}"/>', '<defs>']
    for colour in ("w", "b"):
        for code in ORDER:
            s.append(f'<g id="{colour}{code}">'
                     f'{piece_body(code, colour, "b" + colour + code)}</g>')
    s.append('</defs>')
    for r in range(8):
        for f in range(8):
            sq = BOARD_LIGHT if (r + f) % 2 == 0 else BOARD_DARK
            s.append(f'<rect x="{pad + f*cell}" y="{pad + r*cell}" '
                     f'width="{cell}" height="{cell}" fill="{sq}"/>')
    for r, row in enumerate(START):
        for f, ch in enumerate(row):
            if ch == ".":
                continue
            ref = ("w" if ch.isupper() else "b") + ch.upper()
            s.append(f'<use xlink:href="#{ref}" href="#{ref}" '
                     f'transform="translate({pad + f*cell} {pad + r*cell}) '
                     f'scale({cell/128:.6f})"/>')
    s.append('</svg>')
    return "".join(s)


def contact(colour="w", bg="#9AA39C", w=380):
    s = [_open(w * 3, w * 2), f'<rect width="{w*3}" height="{w*2}" fill="{bg}"/>']
    for i, code in enumerate(ORDER):
        s.append(f'<g transform="translate({(i%3)*w} {(i//3)*w}) '
                 f'scale({w/128:.6f})">{piece_body(code, colour, "c" + code)}</g>')
    s.append('</svg>')
    return "".join(s)


if __name__ == "__main__":
    write_pieces()
    (ROOT / "arris-specimen.svg").write_text(specimen(), encoding="utf-8")
    (ROOT / "arris-board.svg").write_text(board(), encoding="utf-8")
    (ROOT / "contact-w.svg").write_text(contact("w"), encoding="utf-8")
    (ROOT / "contact-b.svg").write_text(contact("b", "#B9C0B8"), encoding="utf-8")
    print("ok")
