#!/usr/bin/env python3
"""
Export the PLINTH set: WebP rasters for chessground, a specimen sheet and a
starting-position board preview.

Needs: rsvg-convert (librsvg) and ImageMagick on PATH.
"""

import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SVG = os.path.join(HERE, "svg")
WEBP = os.path.join(HERE, "webp")

CODES = [c + p for c in "wb" for p in "KQRBNP"]

# chessground ships 1x/2x/3x/4x off a 128pt base.
SIZES = {"": 128, "2.0x": 256, "3.0x": 384, "4.0x": 512}

# The board. A warm bone against a muted sage: enough value separation for the
# cool stone of the pieces to sit on either square without the outline doing
# all the work.
LIGHT = "#E9E3D1"
DARK = "#77896E"
PAPER = "#20252A"      # the ground the specimen sheet sits on
INK = "#E7EAED"


def run(cmd):
    subprocess.run(cmd, check=True)


def png(code, px, out):
    run(["rsvg-convert", "-w", str(px), "-h", str(px),
         os.path.join(SVG, f"{code}.svg"), "-o", out])


def build_webp():
    for sub, px in SIZES.items():
        d = os.path.join(WEBP, sub) if sub else WEBP
        os.makedirs(d, exist_ok=True)
        for code in CODES:
            tmp = os.path.join(d, f"{code}.png")
            png(code, px, tmp)
            run(["cwebp", "-quiet", "-q", "95", "-alpha_q", "100",
                 tmp, "-o", os.path.join(d, f"{code}.webp")])
            os.remove(tmp)
    print(f"webp -> {WEBP}  (128 / 256 / 384 / 512)")


def square(colour, px, out):
    run(["magick", "-size", f"{px}x{px}", f"xc:{colour}", out])


def build_sheet(tmp):
    """Six white pieces on alternating cream/sage squares, plus a name plate."""
    cell = 200
    cells = []
    for i, p in enumerate("KQRBNP"):
        bg = LIGHT if i % 2 == 0 else DARK
        sq = os.path.join(tmp, f"sq{i}.png")
        square(bg, cell, sq)
        pc = os.path.join(tmp, f"pc{i}.png")
        png(f"w{p}", cell, pc)
        merged = os.path.join(tmp, f"cell{i}.png")
        run(["magick", sq, pc, "-gravity", "center", "-composite", merged])
        cells.append(merged)

    strip = os.path.join(tmp, "strip.png")
    run(["magick", "montage"] + cells +
        ["-tile", "6x1", "-geometry", "+0+0", "-background", "none", strip])

    sheet = os.path.join(HERE, "plinth-specimen.png")
    # Everything hangs off one left margin at x=100, the same margin the
    # 1200-wide strip sits on. No stranded corners.
    run(["magick", "-size", "1400x560", f"xc:{PAPER}",
         "(", strip, "-resize", "1200x200", ")",
         "-gravity", "north", "-geometry", "+0+240", "-composite",
         "-font", "Avenir-Black", "-pointsize", "56", "-fill", INK,
         "-gravity", "northwest", "-annotate", "+100+80", "Plinth",
         "-font", "Avenir-Book", "-pointsize", "23", "-fill", "#8A94A0",
         "-gravity", "northwest", "-annotate", "+103+172",
         "display grotesque Staunton",
         "-font", "Avenir-Book", "-pointsize", "19", "-fill", "#68727E",
         "-gravity", "southwest", "-annotate", "+103+48",
         "© ChessEver LLC   ·   original geometry, 128 grid",
         sheet])
    print(f"sheet -> {sheet}")


START = [
    "rnbqkbnr",
    "pppppppp",
    "........",
    "........",
    "........",
    "........",
    "PPPPPPPP",
    "RNBQKBNR",
]


def build_board(tmp):
    cell = 128
    size = cell * 8
    board = os.path.join(tmp, "board.png")
    run(["magick", "-size", f"{size}x{size}", f"xc:{LIGHT}", board])
    args = ["magick", board]
    for r in range(8):
        for c in range(8):
            if (r + c) % 2 == 1:
                args += ["-fill", DARK, "-draw",
                         f"rectangle {c*cell},{r*cell} {(c+1)*cell-1},{(r+1)*cell-1}"]
    args.append(board)
    run(args)

    for r, row in enumerate(START):
        for c, ch in enumerate(row):
            if ch == ".":
                continue
            code = ("w" if ch.isupper() else "b") + ch.upper()
            pc = os.path.join(tmp, f"b_{code}.png")
            if not os.path.exists(pc):
                png(code, cell, pc)
            run(["magick", board, pc, "-geometry", f"+{c*cell}+{r*cell}",
                 "-composite", board])

    out = os.path.join(HERE, "plinth-board.png")
    run(["magick", board, "-bordercolor", PAPER, "-border", "40", out])
    print(f"board -> {out}")


def main():
    tmp = os.path.join(HERE, ".tmp")
    os.makedirs(tmp, exist_ok=True)
    build_webp()
    build_sheet(tmp)
    build_board(tmp)
    for fn in os.listdir(tmp):
        os.remove(os.path.join(tmp, fn))
    os.rmdir(tmp)


if __name__ == "__main__":
    main()
