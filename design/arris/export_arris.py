#!/usr/bin/env python3
"""Rasterise Arris: 512 WebP for all twelve pieces, plus both previews.

Requires rsvg-convert (librsvg) and cwebp. Run build_arris.py first.
"""

import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
SVG = ROOT / "svg"
WEBP = ROOT / "webp"

SIZES = {"": 512, "256": 256, "128": 128}
PIECES = [c + p for c in "wb" for p in ("K", "Q", "R", "B", "N", "P")]


def need(tool):
    if shutil.which(tool) is None:
        sys.exit(f"missing required tool: {tool}")


def png(src, dst, width):
    subprocess.run(["rsvg-convert", "-w", str(width), str(src), "-o", str(dst)],
                   check=True)


def webp(src, dst):
    # Flat-colour vector art: lossless is both smaller and exact here.
    subprocess.run(["cwebp", "-quiet", "-lossless", "-z", "9",
                    str(src), "-o", str(dst)], check=True)


def main():
    need("rsvg-convert")
    need("cwebp")
    tmp = ROOT / ".tmp"
    tmp.mkdir(exist_ok=True)

    for sub, size in SIZES.items():
        out = WEBP / sub if sub else WEBP
        out.mkdir(parents=True, exist_ok=True)
        for name in PIECES:
            p = tmp / f"{name}.png"
            png(SVG / f"{name}.svg", p, size)
            webp(p, out / f"{name}.webp")
        print(f"webp {size}px -> {out}")

    png(ROOT / "arris-specimen.svg", ROOT / "arris-specimen.png", 860)
    png(ROOT / "arris-board.svg", ROOT / "arris-board.png", 1024)
    print("previews -> arris-specimen.png, arris-board.png")

    shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
