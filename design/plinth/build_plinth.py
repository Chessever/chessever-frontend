#!/usr/bin/env python3
"""
PLINTH — an original 2D Staunton chess set for chessground.
(c) ChessEver LLC. All geometry authored from scratch for this set.

Cut: "display grotesque Staunton".
  - Classic Staunton letterforms, one new cut. Nothing themed, nothing invented.
  - Plumper than cburnett, cooler stone than a paper set, flatter fill than Merida.
  - One light from the upper left, expressed as a single HARD-EDGED shadow plane
    (a stencil cut, never an airbrush) plus a slab under each real overhang.
  - Every piece stands on the same two-step chamfered plinth: the family DNA.
  - Corners are authored crisp and softened only by the round stroke joins.

Coordinate system: viewBox 0 0 128 128, centre line x = 64, ground line y = 118.
Height ladder (top of piece): K 5, Q 9, N 10, B 12, R 16, P 20.
"""

import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "svg")

CX = 64.0
GROUND = 118.0

# ---------------------------------------------------------------- palette ----
# Cool quarried stone, not warm vellum. Two tones per piece plus the outline.
WHITE = dict(
    body="#EEF0F2",      # cool near-white stone
    shade="#BDC6CF",     # the cut plane
    line="#13161A",      # outline
    detail="#13161A",    # internal structure
    eye="#13161A",
)
BLACK = dict(
    body="#30363D",      # flat cool graphite, never pure black
    shade="#1A1E23",
    line="#090B0D",
    detail="#828D9A",    # internal structure reads light on a dark body
    eye="#B4BDC7",       # the eye needs one more step of lift to hold at 40px
)

OUTER_W = 4.6            # silhouette stroke
INNER_W = 2.8            # internal structure stroke


# ------------------------------------------------------------ path helpers ---
def f(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def pts(*coords):
    return " ".join(f(c) for c in coords)


# ------------------------------------------------------------- the plinth ----
# Two chamfered steps under a landing collar. Shared by all six pieces; the
# only thing that changes is the width, which is how the set holds together.
SLAB_T, RISER_T, COLLAR_T = 110.5, 103.5, 97.5


def plinth_left(slab, riser, collar):
    return (
        f"L {pts(CX - collar, COLLAR_T)} "
        f"L {pts(CX - collar, 100.5)} "
        f"L {pts(CX - riser, RISER_T)} "
        f"L {pts(CX - riser, 107.5)} "
        f"L {pts(CX - slab, SLAB_T)} "
        f"L {pts(CX - slab, 114.6)} "
        f"Q {pts(CX - slab, GROUND, CX - slab + 4, GROUND)} "
    )


def plinth_right(slab, riser, collar):
    return (
        f"L {pts(CX + slab - 4, GROUND)} "
        f"Q {pts(CX + slab, GROUND, CX + slab, 114.6)} "
        f"L {pts(CX + slab, SLAB_T)} "
        f"L {pts(CX + riser, 107.5)} "
        f"L {pts(CX + riser, RISER_T)} "
        f"L {pts(CX + collar, 100.5)} "
        f"L {pts(CX + collar, COLLAR_T)} "
    )


def plinth_lines(slab, riser, collar):
    """Two lines only. The chamfers and the shadow slabs carry the rest."""
    return [
        f"M {pts(CX - riser, RISER_T)} L {pts(CX + riser, RISER_T)}",
        f"M {pts(CX - slab, SLAB_T)} L {pts(CX + slab, SLAB_T)}",
    ]


def circle_path(cx, cy, r):
    return (
        f"M {pts(cx - r, cy)} "
        f"A {pts(r, r)} 0 1 0 {pts(cx + r, cy)} "
        f"A {pts(r, r)} 0 1 0 {pts(cx - r, cy)} Z"
    )


def bead_chain(spec):
    """
    Trace the outer contour of a chain of near-tangent circles, from the first
    circle's bottom point all the way over the chain to the last circle's
    bottom point. The V between neighbours is what makes the queen's five
    pearls read as five pearls at 40px rather than as one bumpy bar.
    Returns (arc commands, start point, end point, notch points).
    """
    import math

    def upper_xsect(a, b):
        (x1, y1, r1), (x2, y2, r2) = a, b
        dx, dy = x2 - x1, y2 - y1
        d = math.hypot(dx, dy)
        t = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
        h = math.sqrt(max(r1 * r1 - t * t, 0.0))
        bx, by = x1 + t * dx / d, y1 + t * dy / d
        p1 = (bx + h * dy / d, by - h * dx / d)
        p2 = (bx - h * dy / d, by + h * dx / d)
        return p1 if p1[1] < p2[1] else p2

    notch = [upper_xsect(spec[i], spec[i + 1]) for i in range(len(spec) - 1)]
    x0, y0, r0 = spec[0]
    xn, yn, rn = spec[-1]
    start, end = (x0, y0 + r0), (xn, yn + rn)

    cmds = ""
    for i, (cx, cy, r) in enumerate(spec):
        big = 1 if i in (0, len(spec) - 1) else 0
        tgt = notch[i] if i < len(notch) else end
        cmds += f"A {pts(r, r)} 0 {big} 1 {pts(*tgt)} "
    return cmds, start, end, notch

# ------------------------------------------------------------- the shadow ----
# One rake of light from the upper left. The shadow is a straight cut that leans
# left as it falls, plus a slab under each overhang. Clipped to the silhouette,
# so the plane always terminates exactly on the piece's own contour.
def rake(x_top=73.0, x_bot=57.0):
    return f"M {pts(x_top, -4)} L 132 -4 L 132 132 L {pts(x_bot, 132)} Z "


def slab_under(y, h=4.4):
    return f"M -4 {f(y)} L 132 {f(y)} L 132 {f(y + h)} L -4 {f(y + h)} Z "


PLINTH_SLABS = slab_under(RISER_T, 4.0) + slab_under(SLAB_T, 4.0)


# =============================================================== the pieces ==
# Proportion rule for this cut: the identifying form (crown, coronet, merlons,
# mitre, horse) owns the top ~55% of the piece. Stems are deliberately short —
# a long plain stem carries no information and is dead weight at 40px.

def king():
    slab, riser, collar = 49, 42, 34
    d = (
        # Latin cross, crisp arms, softened only by the round joins
        f"M {pts(57.8, 5)} "
        f"L {pts(57.8, 12.4)} L {pts(44.4, 12.4)} L {pts(44.4, 23.2)} "
        f"L {pts(57.8, 23.2)} L {pts(57.8, 30.6)} "
        # cup: a flaring lip, then a bellied bowl
        f"L {pts(35.6, 29.6)} L {pts(39.4, 37.6)} "
        f"C {pts(40.6, 45.4, 45.4, 53, 51.4, 58)} "
        # collar overhangs the bowl, chamfers into the stem
        f"L {pts(44.6, 59)} L {pts(43.4, 70.4)} L {pts(52.6, 72.8)} "
        f"C {pts(50.4, 82, 45, 90.6, 30, 97.5)} "
        + plinth_left(slab, riser, collar)
        + plinth_right(slab, riser, collar)
        + f"C {pts(83, 90.6, 77.6, 82, 75.4, 72.8)} "
        f"L {pts(84.6, 70.4)} L {pts(83.4, 59)} L {pts(76.6, 58)} "
        f"C {pts(82.6, 53, 87.4, 45.4, 88.6, 37.6)} "
        f"L {pts(92.4, 29.6)} L {pts(70.2, 30.6)} "
        f"L {pts(70.2, 23.2)} L {pts(83.6, 23.2)} L {pts(83.6, 12.4)} "
        f"L {pts(70.2, 12.4)} L {pts(70.2, 5)} Z"
    )
    lines = [
        f"M {pts(39.4, 37.6)} C {pts(50.6, 41, 77.4, 41, 88.6, 37.6)}",   # far rim of the cup
        f"M {pts(44.6, 59)} L {pts(83.4, 59)}",                            # collar top
        f"M {pts(43.4, 70.4)} L {pts(84.6, 70.4)}",                        # collar bottom
    ] + plinth_lines(slab, riser, collar)
    shadow = (rake(73, 57) + slab_under(37.6, 3.6) + slab_under(59)
              + slab_under(70.4, 3.4) + PLINTH_SLABS)
    return dict(d=d, lines=lines, shadow=shadow)


def queen():
    slab, riser, collar = 48, 41, 33
    # Five near-tangent pearls emerging from a solid coronet. No free-standing
    # spikes: at 40px separate points close up into a slab, so all the
    # articulation lives in the V between neighbouring pearls.
    pearls = [(37.4, 21.6, 7.4), (50.7, 17.6, 7.4), (64.0, 16.0, 7.4),
              (77.3, 17.6, 7.4), (90.6, 21.6, 7.4)]
    chain, start, end, _ = bead_chain(pearls)
    d = (
        f"M {pts(*start)} " + chain +
        f"L {pts(93.6, 32.6)} L {pts(92.4, 45.4)} "                   # crown flank
        f"L {pts(91.4, 55.4)} "                                       # band
        f"L {pts(84.6, 57.6)} L {pts(83.4, 69)} "                     # collar right
        f"L {pts(75.6, 71.4)} "
        f"C {pts(78, 81, 82.6, 90, 96, 97.5)} "                       # stem right flare
        f"L {pts(CX + collar, COLLAR_T)} L {pts(CX + collar, 100.5)} "
        f"L {pts(CX + riser, RISER_T)} L {pts(CX + riser, 107.5)} "
        f"L {pts(CX + slab, SLAB_T)} L {pts(CX + slab, 114.6)} "
        f"Q {pts(CX + slab, GROUND, CX + slab - 4, GROUND)} "
        f"L {pts(CX - slab + 4, GROUND)} "
        f"Q {pts(CX - slab, GROUND, CX - slab, 114.6)} "
        f"L {pts(CX - slab, SLAB_T)} L {pts(CX - riser, 107.5)} "
        f"L {pts(CX - riser, RISER_T)} L {pts(CX - collar, 100.5)} "
        f"L {pts(CX - collar, COLLAR_T)} "
        f"L {pts(32, 97.5)} "
        f"C {pts(45.4, 90, 50, 81, 52.4, 71.4)} "                     # stem left flare
        f"L {pts(44.6, 69)} L {pts(43.4, 57.6)} "                     # collar left
        f"L {pts(36.6, 55.4)} L {pts(35.6, 45.4)} L {pts(34.4, 32.6)} Z"
    )
    lines = [
        f"M {pts(35.6, 45.4)} L {pts(92.4, 45.4)}",                   # crown meets the band
        f"M {pts(36.6, 55.4)} L {pts(91.4, 55.4)}",                   # band bottom
        f"M {pts(44.6, 69)} L {pts(83.4, 69)}",                       # collar bottom
    ] + plinth_lines(slab, riser, collar)
    shadow = (rake(73, 57) + slab_under(45.4, 3.4) + slab_under(55.4)
              + slab_under(69, 3.4) + PLINTH_SLABS)
    return dict(d=d, lines=lines, shadow=shadow)


def rook():
    slab, riser, collar = 50, 43, 36
    # three merlons, 18 / 9 / 18 / 9 / 18 across x 28..100, cut 24 deep
    d = (
        f"M {pts(28, 14)} "
        f"L {pts(46, 14)} L {pts(46, 38)} L {pts(55, 38)} L {pts(55, 14)} "
        f"L {pts(73, 14)} L {pts(73, 38)} L {pts(82, 38)} L {pts(82, 14)} "
        f"L {pts(100, 14)} L {pts(102.6, 38)} L {pts(102.6, 53.4)} "   # parapet corbels out
        f"L {pts(88.6, 58.6)} L {pts(86.4, 63.4)} "                    # neck
        f"C {pts(89.4, 75.4, 90.6, 86, 101.6, 97.5)} "                 # shaft + base flare
        f"L {pts(CX + collar, COLLAR_T)} L {pts(CX + collar, 100.5)} "
        f"L {pts(CX + riser, RISER_T)} L {pts(CX + riser, 107.5)} "
        f"L {pts(CX + slab, SLAB_T)} L {pts(CX + slab, 114.6)} "
        f"Q {pts(CX + slab, GROUND, CX + slab - 4, GROUND)} "
        f"L {pts(CX - slab + 4, GROUND)} "
        f"Q {pts(CX - slab, GROUND, CX - slab, 114.6)} "
        f"L {pts(CX - slab, SLAB_T)} L {pts(CX - riser, 107.5)} "
        f"L {pts(CX - riser, RISER_T)} L {pts(CX - collar, 100.5)} "
        f"L {pts(CX - collar, COLLAR_T)} "
        f"L {pts(26.4, 97.5)} "
        f"C {pts(37.4, 86, 38.6, 75.4, 41.6, 63.4)} "
        f"L {pts(39.4, 58.6)} L {pts(25.4, 53.4)} L {pts(25.4, 38)} Z"
    )
    lines = [
        f"M {pts(25.4, 38)} L {pts(102.6, 38)}",                       # crenellation floor
        f"M {pts(25.4, 53.4)} L {pts(102.6, 53.4)}",                   # parapet underside
        f"M {pts(39.4, 58.6)} L {pts(88.6, 58.6)}",                    # neck
    ] + plinth_lines(slab, riser, collar)
    # the rake is nudged so the cut never lands on a merlon centre line
    shadow = (rake(77.4, 58) + slab_under(38) + slab_under(53.4)
              + slab_under(58.6, 3.4) + PLINTH_SLABS)
    return dict(d=d, lines=lines, shadow=shadow)


def bishop():
    slab, riser, collar = 45, 38, 31
    # a tall almond mitre; the slit is a cut groove, not a hole, so it holds at 40px
    d = (
        f"M {pts(64, 29)} "
        f"C {pts(55, 32.6, 43.4, 47.4, 39.6, 64.4)} "                  # mitre left
        f"C {pts(38.6, 71.6, 40.6, 77, 44.6, 80)} "
        f"L {pts(43.4, 90.4)} L {pts(51.4, 92.6)} "                    # collar + chamfer
        f"C {pts(49.4, 94.6, 44, 96.4, 33, 97.5)} "                    # stem flare
        + plinth_left(slab, riser, collar)
        + plinth_right(slab, riser, collar)
        + f"C {pts(84, 96.4, 78.6, 94.6, 76.6, 92.6)} "
        f"L {pts(84.6, 90.4)} L {pts(83.4, 80)} "
        f"C {pts(87.4, 77, 89.4, 71.6, 88.4, 64.4)} "
        f"C {pts(84.6, 47.4, 73, 32.6, 64, 29)} Z"
    )
    lines = [
        f"M {pts(44.6, 80)} L {pts(83.4, 80)}",                        # collar top
        f"M {pts(43.4, 90.4)} L {pts(84.6, 90.4)}",                    # collar bottom
    ] + plinth_lines(slab, riser, collar)
    slit = f"M {pts(40.8, 66.6)} L {pts(67.4, 39.4)}"
    beads = [circle_path(64, 21.6, 8.6)]                               # ball finial
    shadow = (rake(72, 57) + slab_under(80) + slab_under(90.4, 3.4) + PLINTH_SLABS)
    return dict(d=d, lines=lines, beads=beads, shadow=shadow, slit=slit)


def pawn():
    slab, riser, collar = 39, 33, 26
    d = (
        f"M {pts(55.4, 40.4)} "
        f"C {pts(54.6, 45.4, 52.4, 48.6, 49, 50.6)} "                  # neck into the collar
        f"L {pts(47, 59)} L {pts(53.6, 61.4)} "
        f"C {pts(51.6, 75.4, 47.6, 89, 38, 97.5)} "                    # quiet taper
        + plinth_left(slab, riser, collar)
        + plinth_right(slab, riser, collar)
        + f"C {pts(80.4, 89, 76.4, 75.4, 74.4, 61.4)} "
        f"L {pts(81, 59)} L {pts(79, 50.6)} "
        f"C {pts(75.6, 48.6, 73.4, 45.4, 72.6, 40.4)} Z"
    )
    lines = [
        f"M {pts(49, 50.6)} L {pts(79, 50.6)}",                        # collar top
        f"M {pts(47, 59)} L {pts(81, 59)}",                            # collar bottom
    ] + plinth_lines(slab, riser, collar)
    beads = [circle_path(64, 30.4, 14)]                                # the head
    shadow = (rake(71, 58) + slab_under(50.6, 3.4) + slab_under(59) + PLINTH_SLABS)
    return dict(d=d, lines=lines, beads=beads, shadow=shadow)


def knight():
    slab, riser, collar = 48, 41, 35
    # A real horse in profile, facing left: ear, brow, dished face, muzzle,
    # jaw, throat, chest, mane crest, pedestal.
    d = (
        f"M {pts(72.6, 9)} "                                           # ear tip
        f"C {pts(77, 14.4, 80.4, 20, 81.6, 26)} "                      # back of the ear
        f"C {pts(91.6, 32, 99, 43, 102.4, 56)} "                       # mane crest
        f"C {pts(105.4, 68, 106, 81, 104, 92)} "                       # back of the neck
        f"L {pts(102.4, 97.5)} "
        f"L {pts(CX + collar, COLLAR_T)} L {pts(CX + collar, 100.5)} "
        f"L {pts(CX + riser, RISER_T)} L {pts(CX + riser, 107.5)} "
        f"L {pts(CX + slab, SLAB_T)} L {pts(CX + slab, 114.6)} "
        f"Q {pts(CX + slab, GROUND, CX + slab - 4, GROUND)} "
        f"L {pts(CX - slab + 4, GROUND)} "
        f"Q {pts(CX - slab, GROUND, CX - slab, 114.6)} "
        f"L {pts(CX - slab, SLAB_T)} L {pts(CX - riser, 107.5)} "
        f"L {pts(CX - riser, RISER_T)} L {pts(CX - collar, 100.5)} "
        f"L {pts(CX - collar, COLLAR_T)} "
        f"L {pts(25.6, 97.5)} "
        f"C {pts(27, 88.6, 32.4, 82, 41.6, 78)} "                      # chest
        f"C {pts(36.4, 71.4, 30.6, 67.4, 24.4, 65.4)} "                # throat up to the jaw
        f"C {pts(19.6, 66.6, 14.6, 65.4, 11, 62.4)} "                  # underside of the muzzle
        f"L {pts(8.4, 57)} L {pts(9.6, 46.6)} "                        # squared-off nose
        f"C {pts(21.6, 41.6, 33.6, 33.4, 44.4, 23)} "                  # the dish (concave)
        f"C {pts(48.6, 18.8, 53.6, 16.8, 59.6, 17)} "                  # brow
        f"C {pts(63.2, 15.4, 68, 12.4, 72.6, 9)} Z"                    # forehead into the ear
    )
    lines = [
        f"M {pts(70.6, 14.4)} C {pts(73.8, 17.6, 76, 21.6, 77.2, 25.6)}",   # ear inner
        f"M {pts(75.6, 30)} C {pts(80.4, 35.6, 84, 42, 86.2, 49.4)}",       # mane cut
        f"M {pts(83.4, 27.4)} C {pts(89, 34.6, 93.4, 43.6, 95.6, 53.6)}",   # mane cut
        f"M {pts(24.4, 65.4)} C {pts(34.4, 62.4, 41.4, 55.6, 45, 46.4)}",   # cheek / jaw
        f"M {pts(15.6, 53)} C {pts(17.8, 50.4, 21, 50.4, 22.8, 52.4)}",     # nostril
        f"M {pts(10.6, 59.6)} C {pts(15.4, 61.6, 20.6, 61.4, 24.2, 60)}",   # mouth
    ] + plinth_lines(slab, riser, collar)
    # the eye is a solid almond, so it survives 40px
    eye = (
        f"M {pts(46.6, 34)} "
        f"C {pts(50, 29.4, 54.8, 28, 57.4, 30.6)} "
        f"C {pts(59.6, 33, 57.2, 37.6, 52.8, 38.8)} "
        f"C {pts(48.8, 39.6, 45.4, 37.4, 46.6, 34)} Z"
    )
    shadow = (
        rake(79, 58)
        + f"M {pts(6, 61)} L {pts(45, 43)} L {pts(52, 82)} L {pts(6, 98)} Z "
        + PLINTH_SLABS
    )
    return dict(d=d, lines=lines, shadow=shadow, eye=eye)


PIECES = dict(K=king, Q=queen, R=rook, B=bishop, N=knight, P=pawn)


# ------------------------------------------------------------------ render ---
def svg_for(code, colour, size=128):
    p = PIECES[code]()
    c = WHITE if colour == "w" else BLACK
    uid = f"{colour}{code}"

    beads = p.get("beads", [])
    under = p.get("under", [])
    eye = p.get("eye")

    clip = " ".join([p["d"]] + beads + under)

    layers = []
    for u in under:                                  # spikes sit behind the body
        layers.append(
            f'<path d="{u}" fill="{c["body"]}" stroke="{c["line"]}" '
            f'stroke-width="{OUTER_W}" stroke-linejoin="round" stroke-linecap="round"/>'
        )
    layers.append(
        f'<path d="{p["d"]}" fill="{c["body"]}" stroke="{c["line"]}" '
        f'stroke-width="{OUTER_W}" stroke-linejoin="round" stroke-linecap="round"/>'
    )
    for b in beads:
        layers.append(
            f'<path d="{b}" fill="{c["body"]}" stroke="{c["line"]}" '
            f'stroke-width="{OUTER_W}" stroke-linejoin="round"/>'
        )

    restroke = [
        f'<path d="{p["d"]}" fill="none" stroke="{c["line"]}" stroke-width="{OUTER_W}" '
        f'stroke-linejoin="round" stroke-linecap="round"/>'
    ] + [
        f'<path d="{b}" fill="none" stroke="{c["line"]}" stroke-width="{OUTER_W}" '
        f'stroke-linejoin="round"/>' for b in beads
    ]

    structure = "".join(
        f'<path d="{ln}" fill="none" stroke="{c["detail"]}" stroke-width="{INNER_W}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>'
        for ln in p["lines"]
    )

    slit_el = ""
    if p.get("slit"):
        slit_el = (
            f'<path d="{p["slit"]}" fill="none" stroke="{c["detail"]}" stroke-width="4.2" '
            f'stroke-linecap="round"/>'
        )

    eye_el = ""
    if eye:
        eye_el = (
            f'<path d="{eye}" fill="{c["eye"]}" '
            f'stroke="{c["line"]}" stroke-width="1.4" stroke-linejoin="round"/>'
        )

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" '
        f'width="{size}" height="{size}">'
        f"<title>Plinth {uid}</title>"
        f"<desc>Plinth chess set © ChessEver LLC. Original geometry.</desc>"
        f'<defs><clipPath id="c{uid}"><path d="{clip}"/></clipPath></defs>'
        + "".join(layers)
        + f'<g clip-path="url(#c{uid})"><path d="{p["shadow"]}" fill="{c["shade"]}"/></g>'
        + "".join(restroke)
        + structure
        + slit_el
        + eye_el
        + "</svg>\n"
    )


def main():
    os.makedirs(OUT, exist_ok=True)
    for colour in ("w", "b"):
        for code in "KQRBNP":
            with open(os.path.join(OUT, f"{colour}{code}.svg"), "w") as fh:
                fh.write(svg_for(code, colour))
    print(f"wrote 12 svgs -> {OUT}")


if __name__ == "__main__":
    main()
