#!/usr/bin/env python3
"""Quoin - an original 2D Staunton chess set for chessground.

(c) ChessEver LLC. Every path in this file is authored from raw coordinates.
Nothing is traced, morphed, filtered or recoloured from cburnett, merida,
california, staunty, gioco, maestro or any other existing set.

The cut is a display-grotesque Staunton. Two things define it. First, the
pieces are assembled the way a set is actually turned - base, shaft, collar,
head - each turning drawn as its own closed outlined element and stacked back
to front, so the drawing is a stack of masses rather than one traced contour.
Second, the light is a single cylindrical rake from the upper left, laid down
as two flat planes clipped to the piece: a lit flank on the left, a turned-away
flank on the right, and the body tone left untouched through the middle. No
gradient, no bloom, no seam across the face of the piece.

Grid 45 x 45 (chessground native). Centre line x = 22.5, ground line y = 39.9.

    python3 build_quoin.py
"""

from pathlib import Path

CX = 22.5
GROUND = 39.9
OUT = Path(__file__).parent / "svg"

# --------------------------------------------------------------------------
# Palette: cool quarried stone and a green-grey graphite. Deliberately
# NOT the stock indigo-slate dark, and deliberately not paper cream.
# --------------------------------------------------------------------------
WHITE = dict(
    body="#F0F1EE",
    line="#141A1F",
    detail="#141A1F", incise="#141A1F",
    lit="#FFFFFF", lit_a="0.34",
    shade="#0A1013", shade_a="0.10",
    contour=None,
    outer_w=1.35,
)
BLACK = dict(
    body="#272C2E",
    line="#0A0D0C",
    detail="#CCD3D2", incise="#838D8D",
    lit="#FFFFFF", lit_a="0.15",
    shade="#000000", shade_a="0.18",
    contour="#7F8A89",     # internal structure inverts to light on a dark body
    outer_w=1.70,
    contour_w=1.15,
)

def n(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def mx(x):
    """Mirror across the centre line."""
    return 2 * CX - x


# --------------------------------------------------------------------------
# turnings - the shared vocabulary every piece is assembled from
# --------------------------------------------------------------------------
def foot(tw, ty, bw, ch=1.5, by=GROUND, r=1.0):
    """The whole pedestal as ONE turning: chamfer out, straight wall, rounded
    ground edge. Drawn as a single element on purpose - a chamfer plus a
    plinth plus a step stacked separately reads as a barcode at 40px."""
    return (
        f"M {n(CX-tw)} {n(ty)} H {n(CX+tw)} "
        f"L {n(CX+bw)} {n(ty+ch)} V {n(by-r)} "
        f"Q {n(CX+bw)} {n(by)} {n(CX+bw-r)} {n(by)} "
        f"H {n(CX-bw+r)} Q {n(CX-bw)} {n(by)} {n(CX-bw)} {n(by-r)} "
        f"V {n(ty+ch)} Z"
    )


def shaft(tw, ty, bw, by, k1=0.52, k2=0.18, pull=0.35):
    """Concave shaft: holds its width, then kicks out into the foot."""
    h = by - ty
    c1 = (CX + tw, ty + k1 * h)
    c2 = (CX + bw - pull * (bw - tw), by - k2 * h)
    return (
        f"M {n(CX-tw)} {n(ty)} H {n(CX+tw)} "
        f"C {n(c1[0])} {n(c1[1])} {n(c2[0])} {n(c2[1])} {n(CX+bw)} {n(by)} "
        f"H {n(CX-bw)} "
        f"C {n(mx(c2[0]))} {n(c2[1])} {n(mx(c1[0]))} {n(c1[1])} {n(CX-tw)} {n(ty)} Z"
    )


def collar(hw, y0, y1, r=1.0):
    """Turned collar ring - the band that separates head from shaft."""
    return (
        f"M {n(CX-hw+r)} {n(y0)} H {n(CX+hw-r)} "
        f"Q {n(CX+hw)} {n(y0)} {n(CX+hw)} {n(y0+r)} V {n(y1-r)} "
        f"Q {n(CX+hw)} {n(y1)} {n(CX+hw-r)} {n(y1)} H {n(CX-hw+r)} "
        f"Q {n(CX-hw)} {n(y1)} {n(CX-hw)} {n(y1-r)} V {n(y0+r)} "
        f"Q {n(CX-hw)} {n(y0)} {n(CX-hw+r)} {n(y0)} Z"
    )


def ball(cy, r, cx=CX):
    """Finial / pearl, as arcs so it stays one path element."""
    return (
        f"M {n(cx)} {n(cy-r)} "
        f"A {n(r)} {n(r)} 0 0 1 {n(cx)} {n(cy+r)} "
        f"A {n(r)} {n(r)} 0 0 1 {n(cx)} {n(cy-r)} Z"
    )


# --------------------------------------------------------------------------
# the six pieces
# --------------------------------------------------------------------------
def pawn():
    """Ball, collar, taper, foot. Quiet. Nothing invented."""
    return dict(
        shapes=[
            foot(6.0, 35.6, 8.8, ch=1.3, r=0.9),
            shaft(4.6, 21.6, 6.0, 35.6),
            collar(5.2, 19.7, 21.9, r=1.0),
            ball(15.7, 4.5),
        ],
        span=(13.7, 31.3),
        details=[],
    )


def rook():
    """Three merlons, neck, shaft, flared base. Architecture, not decoration."""
    hw, top, floor, base = 10.4, 9.6, 12.5, 15.6
    m, g = 4.9, 3.05                      # 4.9*3 + 3.05*2 = 20.8 = 2*hw
    a0 = CX - hw
    a1, b0 = a0 + m, a0 + m + g
    b1, c0 = b0 + m, b0 + m + g
    c1 = c0 + m
    crown = (
        f"M {n(a0)} {n(top)} H {n(a1)} V {n(floor)} H {n(b0)} V {n(top)} "
        f"H {n(b1)} V {n(floor)} H {n(c0)} V {n(top)} H {n(c1)} "
        f"V {n(base)} H {n(a0)} Z"
    )
    return dict(
        shapes=[
            foot(8.6, 34.9, 12.4),
            shaft(7.3, 18.8, 8.6, 34.9, k1=0.5, k2=0.22),
            collar(9.6, 15.4, 18.5, r=0.9),   # corbel under the crown
            crown,
        ],
        span=(10.1, 34.9),
        details=[],
    )


def bishop():
    """Ball finial, mitre, clear slit, body, foot."""
    # A mitre, not a teardrop: a domed crown with a short neck to the finial,
    # the swell carried low so the widest point sits just above the collar,
    # then a real waist tucking back in. The pointed-egg version reads as a
    # balloon at any size.
    mitre = (
        "M 22.5 9.6 "
        "C 23.9 10.1 24.8 11.4 24.9 13.4 "   # short neck under the finial
        "C 25.9 16.6 28.2 18.6 28.5 21.2 "   # the swell, carried low
        "C 28.7 23.5 27.4 25.2 25.5 25.9 "   # waist into the collar
        "H 19.5 "
        "C 17.6 25.2 16.3 23.5 16.5 21.2 "
        "C 16.8 18.6 19.1 16.6 20.1 13.4 "
        "C 20.2 11.4 21.1 10.1 22.5 9.6 Z"
    )
    return dict(
        shapes=[
            foot(7.0, 35.3, 10.6, ch=1.4),
            shaft(4.4, 26.6, 7.0, 35.3),
            collar(5.3, 24.4, 26.8, r=1.0),
            mitre,
            ball(8.0, 1.9),
        ],
        # The slit is a tapered wedge, not a stroke of even width - a cut has
        # a mouth and a close.
        span=(11.9, 33.1),
        details=[("fill", "M 24.7 15.6 L 26 16.6 L 22.4 21.4 L 21.7 20.5 Z", 0)],
    )


def queen():
    """Five pearls on a coronet, the king's body language, no cross."""
    coronet = (
        "M 12.1 20.8 L 12.9 12.4 L 15.6 17.2 L 17.1 10.2 L 20.3 16.6 "
        "L 22.5 8.4 L 24.7 16.6 L 27.9 10.2 L 29.4 17.2 L 32.1 12.4 "
        "L 32.9 20.8 Z"
    )
    return dict(
        shapes=[
            foot(8.3, 35.0, 12.4),
            shaft(5.9, 23.2, 8.3, 35.0),
            coronet,
            collar(10.4, 20.4, 23.4, r=1.3),
            ball(11.0, 1.7, cx=12.9),
            ball(8.9, 1.7, cx=17.1),
            ball(6.9, 2.0, cx=22.5),
            ball(8.9, 1.7, cx=mx(17.1)),
            ball(11.0, 1.7, cx=mx(12.9)),
        ],
        span=(10.1, 34.9),
        details=[],
    )


def king():
    """Latin cross, cup head, collar, flared body, stepped foot."""
    cross = (
        "M 21.1 2.9 H 23.9 V 6.3 H 27.3 V 9.1 H 23.9 V 13 H 21.1 V 9.1 "
        "H 17.7 V 6.3 H 21.1 Z"
    )
    cup = (
        "M 14.1 13.6 "
        "C 16.8 12.2 28.2 12.2 30.9 13.6 "
        "C 30.4 17.4 28.9 20 27 21.4 "
        "H 18 "
        "C 16.1 20 14.6 17.4 14.1 13.6 Z"
    )
    return dict(
        shapes=[
            foot(8.9, 34.8, 13.0),
            shaft(5.6, 23.2, 8.9, 34.8),
            cup,
            collar(6.4, 20.6, 23.4, r=1.1),
            cross,
        ],
        span=(9.5, 35.5),
        details=[],
    )


def knight():
    """A real horse: ear, brow, dish, muzzle, jaw, neck, chest, pedestal.

    Read the outline clockwise from the ear tip: back of ear, crest, neck,
    ground line of the neck, chest, throat, jowl, jaw, chin, lip, muzzle
    front, dished nose bridge, brow, poll, front of ear.
    """
    head = (
        "M 25.6 6.6 "
        "C 26.5 7.6 27.1 8.7 27.4 9.9 "          # back of the ear
        "C 29.5 11 31 13.4 31.7 16.6 "           # crest
        "C 32.4 19.6 32.5 22.8 32.3 26 "         # neck, back edge
        "C 32.2 29.4 32.4 32.2 32.4 34.6 "
        "H 12.6 "                                # ground line of the neck
        "C 12.4 31.2 12.8 28.4 14 26.2 "         # chest
        "C 15.1 24.2 16.5 23.1 17.8 22.3 "       # throat into the jowl
        "C 16.5 22.6 15.3 23 14.2 23.3 "         # jaw forward to the chin
        "C 12.8 23.7 11.4 23.1 10.9 21.9 "       # lip
        "C 10.4 20.6 10.9 19.2 11.7 18.1 "       # front of the muzzle
        "C 13.7 16.5 14.7 15.1 15.7 13.9 "       # the dish - concave bridge
        "C 17.3 12.1 19.4 10.6 21.6 9.6 "        # brow
        "C 22.5 9.9 23.4 9.7 24.2 9.3 "          # poll
        "C 24.4 8.1 24.9 7.4 25.6 6.6 Z"         # front of the ear
    )
    return dict(
        shapes=[
            foot(9.9, 34.6, 12.6),
            head,
        ],
        span=(10.4, 35.1),
        details=[
            ("stroke", "M 27.4 11 C 28.7 12.8 29.5 15 29.9 17.4", 1.1),  # crest
            ("stroke", "M 18.1 21.9 C 19.5 20.3 20.6 18.5 21.1 16.5", 1.05),
            ("stroke", "M 11.4 21.4 C 12.7 22.2 13.7 22.6 14.8 22.9", 1.0),
            ("fill", "M 17.6 16.1 C 18.1 15.2 19.4 15.1 19.9 15.8 "
                     "C 19.5 16.8 18.2 17 17.6 16.1 Z", 0),    # almond eye
            ("fill", "M 12.5 19.5 C 13.3 19.1 13.9 19.6 13.6 20.3 "
                     "C 13 20.7 12.4 20.3 12.5 19.5 Z", 0),    # nostril
            ("stroke", "M 25.5 8 C 25.9 8.7 26.2 9.3 26.4 9.9", 0.95),
        ],
    )


PIECES = dict(K=king(), Q=queen(), R=rook(), B=bishop(), N=knight(), P=pawn())
ORDER = ["K", "Q", "R", "B", "N", "P"]


# --------------------------------------------------------------------------
# emit
# --------------------------------------------------------------------------
def svg_for(code, side):
    pal = WHITE if side == "w" else BLACK
    piece = PIECES[code]
    name = f"{side}{code}"
    cid = f"q{name}"
    joins = 'stroke-linejoin="round" stroke-linecap="round"'
    paths = "".join(f'<path d="{d}"/>' for d in piece["shapes"])

    body_pass = (
        f'<g fill="{pal["body"]}" stroke="{pal["line"]}" '
        f'stroke-width="{pal["outer_w"]}" {joins}>{paths}</g>'
    )

    # The dark body inverts its internal structure to light: the same drawing
    # re-struck thin in a pale ink over the heavy dark pass. Clipped to the
    # silhouette so only the inner half of each contour survives - the outer
    # rim stays dark and the piece never grows a grey halo on the board.
    contour_pass = ""
    if pal["contour"]:
        contour_pass = (
            f'<g clip-path="url(#{cid})" fill="{pal["body"]}" '
            f'stroke="{pal["contour"]}" stroke-width="{pal["contour_w"]}" '
            f"{joins}>{paths}</g>"
        )

    # The rake, keyed to THIS piece's own width. A flat plane with a fixed
    # boundary cuts a hard seam across a wide piece and misses a narrow one
    # entirely, so the falloff is anchored to the piece's span instead: lit
    # flank rolling off before the axis, turned-away flank picking up after
    # it. Monochrome value only - this is modelling a cylinder, not colour.
    x0, x1 = piece["span"]
    w = x1 - x0
    grad = (
        f'<linearGradient id="{cid}l" gradientUnits="userSpaceOnUse" '
        f'x1="{n(x0)}" y1="6" x2="{n(x0 + 0.42 * w)}" y2="30">'
        f'<stop offset="0" stop-color="{pal["lit"]}" '
        f'stop-opacity="{pal["lit_a"]}"/>'
        f'<stop offset="1" stop-color="{pal["lit"]}" stop-opacity="0"/>'
        f"</linearGradient>"
        f'<linearGradient id="{cid}s" gradientUnits="userSpaceOnUse" '
        f'x1="{n(x0 + 0.62 * w)}" y1="6" x2="{n(x1)}" y2="30">'
        f'<stop offset="0" stop-color="{pal["shade"]}" stop-opacity="0"/>'
        f'<stop offset="1" stop-color="{pal["shade"]}" '
        f'stop-opacity="{pal["shade_a"]}"/>'
        f"</linearGradient>"
    )
    light = (
        f'<g clip-path="url(#{cid})">'
        f'<rect x="0" y="0" width="45" height="45" fill="url(#{cid}l)"/>'
        f'<rect x="0" y="0" width="45" height="45" fill="url(#{cid}s)"/>'
        f"</g>"
    )

    det = []
    for kind, d, w in piece["details"]:
        if kind == "stroke":
            det.append(
                f'<path d="{d}" fill="none" stroke="{pal["incise"]}" '
                f'stroke-width="{w}" stroke-linecap="round" '
                f'stroke-linejoin="round"/>'
            )
        else:
            det.append(f'<path d="{d}" fill="{pal["detail"]}"/>')

    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 45 45" '
        'width="45" height="45">'
        f"<title>Quoin {name}</title>"
        "<desc>Quoin chess set (c) ChessEver LLC. Original geometry, "
        "authored from raw coordinates.</desc>"
        f'<defs><clipPath id="{cid}">{paths}</clipPath>{grad}</defs>'
        f"{body_pass}{contour_pass}{light}{''.join(det)}"
        "</svg>"
    )


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for code in ORDER:
        for side in ("w", "b"):
            (OUT / f"{side}{code}.svg").write_text(svg_for(code, side))
    print(f"wrote 12 svg -> {OUT}")


if __name__ == "__main__":
    main()
