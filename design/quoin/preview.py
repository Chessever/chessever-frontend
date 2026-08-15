#!/usr/bin/env python3
"""Working-eye renderer: a big proof sheet plus a 40px row, for judging only."""
import subprocess, sys
from pathlib import Path

D = Path(__file__).parent
SVG = D / "svg"
ORDER = ["K", "Q", "R", "B", "N", "P"]
CREAM, GREEN = "#F0E7D3", "#5F7D63"


def png(src, dst, size, bg):
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size),
         "-b", bg, "-o", str(dst), str(src)], check=True)


def sheet(out, size, tag):
    tmp = D / "_tmp"
    tmp.mkdir(exist_ok=True)
    rows = []
    for r, side in enumerate(("w", "b")):
        cells = []
        for c, code in enumerate(ORDER):
            bg = CREAM if (r + c) % 2 == 0 else GREEN
            p = tmp / f"{tag}{side}{code}.png"
            png(SVG / f"{side}{code}.svg", p, size, bg)
            cells.append(str(p))
        row = tmp / f"{tag}row{r}.png"
        subprocess.run(["magick"] + cells + ["+append", str(row)], check=True)
        rows.append(str(row))
    subprocess.run(["magick"] + rows + ["-append", str(out)], check=True)
    print(out)


if __name__ == "__main__":
    sheet(D / "_proof_big.png", 220, "b")
    sheet(D / "_proof_40.png", 40, "s")
    subprocess.run(["magick", str(D / "_proof_40.png"), "-filter", "point",
                    "-resize", "300%", str(D / "_proof_40x3.png")], check=True)
