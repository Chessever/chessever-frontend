import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// The ChessEver mark, drawn instead of decoded: the four corner squares
/// round the centre cell that holds the king, as in
/// `assets/pngs/chessever-mark.png` (the paywall's hero, and
/// `PngAsset.premiumIcon`). Drawn, its corner squares can move.
///
/// Measured from the 418 px asset and evened out, in a unit box: corner
/// squares a third of the box, rounded 2.8% on their outer corners; a centre
/// cell 37% wide that runs under them; the joint between the two filleted,
/// as the asset is.
abstract final class _Mark {
  /// A corner square's side.
  static const double corner = 1 / 3;

  /// The centre cell's near and far edges.
  static const double centreNear = 0.315;
  static const double centreFar = 1 - centreNear;

  /// How far a corner square runs over the centre cell at rest.
  static const double overlap = corner - centreNear;

  static const Color cyan = Color(0xFF0FB4E5);

  /// The king, traced from the asset (its own 418 px box, normalised).
  static final Path king = () {
    const points = [
      (0.4923, 0.3589),
      (0.5048, 0.3579),
      (0.5072, 0.3669),
      (0.5159, 0.3708),
      (0.5171, 0.3756),
      (0.5160, 0.3780),
      (0.5062, 0.3828),
      (0.5061, 0.3900),
      (0.5077, 0.3923),
      (0.5191, 0.3982),
      (0.5359, 0.4037),
      (0.5406, 0.4067),
      (0.5439, 0.4115),
      (0.5440, 0.4187),
      (0.5414, 0.4282),
      (0.5299, 0.4521),
      (0.5253, 0.4665),
      (0.5263, 0.4698),
      (0.5359, 0.4737),
      (0.5392, 0.4785),
      (0.5392, 0.4833),
      (0.5359, 0.4886),
      (0.5238, 0.4928),
      (0.5236, 0.5120),
      (0.5255, 0.5311),
      (0.5332, 0.5574),
      (0.5484, 0.5861),
      (0.5493, 0.5933),
      (0.5651, 0.6100),
      (0.5670, 0.6161),
      (0.5658, 0.6244),
      (0.5598, 0.6316),
      (0.4426, 0.6326),
      (0.4341, 0.6292),
      (0.4289, 0.6196),
      (0.4302, 0.6124),
      (0.4329, 0.6077),
      (0.4462, 0.5933),
      (0.4473, 0.5837),
      (0.4582, 0.5646),
      (0.4673, 0.5431),
      (0.4721, 0.5191),
      (0.4728, 0.4928),
      (0.4614, 0.4880),
      (0.4579, 0.4809),
      (0.4607, 0.4737),
      (0.4713, 0.4699),
      (0.4725, 0.4665),
      (0.4672, 0.4498),
      (0.4542, 0.4210),
      (0.4535, 0.4115),
      (0.4561, 0.4067),
      (0.4595, 0.4043),
      (0.4908, 0.3923),
      (0.4919, 0.3828),
      (0.4904, 0.3809),
      (0.4833, 0.3789),
      (0.4807, 0.3732),
      (0.4833, 0.3700),
      (0.4914, 0.3660),
    ];
    final path = Path()..moveTo(points.first.$1, points.first.$2);
    for (final (x, y) in points.skip(1)) {
      path.lineTo(x, y);
    }
    return path..close();
  }();

  /// The full mark's corner rounding and joint fillets, in its box.
  static const double markRadius = 0.028;
  static const double markFillet = 0.024;

  /// The choice icon's: softer, as the full mark's 2.8% corner reads as
  /// sharp at 16 pt.
  static const double iconRadius = 0.065;
  static const double iconFillet = 0.05;

  /// The two outlines at rest, built once: the union below costs a dozen
  /// path operations, and a spinner beside a mark repaints it every frame.
  static final Path markAtRest = squares(
    spread: 0,
    radius: markRadius,
    fillet: markFillet,
  );
  static final Path iconAtRest = squares(
    spread: 0,
    radius: iconRadius,
    fillet: iconFillet,
  );

  /// The mark's squares in a unit box, as one outline. [spread] moves each
  /// corner square out along its diagonal (under 0 draws them in over the
  /// centre); [radius] rounds their outer corners and [fillet] the joints.
  ///
  /// One path, unioned, drawn once: shapes painted one by one leave a
  /// faint antialiased seam wherever two of their edges meet. Only a moving
  /// mark builds one; at rest it draws [markAtRest] or [iconAtRest].
  static Path squares({
    required double spread,
    required double radius,
    required double fillet,
  }) {
    var path = Path()
      ..addRect(
        const Rect.fromLTRB(centreNear, centreNear, centreFar, centreFar),
      );
    void add(Path piece) =>
        path = Path.combine(PathOperation.union, path, piece);
    // A corner square's inner corner hides under the centre cell while the
    // two overlap; parted from it, it rounds like the others.
    final apart = (spread / overlap).clamp(0.0, 1.0);
    final inner = Radius.circular(radius * apart);
    final outer = Radius.circular(radius);
    // The joints' fillets shrink to nothing as the squares part. Drawn in,
    // two neighbours leave a narrow notch over the centre cell: its two
    // fillets meet in a round bottom, never overlap into a bump.
    final notch = 1 - 2 * corner + 2 * spread;
    final joint = math.max(0.0, math.min(fillet * (1 - apart), notch / 2));
    for (final sx in const [-1.0, 1.0]) {
      for (final sy in const [-1.0, 1.0]) {
        final left = sx < 0 ? 0.0 : 1 - corner;
        final top = sy < 0 ? 0.0 : 1 - corner;
        final square = Rect.fromLTWH(
          left + sx * spread,
          top + sy * spread,
          corner,
          corner,
        );
        // The corner facing the centre is the inner one.
        add(
          Path()..addRRect(
            RRect.fromRectAndCorners(
              square,
              topLeft: sx > 0 && sy > 0 ? inner : outer,
              topRight: sx < 0 && sy > 0 ? inner : outer,
              bottomLeft: sx > 0 && sy < 0 ? inner : outer,
              bottomRight: sx < 0 && sy < 0 ? inner : outer,
            ),
          ),
        );
        if (joint <= 0) continue;
        // The square's two edges that meet the centre cell, and the centre
        // cell's two edges they meet: two concave corners per joint.
        final edgeX = sx < 0 ? square.right : square.left;
        final edgeY = sy < 0 ? square.bottom : square.top;
        final centreX = sx < 0 ? centreNear : centreFar;
        final centreY = sy < 0 ? centreNear : centreFar;
        add(
          _fillet(Offset(edgeX, centreY), Offset(-sx, 0), Offset(0, sy), joint),
        );
        add(
          _fillet(Offset(centreX, edgeY), Offset(0, -sy), Offset(sx, 0), joint),
        );
      }
    }
    return path;
  }

  /// The fillet of radius [r] in the concave corner at [p], whose two edges
  /// run along [u] and [v] (each edge's shape lies on the far side of the
  /// other direction). It reaches a hair into both shapes, so the union
  /// has no edge to meet exactly.
  static Path _fillet(Offset p, Offset u, Offset v, double r) {
    const into = 0.004;
    final a = p - u * into - v * into;
    final b = p + u * r - v * into;
    final c = p + u * r;
    final d = p + v * r;
    final e = p + v * r - u * into;
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      // A conic of weight cos 45° through the corner: an exact quarter
      // circle tangent to both edges.
      ..conicTo(p.dx, p.dy, d.dx, d.dy, math.sqrt1_2)
      ..lineTo(e.dx, e.dy)
      ..close();
  }
}

/// The premium moment's mark: the ChessEver mark in full colour, bare on
/// the popup's glass.
///
/// It opens assembled from a breath apart: the corner squares start a few
/// points out along their diagonals and spring in round the king, landing
/// with a little give. On screen from its first frame (only the squares'
/// places move), and still under reduced motion.
class PremiumMark extends StatelessWidget {
  const PremiumMark({super.key, this.size = 56});

  final double size;

  /// How far apart the corner squares open, in the mark's box.
  static const double openSpread = 0.075;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SingleMotionBuilder(
        motion: const _AssembleSpring(),
        value: 0.0,
        from: still ? null : 1.0,
        active: !still,
        builder: (context, open, _) => CustomPaint(
          size: Size.square(size),
          painter: _PremiumMarkPainter(spread: open * openSpread),
        ),
      ),
    );
  }
}

class _PremiumMarkPainter extends CustomPainter {
  const _PremiumMarkPainter({required this.spread});

  final double spread;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width, size.height);
    canvas
      ..drawPath(
        spread == 0
            ? _Mark.markAtRest
            : _Mark.squares(
                spread: spread,
                radius: _Mark.markRadius,
                fillet: _Mark.markFillet,
              ),
        Paint()..color = _Mark.cyan,
      )
      ..drawPath(_Mark.king, Paint()..color = const Color(0xFF000000))
      ..restore();
  }

  @override
  bool shouldRepaint(_PremiumMarkPainter oldDelegate) =>
      oldDelegate.spread != spread;
}

/// The marks a Premium choice wears, one family: solid geometric shapes
/// with softened corners. Each is drawn to its own ink box, 16 pt tall and
/// as wide as its shape, so nothing it draws hangs outside its box: a
/// choice's mark then sits a measured gap from its label, and the pair
/// centres on its plate by what is drawn.
enum ChoiceGlyph {
  /// The ChessEver mark's squares (no king at this size): Upgrade.
  premium(Size(16, 16)),

  /// A play triangle, as tall as the mark and a little narrower, so the two
  /// weigh the same: Watch ad.
  play(Size(14, 16)),

  /// A turning arrow: retry a reward's confirmation.
  retry(Size(15.8, 16));

  const ChoiceGlyph(this.size);

  /// The glyph's ink box, in points.
  final Size size;
}

/// A [ChoiceGlyph] in [color], at its [ChoiceGlyph.size].
///
/// [press] is the choice's press (0 at rest, 1 fully pressed): under it the
/// premium mark's corner squares close in round the centre, 2.4 pt at a
/// full press. A new [burst] count, given as a tap lands, kicks them apart
/// again: they spring out a point past rest and settle back together, the
/// way the big mark assembles as the popup opens. Neither moves under
/// reduced motion.
class ChoiceGlyphIcon extends StatefulWidget {
  const ChoiceGlyphIcon(
    this.glyph, {
    super.key,
    required this.color,
    this.press = 0,
    this.burst = 0,
  });

  final ChoiceGlyph glyph;
  final Color color;
  final double press;
  final int burst;

  @override
  State<ChoiceGlyphIcon> createState() => _ChoiceGlyphIconState();
}

class _ChoiceGlyphIconState extends State<ChoiceGlyphIcon>
    with SingleTickerProviderStateMixin {
  /// The burst, in presses (above 0 the squares stand apart). Made on the
  /// first burst, so a mark that never bursts holds no ticker.
  SingleMotionController? _kick;
  bool _still = false;

  /// The kick, in presses a second. Given as the finger lifts from a full
  /// press, it carries the squares about a point past rest (half a press
  /// the other way) some 160 ms later; on the mark's assemble spring they
  /// are back together within half a second.
  static const double _kickVelocity = 20;

  @override
  void didUpdateWidget(ChoiceGlyphIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.burst == oldWidget.burst ||
        widget.glyph != ChoiceGlyph.premium ||
        _still) {
      return;
    }
    final kick = _kick ??= SingleMotionController(
      motion: const _AssembleSpring(),
      vsync: this,
    );
    unawaited(kick.animateTo(0, withVelocity: _kickVelocity));
  }

  @override
  void dispose() {
    _kick?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _still = MediaQuery.disableAnimationsOf(context);
    return CustomPaint(
      size: widget.glyph.size,
      painter: _ChoiceGlyphPainter(
        glyph: widget.glyph,
        color: widget.color,
        press: widget.press,
        kick: _kick,
      ),
    );
  }
}

class _ChoiceGlyphPainter extends CustomPainter {
  _ChoiceGlyphPainter({
    required this.glyph,
    required this.color,
    required this.press,
    this.kick,
  }) : super(repaint: kick);

  final ChoiceGlyph glyph;
  final Color color;
  final double press;
  final Animation<double>? kick;

  /// How far the premium mark's corners close in at a full press, in its
  /// box: 2.4 pt at 16 pt, so a tap (pressed some 90%) visibly draws them
  /// in under the finger.
  static const double _squeeze = 0.15;

  /// The play triangle in its 14 x 16 box: its corners rounded 1.6 pt, the
  /// polygon set so the rounded ink fills the box exactly (the flat side on
  /// its left edge, the rounded tip on its right).
  static final Path _play = _roundedPolygon(const [
    Offset(0, -1.208),
    Offset(15.538, 8),
    Offset(0, 17.208),
  ], 1.6);

  /// The turning arrow, drawn on a 20-unit grid: a ring of radius 5.9
  /// round (10, 10.6), three quarters of a turn from the right of the top,
  /// its arrowhead at the upper left. Its ink spans [_retryInk] there,
  /// scaled to the glyph's 16 pt height.
  static const Offset _retryCentre = Offset(10, 10.6);
  static const double _retryRadius = 5.9;
  static const double _retryStart = -math.pi / 6;
  static const double _retrySweep = math.pi * 1.5;
  static const Rect _retryInk = Rect.fromLTRB(2.9, 3.32, 17.1, 17.7);
  static final Path _retryHead = () {
    const end = _retryStart + _retrySweep;
    final tip =
        _retryCentre + Offset(math.cos(end), math.sin(end)) * _retryRadius;
    // Clockwise along the circle, and out from it.
    final along = Offset(-math.sin(end), math.cos(end));
    final out = Offset(math.cos(end), math.sin(end));
    return _roundedPolygon([
      tip + along * 3.6,
      tip - along * 1.2 + out * 3.4,
      tip - along * 1.2 - out * 3.4,
    ], 1.0);
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    switch (glyph) {
      case ChoiceGlyph.premium:
        // The press draws the squares in; the burst (a negative press)
        // parts them.
        final p = press - (kick?.value ?? 0);
        canvas
          ..save()
          ..scale(size.width, size.height)
          ..drawPath(
            p.abs() < 1e-3
                ? _Mark.iconAtRest
                : _Mark.squares(
                    spread: -_squeeze * p,
                    radius: _Mark.iconRadius,
                    fillet: _Mark.iconFillet,
                  ),
            paint,
          )
          ..restore();
      case ChoiceGlyph.play:
        canvas.drawPath(_play, paint);
      case ChoiceGlyph.retry:
        final scale = size.height / _retryInk.height;
        canvas
          ..save()
          ..scale(scale)
          ..translate(-_retryInk.left, -_retryInk.top)
          ..drawArc(
            Rect.fromCircle(center: _retryCentre, radius: _retryRadius),
            _retryStart,
            _retrySweep,
            false,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4
              ..strokeCap = StrokeCap.round,
          )
          ..drawPath(_retryHead, paint)
          ..restore();
    }
  }

  @override
  bool shouldRepaint(_ChoiceGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.press != press ||
      oldDelegate.kick != kick;
}

/// A convex polygon through [points] with every corner rounded to [radius]
/// (exact circular arcs, drawn as conics).
Path _roundedPolygon(List<Offset> points, double radius) {
  final path = Path();
  final n = points.length;
  for (var i = 0; i < n; i++) {
    final previous = points[(i - 1 + n) % n];
    final corner = points[i];
    final next = points[(i + 1) % n];
    final toPrevious = previous - corner;
    final toNext = next - corner;
    final a = toPrevious / toPrevious.distance;
    final b = toNext / toNext.distance;
    // The corner's angle, and how far along each edge its arc starts.
    final angle = math.acos((a.dx * b.dx + a.dy * b.dy).clamp(-1.0, 1.0));
    final cut = radius / math.tan(angle / 2);
    final from = corner + a * cut;
    final to = corner + b * cut;
    if (i == 0) {
      path.moveTo(from.dx, from.dy);
    } else {
      path.lineTo(from.dx, from.dy);
    }
    path.conicTo(corner.dx, corner.dy, to.dx, to.dy, math.sin(angle / 2));
  }
  return path..close();
}

/// The mark's assemble, and the Upgrade icon's burst back together: the
/// alert modal's bouncy spring, let go once it is within a hair of rest (a
/// hundredth of a point at the mark's size) and set exactly on its target,
/// so the open is not held a second longer for motion nobody can see.
class _AssembleSpring extends Motion {
  const _AssembleSpring()
    : super(tolerance: const Tolerance(distance: 0.003, velocity: 0.05));

  static const _spring = CupertinoMotion.bouncy(
    duration: Duration(milliseconds: 520),
  );

  @override
  bool get needsSettle => true;

  @override
  bool get unboundedWillSettle => false;

  @override
  Simulation createSimulation({
    double start = 0,
    double end = 1,
    double velocity = 0,
  }) => SpringSimulation(
    _spring.description,
    start,
    end,
    velocity,
    tolerance: tolerance,
    snapToEnd: true,
  );

  @override
  bool operator ==(Object other) => other is _AssembleSpring;

  @override
  int get hashCode => (_AssembleSpring).hashCode;
}
