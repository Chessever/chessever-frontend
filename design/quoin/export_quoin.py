#!/usr/bin/env python3
"""Rasterise Quoin: WebP for chessground, plus the specimen and board previews.

Needs rsvg-convert (librsvg), ImageMagick and cwebp.

    python3 build_quoin.py && python3 export_quoin.py
"""

import shutil
import subprocess
import tempfile
from pathlib import Path

D = Path(__file__).parent
SVG = D / "svg"
WEBP = D / "webp"
FLUT = WEBP / "flutter"

ORDER = ["K", "Q", "R", "B", "N", "P"]
NAMES = [f"{s}{c}" for c in ORDER for s in ("w", "b")]

CREAM = "#F0E7D3"
GREEN = "#5F7D63"
FRAME = "#2B3230"

START = [
    "rnbqkbnr",
    "pppppppp",
    "8", "8", "8", "8",
    "PPPPPPPP",
    "RNBQKBNR",
]


def run(*a):
    subprocess.run([str(x) for x in a], check=True)


def png(src, dst, size, bg="none"):
    run("rsvg-convert", "-w", size, "-h", size, "-b", bg, "-o", dst, src)


# --------------------------------------------------------------------------
def export_webp():
    for d in (WEBP, FLUT):
        d.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for name in NAMES:
            src = SVG / f"{name}.svg"
            # the requested deliverable: 512, transparent
            p = tmp / f"{name}_512.png"
            png(src, p, 512)
            run("cwebp", "-quiet", "-q", 94, "-alpha_q", 100, p,
                "-o", WEBP / f"{name}.webp")
            # Flutter density buckets off the same geometry
            for size, sub in ((128, ""), (256, "2.0x"), (384, "3.0x"),
                              (512, "4.0x")):
                out = FLUT / sub
                out.mkdir(parents=True, exist_ok=True)
                q = tmp / f"{name}_{size}.png"
                png(src, q, size)
                run("cwebp", "-quiet", "-q", 94, "-alpha_q", 100, q,
                    "-o", out / f"{name}.webp")
    print(f"webp -> {WEBP} (512) and {FLUT} (1x/2x/3x/4x)")


# --------------------------------------------------------------------------
def specimen(cell=220):
    """The six white pieces, one row, alternating cream and green."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        cells = []
        for i, code in enumerate(ORDER):
            bg = CREAM if i % 2 == 0 else GREEN
            p = tmp / f"{code}.png"
            png(SVG / f"w{code}.svg", p, cell, bg)
            cells.append(p)
        run("magick", *cells, "+append",
            "-bordercolor", FRAME, "-border", "6", D / "quoin-specimen.png")
    print(D / "quoin-specimen.png")


def board(cell=64):
    """Starting position, a1 dark, rank 8 at the top."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        cache = {}
        rows = []
        for r, rank in enumerate(START):
            squares = []
            c = 0
            for ch in rank:
                if ch.isdigit():
                    span = int(ch)
                else:
                    span = 1
                for _ in range(span):
                    bg = CREAM if (r + c) % 2 == 0 else GREEN
                    if ch.isdigit():
                        key = ("empty", bg)
                        if key not in cache:
                            p = tmp / f"e{len(cache)}.png"
                            run("magick", "-size", f"{cell}x{cell}",
                                f"xc:{bg}", p)
                            cache[key] = p
                    else:
                        side = "w" if ch.isupper() else "b"
                        key = (side + ch.upper(), bg)
                        if key not in cache:
                            p = tmp / f"p{len(cache)}.png"
                            png(SVG / f"{key[0]}.svg", p, cell, bg)
                            cache[key] = p
                    squares.append(cache[key])
                    c += 1
            row = tmp / f"r{r}.png"
            run("magick", *squares, "+append", row)
            rows.append(row)
        run("magick", *rows, "-append",
            "-bordercolor", FRAME, "-border", "8", D / "quoin-board.png")
    print(D / "quoin-board.png")


if __name__ == "__main__":
    export_webp()
    specimen()
    board()
    for junk in D.glob("_proof*"):
        junk.unlink()
    shutil.rmtree(D / "_tmp", ignore_errors=True)
