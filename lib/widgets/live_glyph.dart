import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The live mark: a solid dot broadcasting, with two arcs of signal leaving
/// it on either side, the sign a reader already knows from every radio,
/// stream and "on air" light.
///
/// Drawn on a 24 grid in the floating glyphs' language: one even stroke with
/// round caps and every arc spaced so dot, gap, arc, gap, arc read at one
/// rhythm. The figure is
/// symmetric about both axes through its box's centre, so the box centre is
/// its optical centre too and it sits dead centre in any disc.
///
/// The dot and the arcs take their own colours, so the dot can carry the
/// app's live colour while the arcs stay in the ink around them. [spread]
/// pushes the arcs outward (0 at rest, 1 the full push), the signal leaving
/// the dot; the figure at 0 is the mark.
class LiveGlyph extends StatelessWidget {
  const LiveGlyph({
    super.key,
    required this.size,
    required this.dotColor,
    required this.waveColor,
    this.spread = 0,
  });

  /// The square the mark is drawn in.
  final double size;
  final Color dotColor;
  final Color waveColor;
  final double spread;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: LiveGlyphPainter(
        dotColor: dotColor,
        waveColor: waveColor,
        spread: spread,
      ),
    ),
  );
}

/// Paints [LiveGlyph] into the largest square centred in its box.
class LiveGlyphPainter extends CustomPainter {
  const LiveGlyphPainter({
    required this.dotColor,
    required this.waveColor,
    this.spread = 0,
  });

  final Color dotColor;
  final Color waveColor;
  final double spread;

  /// The grid the figure is drawn on.
  static const double grid = 24;

  /// The arcs' stroke: between the field's magnifier and Material's
  /// rounded glyphs, the two weights it sits beside in a stack.
  static const double stroke = 2.4;

  /// The dot and the arcs, stepping out from the centre at one rhythm: the
  /// dot to 2.9, a 2.0 gap, the inner arc (4.9 to 7.3), a 2.0 gap, the outer
  /// arc (9.3 to 11.7), its rim a hair inside the grid. A short wide figure,
  /// so it takes the grid's width to carry the weight of a square glyph.
  static const double dotRadius = 2.9;
  static const double innerRadius = 6.1;
  static const double outerRadius = 10.5;

  /// Half of each arc's sweep, either side of the horizontal. Wide enough to
  /// read as a wave at a glance, short enough that the arcs stay arcs and
  /// never close into rings around the dot. Both arcs share it, so their
  /// round ends line up on one ray from the dot.
  static const double halfSweep = 50 * math.pi / 180;

  /// How far each arc moves out at the full [spread], in grid units: the
  /// outer one twice the inner, as a wave travelling away. The outer rim
  /// then reaches 12.4, still well inside any disc the mark is drawn on.
  static const double innerPush = 0.35;
  static const double outerPush = 0.7;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / grid;
    final centre = size.center(Offset.zero);
    final push = spread.clamp(0.0, 1.0);
    canvas.drawCircle(centre, dotRadius * unit, Paint()..color = dotColor);
    final pen = Paint()
      ..color = waveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * unit
      ..strokeCap = StrokeCap.round;
    for (final radius in [
      innerRadius + innerPush * push,
      outerRadius + outerPush * push,
    ]) {
      final rect = Rect.fromCircle(center: centre, radius: radius * unit);
      // Right, then left: the same arc mirrored through the dot.
      for (final facing in const [0.0, math.pi]) {
        canvas.drawArc(rect, facing - halfSweep, halfSweep * 2, false, pen);
      }
    }
  }

  @override
  bool shouldRepaint(LiveGlyphPainter old) =>
      old.dotColor != dotColor ||
      old.waveColor != waveColor ||
      old.spread != spread;
}
