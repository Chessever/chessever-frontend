#!/usr/bin/env python3
"""Rasterise Ashlar: 512 WebP, the chessground density buckets, and both
previews. Run build_ashlar.py first."""

import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent
SVG = ROOT / "svg"
WEBP = ROOT / "webp"
CG = WEBP / "chessground"
ORDER = ["K", "Q", "R", "B", "N", "P"]
DENSITIES = [("1.0x", 128), ("2.0x", 256), ("3.0x", 384), ("4.0x", 512)]


def need(binary):
    if shutil.which(binary) is None:
        raise SystemExit(f"missing {binary}")


def png(src, dst, size):
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size),
                    str(src), "-o", str(dst)], check=True)


def webp(src, dst):
    # lossless: flat two-tone art, and the alpha edge must stay clean
    subprocess.run(["cwebp", "-quiet", "-lossless", "-exact",
                    str(src), "-o", str(dst)], check=True)


def main():
    for b in ("rsvg-convert", "cwebp"):
        need(b)
    tmp = ROOT / ".tmp"
    tmp.mkdir(exist_ok=True)
    WEBP.mkdir(exist_ok=True)
    for d, _ in DENSITIES:
        (CG / d).mkdir(parents=True, exist_ok=True)

    for colour in ("w", "b"):
        for code in ORDER:
            name = f"{colour}{code}"
            src = SVG / f"{name}.svg"
            # headline deliverable: 512
            p = tmp / f"{name}-512.png"
            png(src, p, 512)
            webp(p, WEBP / f"{name}.webp")
            # chessground density buckets
            for d, size in DENSITIES:
                q = tmp / f"{name}-{size}.png"
                png(src, q, size)
                webp(q, CG / d / f"{name}.webp")

    subprocess.run(["rsvg-convert", "-w", "1680",
                    str(ROOT / "ashlar-specimen.svg"),
                    "-o", str(ROOT / "ashlar-specimen.png")], check=True)
    subprocess.run(["rsvg-convert", "-w", "1200",
                    str(ROOT / "ashlar-board.svg"),
                    "-o", str(ROOT / "ashlar-board.png")], check=True)

    shutil.rmtree(tmp)
    print(f"512 webp -> {WEBP}")
    print(f"density buckets -> {CG}")
    print("previews -> ashlar-specimen.png, ashlar-board.png")


if __name__ == "__main__":
    main()
