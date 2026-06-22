#!/usr/bin/env python3
"""Fail if any network image decodes at its original resolution.

Network images (Image.network, CachedNetworkImage, FadeInImage, Image.memory,
Image.file) load arbitrary-resolution sources. Without a decode cap they raster
at full size and tank scroll FPS / memory. Every such call MUST set one of:
  cacheWidth / cacheHeight        (Image.*)
  memCacheWidth / memCacheHeight  (CachedNetworkImage)
or wrap the provider in ResizeImage(...).

Intentional full-resolution sites (e.g. a fullscreen zoom viewer) opt out with
a `// image-cap-ok` comment anywhere inside the constructor call.

Usage:  python3 tool/check_image_caps.py
Exit 0 = clean, 1 = uncapped sites found.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"

# Constructors that pull arbitrary-resolution raster sources.
CONSTRUCTORS = re.compile(
    r"\b(Image\.network|Image\.memory|Image\.file|CachedNetworkImage|FadeInImage(?:\.assetNetwork)?)\s*\("
)
CAP_KEYS = re.compile(r"\b(cacheWidth|cacheHeight|memCacheWidth|memCacheHeight|ResizeImage)\b")
OPT_OUT = re.compile(r"//\s*image-cap-ok")


def call_span(text: str, open_paren_idx: int) -> str:
    """Return the source text of a (...) call starting at the opening paren.

    Naive paren matcher — good enough for Dart widget trees. Skips parens that
    sit inside single/double quoted strings so URLs with '(' don't desync it.
    """
    depth = 0
    i = open_paren_idx
    n = len(text)
    quote = None
    while i < n:
        c = text[i]
        if quote:
            if c == quote and text[i - 1] != "\\":
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[open_paren_idx : i + 1]
        i += 1
    return text[open_paren_idx:]  # unbalanced — return rest, will likely flag


def main() -> int:
    offenders = []
    for path in sorted(LIB.rglob("*.dart")):
        src = path.read_text(encoding="utf-8", errors="replace")
        for m in CONSTRUCTORS.finditer(src):
            ctor = m.group(1)
            span = call_span(src, m.end() - 1)
            if CAP_KEYS.search(span) or OPT_OUT.search(span):
                continue
            line = src.count("\n", 0, m.start()) + 1
            rel = path.relative_to(ROOT)
            offenders.append(f"{rel}:{line}: {ctor} has no decode cap")

    if offenders:
        print("Uncapped network image(s) — add cacheWidth/cacheHeight or "
              "memCacheWidth/memCacheHeight (or `// image-cap-ok` if full-res "
              "is intentional):\n")
        for o in offenders:
            print(f"  {o}")
        print(f"\n{len(offenders)} uncapped site(s).")
        return 1

    print("All network images are resolution-capped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
