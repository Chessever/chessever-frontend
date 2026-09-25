import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart'
    show MoveClassFx;
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// How long after [ClassificationLanding.trigger] changes the effect starts,
/// by default: the analysis board moves pieces over 200 ms, and the effect
/// should meet the piece as it lands rather than wait at an empty square.
const Duration kClassificationLandingDelay = Duration(milliseconds: 150);

/// A short, distinct landing animation for a classified move, drawn on the
/// destination square over the board (place it in a Stack exactly covering
/// the board). Replays whenever [trigger] changes. Draws nothing when
/// [moveClass] is null: clearing it (or moving [square], or changing the
/// class) without a new [trigger] also cuts a landing that is running or
/// still waiting out its [delay], so a gesture never plays on a square the
/// board has already left.
///
/// Each class has its own gesture in the app's pixel-block language, in its
/// badge colour: brilliant bursts tiny squares out of the square, great and
/// best pulse a clean square ring, interesting sweeps a diagonal glint,
/// inaccuracy and mistake wobble a square tint, blunder hits a hard red flash
/// with a 3 px shake, missed win sinks away, book sweeps a page tint.
///
/// Driven by a motor spring (350–600 ms), always ends fully transparent,
/// never takes input ([IgnorePointer]) and draws nothing at all when the
/// platform asks for reduced motion.
class ClassificationLanding extends StatefulWidget {
  const ClassificationLanding({
    super.key,
    required this.square,
    required this.moveClass,
    required this.orientation,
    required this.trigger,
    this.delay = kClassificationLandingDelay,
    this.playOnMount = false,
  });

  final Square? square;
  final MoveClass? moveClass;

  /// Board orientation (which side is at the bottom).
  final Side orientation;

  /// Changes once per landing (e.g. the ply index or move id).
  final Object? trigger;

  /// Wait before the effect starts, so it meets the piece as it lands. Pass
  /// [Duration.zero] for boards that do not animate pieces.
  final Duration delay;

  /// Whether the first build already plays (a board that appears ON a
  /// classified move). Off by default: arriving at a position is not a
  /// landing.
  final bool playOnMount;

  /// The spring behind each class's gesture.
  static CupertinoMotion motionFor(MoveClass moveClass) =>
      CupertinoMotion.smooth(
        duration: _durationFor(moveClass),
        snapToEnd: true,
      );

  static Duration _durationFor(MoveClass moveClass) => switch (moveClass) {
    MoveClass.brilliant => const Duration(milliseconds: 600),
    MoveClass.great => const Duration(milliseconds: 480),
    MoveClass.best => const Duration(milliseconds: 420),
    MoveClass.interesting => const Duration(milliseconds: 460),
    MoveClass.inaccuracy => const Duration(milliseconds: 480),
    MoveClass.mistake => const Duration(milliseconds: 520),
    MoveClass.blunder => const Duration(milliseconds: 460),
    MoveClass.missedWin => const Duration(milliseconds: 600),
    MoveClass.book => const Duration(milliseconds: 420),
  };

  @override
  State<ClassificationLanding> createState() => _ClassificationLandingState();
}

class _ClassificationLandingState extends State<ClassificationLanding>
    with SingleTickerProviderStateMixin {
  /// 0 → 1 over one landing; 1 is also the resting (invisible) state.
  late final SingleMotionController _progress = SingleMotionController(
    motion: const CupertinoMotion.smooth(snapToEnd: true),
    vsync: this,
    initialValue: 1,
  );

  Timer? _delay;
  bool _reduceMotion = false;

  /// Latched when a landing starts. A rebuild that changes the square or
  /// class without a new trigger never repaints the running gesture elsewhere:
  /// [didUpdateWidget] cuts it instead.
  Square? _square;
  MoveClass? _moveClass;

  @override
  void initState() {
    super.initState();
    if (widget.playOnMount) {
      // After the first frame, once MediaQuery has been read.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _replay(rebuild: true);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion) _stop();
  }

  @override
  void didUpdateWidget(ClassificationLanding oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No setState here: a build follows didUpdateWidget anyway.
    if (widget.trigger != oldWidget.trigger) {
      _replay(rebuild: false);
    } else if ((_delay != null || _square != null) &&
        (widget.square == null ||
            widget.moveClass == null ||
            widget.square != oldWidget.square ||
            widget.moveClass != oldWidget.moveClass)) {
      // The board left the landed move (a step, a scrub, a take-back) without
      // a new landing: cut the running or pending gesture.
      _stop();
      _square = null;
      _moveClass = null;
    }
  }

  void _replay({required bool rebuild}) {
    _stop();
    final square = widget.square;
    final moveClass = widget.moveClass;
    if (square == null || moveClass == null || _reduceMotion) return;
    if (widget.delay <= Duration.zero) {
      _start(square, moveClass, rebuild: rebuild);
    } else {
      _delay = Timer(widget.delay, () {
        // Still the move this landing was queued for?
        if (!mounted ||
            widget.square != square ||
            widget.moveClass != moveClass) {
          _delay = null;
          return;
        }
        _start(square, moveClass, rebuild: true);
      });
    }
  }

  void _start(Square square, MoveClass moveClass, {required bool rebuild}) {
    _delay = null;
    if (!mounted || _reduceMotion) return;
    _progress.motion = ClassificationLanding.motionFor(moveClass);
    if (rebuild) {
      setState(() {
        _square = square;
        _moveClass = moveClass;
      });
    } else {
      _square = square;
      _moveClass = moveClass;
    }
    _progress.animateTo(1, from: 0);
  }

  void _stop() {
    _delay?.cancel();
    _delay = null;
    if (_progress.isAnimating) _progress.stop(canceled: true);
    _progress.value = 1;
  }

  @override
  void dispose() {
    _delay?.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final square = _square;
    final moveClass = _moveClass;
    if (square == null || moveClass == null || _reduceMotion) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: ClassificationLandingPainter(
            progress: _progress,
            square: square,
            moveClass: moveClass,
            orientation: widget.orientation,
          ),
        ),
      ),
    );
  }
}

/// Paints one frame of a landing. Public for tests and golden captures.
class ClassificationLandingPainter extends CustomPainter {
  ClassificationLandingPainter({
    required this.progress,
    required this.square,
    required this.moveClass,
    required this.orientation,
  }) : super(repaint: progress);

  /// 0 → 1; at (or within a hair of) 1 nothing is drawn.
  final Animation<double> progress;
  final Square square;
  final MoveClass moveClass;
  final Side orientation;

  /// From this progress on the landing counts as finished and draws nothing:
  /// a spring only asymptotes to its target.
  static const double _finished = 0.996;

  static const Color _white = Color(0xFFFFFFFF);

  /// book.svg's gradient bottom stop.
  static const Color _bookEdge = Color(0xFF4E4731);

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value.clamp(0.0, 1.0);
    if (p >= _finished) return;
    final side = math.min(size.width, size.height) / 8;
    if (side <= 0) return;
    final file = square.file;
    final rank = square.rank;
    final col = orientation == Side.white ? file : 7 - file;
    final row = orientation == Side.white ? 7 - rank : rank;
    final rect = Rect.fromLTWH(col * side, row * side, side, side);
    final color = moveClass.fxColor;
    switch (moveClass) {
      case MoveClass.brilliant:
        _burst(canvas, rect, color, p);
      case MoveClass.great:
        _pulse(canvas, rect, color, p, rings: 2, reach: 0.24);
      case MoveClass.best:
        _pulse(canvas, rect, color, p, rings: 1, reach: 0.16);
      case MoveClass.interesting:
        _glint(canvas, rect, color, p);
      case MoveClass.inaccuracy:
        _wobble(canvas, rect, color, p, turn: 0.07, strength: 0.8);
      case MoveClass.mistake:
        _wobble(canvas, rect, color, p, turn: 0.11, strength: 1, dip: true);
      case MoveClass.blunder:
        _flash(canvas, rect, color, p);
      case MoveClass.missedWin:
        _sink(canvas, rect, color, p);
      case MoveClass.book:
        _pageSweep(canvas, rect, color, p);
    }
  }

  // --- shared -------------------------------------------------------------

  static Paint _fill(Color color, double alpha) =>
      Paint()..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));

  static Paint _stroke(Color color, double alpha, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));

  /// One pixel block: a small square with the 1 px corner of the design's
  /// pixel runs, snapped to the square's pixel grid.
  static void _block(
    Canvas canvas,
    Offset center,
    double blockSide,
    double unit,
    Paint paint,
  ) {
    final snapped = Offset(
      (center.dx / unit).roundToDouble() * unit,
      (center.dy / unit).roundToDouble() * unit,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: snapped, width: blockSide, height: blockSide),
        const Radius.circular(1),
      ),
      paint,
    );
  }

  /// 1 → 0 over the last part of the run, after [holdUntil].
  static double _fadeAfter(double p, double holdUntil) =>
      p <= holdUntil ? 1 : 1 - (p - holdUntil) / (1 - holdUntil);

  // --- gestures -------------------------------------------------------------

  /// !!: a crisp burst of tiny squares expanding out of the square.
  void _burst(Canvas canvas, Rect rect, Color color, double p) {
    final side = rect.width;
    final unit = side / 16;
    final flash = math.pow(1 - p, 2.2).toDouble();
    canvas.drawRect(rect, _fill(color, 0.30 * flash));

    final light = Color.lerp(color, _white, 0.55)!;
    final fade = _fadeAfter(p, 0.5);
    const count = 12;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi + math.pi / count;
      final far = i.isEven ? 0.62 : 0.44;
      final distance = side * (0.34 + far * p);
      final center =
          rect.center +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance);
      final blockSide = unit * (i % 3 == 0 ? 2.0 : 1.5) * (1 - 0.35 * p);
      _block(
        canvas,
        center,
        blockSide,
        unit,
        _fill(i % 4 == 0 ? light : color, fade),
      );
    }
  }

  /// ! and best: a clean square ring pulsing out of the square's edge.
  void _pulse(
    Canvas canvas,
    Rect rect,
    Color color,
    double p, {
    required int rings,
    required double reach,
  }) {
    final side = rect.width;
    canvas.drawRect(rect, _fill(color, 0.22 * math.pow(1 - p, 2)));
    for (var k = 0; k < rings; k++) {
      final lag = 0.2 * k;
      final q = ((p - lag) / (1 - lag)).clamp(0.0, 1.0);
      if (q <= 0) continue;
      final width = math.max(2.0, side * 0.07) * (1 - 0.45 * q);
      final ring = rect.inflate(side * (-0.06 + reach * q));
      canvas.drawRRect(
        RRect.fromRectAndRadius(ring, const Radius.circular(2)),
        _stroke(color, 0.95 * math.pow(1 - q, 1.3), width),
      );
    }
  }

  /// !?: a quick diagonal glint across the square, with two pixel sparks at
  /// the far corner as it passes.
  void _glint(Canvas canvas, Rect rect, Color color, double p) {
    final side = rect.width;
    final unit = side / 16;
    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.left, rect.top);
    canvas.drawRect(
      Offset.zero & rect.size,
      _fill(color, 0.2 * math.pow(1 - p, 1.5)),
    );
    // The band runs along "/" and travels from the top-left corner to the
    // bottom-right one: points with x + y between a and b.
    final band = side * 0.32;
    final a = -band + (2 * side + band) * p;
    final b = a + band;
    final path = Path()
      ..moveTo(a + side, -side)
      ..lineTo(b + side, -side)
      ..lineTo(b - 2 * side, 2 * side)
      ..lineTo(a - 2 * side, 2 * side)
      ..close();
    // The band carries the colour (so it reads on light squares), its core
    // the glint (so it reads on dark ones).
    canvas.drawPath(
      path,
      _fill(Color.lerp(color, _white, 0.15)!, 0.5 * (1 - p)),
    );
    final core = side * 0.07;
    final c0 = (a + b) / 2 - core / 2;
    final c1 = c0 + core;
    canvas.drawPath(
      Path()
        ..moveTo(c0 + side, -side)
        ..lineTo(c1 + side, -side)
        ..lineTo(c1 - 2 * side, 2 * side)
        ..lineTo(c0 - 2 * side, 2 * side)
        ..close(),
      _fill(_white, 0.6 * (1 - p)),
    );
    canvas.restore();

    final spark = math.sin(((p - 0.35) / 0.65).clamp(0.0, 1.0) * math.pi);
    if (spark > 0) {
      final paint = _fill(color, spark);
      _block(
        canvas,
        rect.topRight + Offset(unit * 1, -unit * 1),
        unit * 1.5,
        unit,
        paint,
      );
      _block(
        canvas,
        rect.topRight + Offset(unit * 3, -unit * 3),
        unit * 1.5,
        unit,
        paint,
      );
    }
  }

  /// ?! and ?: a square tint that wobbles and settles as it fades. The
  /// mistake also dips a pixel, the "uh-oh".
  void _wobble(
    Canvas canvas,
    Rect rect,
    Color color,
    double p, {
    required double turn,
    required double strength,
    bool dip = false,
  }) {
    final side = rect.width;
    final unit = side / 16;
    final decay = 1 - p;
    final angle = turn * math.sin(p * 3 * math.pi) * decay;
    final drop = dip ? unit * math.sin(p * math.pi) : 0.0;
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy + drop);
    canvas.rotate(angle);
    final tile = Rect.fromCenter(
      center: Offset.zero,
      width: side * 0.9,
      height: side * 0.9,
    );
    canvas.drawRect(tile, _fill(color, 0.36 * strength * math.pow(decay, 1.2)));
    canvas.drawRRect(
      RRect.fromRectAndRadius(tile, const Radius.circular(2)),
      _stroke(color, 0.85 * strength * decay, math.max(2.0, side * 0.05)),
    );
    canvas.restore();
  }

  /// ??: a hard red flash — full strength on the first frame, no fade-in —
  /// with a 3 px horizontal shake that dies out.
  void _flash(Canvas canvas, Rect rect, Color color, double p) {
    final side = rect.width;
    final shake = 3.0 * math.sin(p * 7 * math.pi) * (1 - p);
    final shaken = rect.shift(Offset(shake, 0));
    canvas.drawRect(shaken, _fill(color, 0.55 * math.pow(1 - p, 1.6)));
    canvas.drawRect(
      shaken.deflate(side * 0.035),
      _stroke(color, 0.95 * (1 - p), math.max(2.0, side * 0.07)),
    );
  }

  /// Missed win: the tint drains down out of the square, trailing three
  /// pixel blocks from its falling edge.
  void _sink(Canvas canvas, Rect rect, Color color, double p) {
    final side = rect.width;
    final unit = side / 16;
    final alpha = 1 - p;
    final top = rect.top + side * p;
    canvas.drawRect(
      Rect.fromLTRB(rect.left, top, rect.right, rect.bottom),
      _fill(color, 0.42 * alpha),
    );
    final blocks = _fill(color, 0.9 * alpha);
    for (var i = 0; i < 3; i++) {
      final x = rect.left + side * (0.28 + 0.22 * i);
      final y = top - unit * (1.5 + (i.isOdd ? 1.5 : 0)) + unit * 2 * p;
      _block(canvas, Offset(x, y), unit * 1.5, unit, blocks);
    }
  }

  /// Book: a soft page-tint sweeping left to right across the square, led by
  /// a lighter page edge.
  void _pageSweep(Canvas canvas, Rect rect, Color color, double p) {
    final side = rect.width;
    final unit = side / 16;
    final presence = math.sin(p * math.pi);
    final lead = rect.left + side * (1.25 * p);
    final band = side * 0.4;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(
      Rect.fromLTRB(lead - band, rect.top, lead, rect.bottom),
      _fill(color, 0.42 * presence),
    );
    // The page edge: the badge's deep bottom tone, so it reads on a light
    // square as well as a dark one.
    canvas.drawRect(
      Rect.fromLTRB(
        lead - math.max(1.5, unit * 0.6),
        rect.top,
        lead,
        rect.bottom,
      ),
      _fill(_bookEdge, 0.6 * presence),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(ClassificationLandingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.square != square ||
      oldDelegate.moveClass != moveClass ||
      oldDelegate.orientation != orientation;
}
