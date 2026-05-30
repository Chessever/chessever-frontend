import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Holds the set of in-flight heart bursts spawned by double-taps / toolbar
/// likes on the board. The board hosts a single [HeartBurstLayer] bound to one
/// of these and calls [spawn] at the tap point.
class HeartBurstController extends ChangeNotifier {
  final List<HeartBurstSpec> _bursts = [];
  int _seq = 0;

  List<HeartBurstSpec> get bursts => List.unmodifiable(_bursts);

  /// Spawns a heart at [position] (local coordinates within the layer).
  /// [isUnlike] plays the shatter animation instead of the like burst.
  /// [onFinished] fires when this specific burst's animation completes —
  /// used by the board to chain the inbound-flight overlay.
  void spawn({
    required Offset position,
    bool isUnlike = false,
    VoidCallback? onFinished,
  }) {
    _bursts.add(
      HeartBurstSpec(
        id: _seq++,
        position: position,
        isUnlike: isUnlike,
        onFinished: onFinished,
      ),
    );
    notifyListeners();
  }

  void _remove(int id) {
    final i = _bursts.indexWhere((b) => b.id == id);
    if (i < 0) return;
    final cb = _bursts[i].onFinished;
    _bursts.removeAt(i);
    notifyListeners();
    cb?.call();
  }
}

class HeartBurstSpec {
  const HeartBurstSpec({
    required this.id,
    required this.position,
    required this.isUnlike,
    this.onFinished,
  });

  final int id;
  final Offset position;
  final bool isUnlike;
  final VoidCallback? onFinished;
}

/// Renders all active bursts from a [HeartBurstController] over the board.
/// Place inside the board [Stack] as `Positioned.fill(child: HeartBurstLayer(...))`.
class HeartBurstLayer extends StatelessWidget {
  const HeartBurstLayer({
    super.key,
    required this.controller,
    required this.color,
    this.reduceMotion = false,
    this.heartSize,
  });

  final HeartBurstController controller;
  final Color color;
  final bool reduceMotion;

  /// Override heart size. When null, sizes to ~50% of the layer's shortest
  /// side — Instagram-style dominance over the frame.
  final double? heartSize;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = heartSize ??
              constraints.biggest.shortestSide.clamp(160.0, 480.0) * 0.55;
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final bursts = controller.bursts;
              if (bursts.isEmpty) return const SizedBox.shrink();
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final b in bursts)
                    Positioned(
                      // Bursts are FAT — give them 2× canvas room around the
                      // tap point so glow ring + sparkles never clip.
                      left: b.position.dx - size,
                      top: b.position.dy - size,
                      width: size * 2,
                      height: size * 2,
                      child: HeartBurst(
                        key: ValueKey(b.id),
                        color: color,
                        isUnlike: b.isUnlike,
                        reduceMotion: reduceMotion,
                        heartSize: size,
                        onComplete: () => controller._remove(b.id),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Multi-stage heart effect: a chained sequence layered for richness.
///
/// Like burst:
///   1. Heart pop-in (underdamped spring → natural overshoot ~1.15).
///   2. Radial glow ring expanding + fading behind it.
///   3. 6 small "sparkle" mini-hearts shooting outward in different directions.
///   4. Main heart drifts up and fades out.
///
/// Unlike burst (chained too):
///   1. Heart appears full-size.
///   2. Quick wobble (spring-driven shake).
///   3. Splits into two halves that rotate apart and fall under gravity.
///   4. Halves fade.
///
/// Reduce-motion: a brief opacity fill, no scale/drift.
class HeartBurst extends StatefulWidget {
  const HeartBurst({
    super.key,
    required this.color,
    required this.onComplete,
    required this.heartSize,
    this.isUnlike = false,
    this.reduceMotion = false,
  });

  final Color color;
  final VoidCallback onComplete;
  final double heartSize;
  final bool isUnlike;
  final bool reduceMotion;

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<HeartBurst>
    with TickerProviderStateMixin {
  /// Spring-driven scale for the initial pop.
  late final AnimationController _pop;
  Animation<double>? _wobbleAnim;

  /// Envelope: opacity, drift, glow ring, sparkles, shatter rotation.
  late final AnimationController _env;
  late Animation<double> _opacity;
  late Animation<double> _drift;
  late Animation<double> _ringT; // 0→1 expansion + fade of glow ring
  late Animation<double> _sparkleT; // 0→1 sparkle outward fly + fade
  late Animation<double> _shatterT; // 0→1 split-apart for unlike

  final math.Random _rng = math.Random();
  late final List<_Sparkle> _sparkles;

  bool _useSpringScale = true;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController.unbounded(vsync: this);
    _env = AnimationController(vsync: this);
    _sparkles = List.generate(6, (i) {
      // Six sparkles fan out in roughly even directions with small jitter.
      final base = (i / 6) * 2 * math.pi;
      final jitter = (_rng.nextDouble() - 0.5) * 0.6;
      return _Sparkle(
        angle: base + jitter,
        distance: widget.heartSize * (0.55 + _rng.nextDouble() * 0.25),
        size: widget.heartSize * (0.12 + _rng.nextDouble() * 0.05),
        startDelay: _rng.nextDouble() * 0.15,
      );
    });

    if (widget.reduceMotion) {
      _runReduced();
    } else if (widget.isUnlike) {
      _runUnlike();
    } else {
      _runLike();
    }
  }

  void _finish() {
    if (_completed || !mounted) return;
    _completed = true;
    widget.onComplete();
  }

  // ---------------------------------------------------------------------------
  // LIKE
  // ---------------------------------------------------------------------------
  //
  // No drift, no fade. The burst ends with the heart at full size + opacity,
  // so the board can hand it off in the SAME frame to the FlyingHeart overlay
  // (positioned at the same global coordinate, same starting size). That
  // makes the whole sequence look like one continuous heart that pops in,
  // sparkles, then shrinks and flies to the disk-icon slot.
  void _runLike() {
    _useSpringScale = true;
    const spring = SpringDescription(mass: 1, stiffness: 520, damping: 16);
    _pop.value = 0;
    _pop.animateWith(SpringSimulation(spring, 0, 1, 6));

    _env.duration = const Duration(milliseconds: 585);
    _opacity = const AlwaysStoppedAnimation(1.0);
    _drift = const AlwaysStoppedAnimation(0.0);
    // Ring expands aggressively during the first ~250ms then is done.
    _ringT = CurvedAnimation(
      parent: _env,
      curve: const Interval(0.0, 0.40, curve: Curves.easeOutQuad),
    );
    // Sparkles fly out over the first ~500ms.
    _sparkleT = CurvedAnimation(
      parent: _env,
      curve: const Interval(0.0, 0.80, curve: Curves.easeOutCubic),
    );
    _shatterT = const AlwaysStoppedAnimation(0.0);

    _env.forward().whenComplete(_finish);
  }

  // ---------------------------------------------------------------------------
  // UNLIKE  (chained shake → shatter → fall)
  // ---------------------------------------------------------------------------
  void _runUnlike() {
    _useSpringScale = false; // unlike uses _env-driven scale instead
    _env.duration = const Duration(milliseconds: 850);

    // Brief settle, then shake, then the heart splits.
    // Quick "wobble" via a damped sine over 0..0.35 of the envelope.
    _wobbleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 30),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0),
        weight: 30,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 700),
    ]).animate(_env);

    // Scale: instantly 1.0, slight squash at shake peak, then halves keep size.
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 600),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 250,
      ),
    ]).animate(_env);
    _drift = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 350),
      TweenSequenceItem(
        // Halves fall a bit under gravity.
        tween: Tween(begin: 0.0, end: 36.0).chain(
          CurveTween(curve: Curves.easeInQuad),
        ),
        weight: 500,
      ),
    ]).animate(_env);

    _ringT = const AlwaysStoppedAnimation(0.0); // no glow on unlike
    _sparkleT = const AlwaysStoppedAnimation(0.0); // no sparkles on unlike

    // Shatter only kicks in after the shake (>~35% of envelope).
    _shatterT = CurvedAnimation(
      parent: _env,
      curve: const Interval(0.35, 1.0, curve: Curves.easeInCubic),
    );

    _env.forward().whenComplete(_finish);
  }

  void _runReduced() {
    _useSpringScale = false;
    _env.duration = const Duration(milliseconds: 300);
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
    ]).animate(_env);
    _drift = const AlwaysStoppedAnimation(0.0);
    _ringT = const AlwaysStoppedAnimation(0.0);
    _sparkleT = const AlwaysStoppedAnimation(0.0);
    _shatterT = const AlwaysStoppedAnimation(0.0);
    _env.forward().whenComplete(_finish);
  }

  @override
  void dispose() {
    _pop.dispose();
    _env.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pop, _env]),
      builder: (context, _) {
        return CustomPaint(
          painter: _BurstPainter(
            color: widget.color,
            heartSize: widget.heartSize,
            isUnlike: widget.isUnlike,
            popScale: _useSpringScale ? _pop.value.clamp(0.0, 2.0) : 1.0,
            opacity: _opacity.value.clamp(0.0, 1.0),
            drift: _drift.value,
            ringT: _ringT.value,
            sparkleT: _sparkleT.value,
            shatterT: _shatterT.value,
            wobble: _wobbleAnim?.value ?? 0.0,
            sparkles: _sparkles,
          ),
        );
      },
    );
  }
}

/// A small heart that tweens position + scale from one screen-space point to
/// another, then calls [onArrived]. Hosted inside an OverlayEntry so it can
/// fly across widget boundaries (board → AppBar save button slot).
class FlyingHeart extends StatefulWidget {
  const FlyingHeart({
    super.key,
    required this.from,
    required this.to,
    required this.color,
    required this.onArrived,
    this.duration = const Duration(milliseconds: 360),
    this.startSize = 56,
    this.endSize = 22,
  });

  final Offset from;
  final Offset to;
  final Color color;
  final VoidCallback onArrived;
  final Duration duration;
  final double startSize;
  final double endSize;

  @override
  State<FlyingHeart> createState() => _FlyingHeartState();
}

class _FlyingHeartState extends State<FlyingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _arrived = false;

  // Quadratic-Bezier arc parameters. The heart sweeps along a smooth
  // parabolic curve through (from → ctrl → to). The control point sits
  // above the chord (perpendicular up) with a random skew along the chord
  // — that gives every flight a distinct arc that leans left-to-right or
  // right-to-left depending on tap-side-of-screen. Always smoothly curved
  // throughout (no straight-line phase) since a quadratic Bezier never
  // flattens between its endpoints when the control point is off the chord.
  late final Offset _ctrl;
  late final double _perpX;
  late final double _perpY;
  late final double _dirX;
  late final double _dirY;
  late final double _distance;
  late final double _wobbleFreq;
  late final double _wobblePhase;

  @override
  void initState() {
    super.initState();
    _initRandomPath();

    // Spring-driven progress 0 → 1. Slightly underdamped (bounce > 0) for an
    // enjoyable arrival feel; snapToEnd clamps final position so the heart
    // docks exactly on the slot. Uses Flutter's built-in physics.
    _c = AnimationController.unbounded(vsync: this);
    // Softer bounce (was 0.18) — eliminates a subtle settle-wobble right at
    // the slot that contributed to the end-stage flicker. The Bezier path
    // + flutter + end-toss already give the flight its organic feel.
    final spring = SpringDescription.withDurationAndBounce(
      duration: widget.duration,
      bounce: 0.10,
    );
    _c.animateWith(
      SpringSimulation(spring, 0, 1, 0, snapToEnd: true),
    ).whenComplete(() {
      if (_arrived) return;
      _arrived = true;
      widget.onArrived();
    });
  }

  void _initRandomPath() {
    final rng = math.Random();
    final dx = widget.to.dx - widget.from.dx;
    final dy = widget.to.dy - widget.from.dy;
    _distance = math.sqrt(dx * dx + dy * dy);
    _dirX = _distance == 0 ? 0 : dx / _distance;
    _dirY = _distance == 0 ? 0 : dy / _distance;

    // Always pick the perpendicular that points UP in screen space so the
    // arc curves over the top rather than dipping below visible UI.
    final perpA = Offset(-_dirY, _dirX);
    final perpB = Offset(_dirY, -_dirX);
    final perp = perpA.dy <= perpB.dy ? perpA : perpB;
    _perpX = perp.dx;
    _perpY = perp.dy;

    // Sagitta (arc height) — large enough that the curve reads "arcsy"
    // through the whole flight, not just at the start. Big per-flight range.
    final sagitta = (_distance * (0.30 + rng.nextDouble() * 0.20))
        .clamp(60.0, _distance * 0.55);

    // Skew the control point along the chord so each flight has a distinct
    // "direction of curl". Sign biased by tap-vs-target horizontal position:
    // tap on the LEFT of slot → arc leans rightward (curves up-then-right);
    // tap on the RIGHT → arc leans leftward (curves up-then-left). Magnitude
    // is randomized so the same side still feels different each time.
    final dirSignX = widget.from.dx < widget.to.dx ? 1.0 : -1.0;
    final skewMag = 0.10 + rng.nextDouble() * 0.22; // 10%..32% of chord
    final ctrlPos = (0.5 + dirSignX * skewMag).clamp(0.18, 0.82);

    final ctrlBase = Offset.lerp(widget.from, widget.to, ctrlPos)!;
    _ctrl = Offset(
      ctrlBase.dx + _perpX * sagitta,
      ctrlBase.dy + _perpY * sagitta,
    );

    // Tiny perpendicular flutter for organic "alive" feel. Kept small —
    // the Bezier arc itself does the heavy curving.
    _wobbleFreq = 8 + rng.nextDouble() * 4;
    _wobblePhase = rng.nextDouble() * 2 * math.pi;
  }

  Offset _trajectory(double t) {
    // Quadratic Bezier — never flattens to a line, always smoothly curved.
    final mt = 1 - t;
    final x = widget.from.dx * mt * mt +
        _ctrl.dx * 2 * mt * t +
        widget.to.dx * t * t;
    final y = widget.from.dy * mt * mt +
        _ctrl.dy * 2 * mt * t +
        widget.to.dy * t * t;

    // Tiny perpendicular flutter, decays at endpoints.
    final flutterEnv = (1 - (2 * t - 1).abs());
    final flutter =
        math.sin(t * _wobbleFreq + _wobblePhase) * flutterEnv * 3.5;

    // End-toss along direction: tiny overshoot in last 15% then settle.
    double toss = 0;
    if (t > 0.85) {
      final localT = ((t - 0.85) / 0.15).clamp(0.0, 1.0);
      toss =
          math.sin(localT * math.pi * 2) * math.exp(-localT * 2.2) * 8.0;
    }

    return Offset(
      x + _perpX * flutter + _dirX * toss,
      y + _perpY * flutter + _dirY * toss,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Spring may transiently overshoot past 1.0 before settling — clamp
        // the values we feed into interpolators / scale curves.
        final t = _c.value.clamp(0.0, 1.0);
        final posT = t;
        final pos = _trajectory(posT);

        // Tangent-based rotation: tilt follows the actual path direction
        // (sample a step ahead, take the angle difference from the straight
        // chord). Result feels alive — heart banks into curves naturally.
        final ahead = _trajectory((posT + 0.04).clamp(0.0, 1.0));
        final tangentAngle = math.atan2(ahead.dy - pos.dy, ahead.dx - pos.dx);
        final chordAngle = math.atan2(_dirY, _dirX);
        final rotation = (tangentAngle - chordAngle).clamp(-0.4, 0.4) *
            (1.0 - t * 0.6);

        // easeInOutSine for a smooth, continuous shrink over the whole
        // flight (rather than the previous "stay big then snap small" feel).
        // The heart visibly downscales throughout the travel.
        final scaleT = Curves.easeInOutSine.transform(t);
        final baseSize =
            ui.lerpDouble(widget.startSize, widget.endSize, scaleT)!;
        // Heartbeat: ~3 beats over the flight, ±8% scale wobble. Damped down
        // near the end so the heart docks cleanly at slot size.
        final beat = math.sin(t * math.pi * 2 * 3);
        final beatScale = 1.0 + beat * 0.08 * (1.0 - t);
        final size = baseSize * beatScale;

        // Ghost trail: 3 faded copies trailing the head along the same arc.
        const trailCount = 3;
        const trailLag = 0.08;
        Widget heartAt(Offset p, double scale, double opacity, double rot) {
          return Positioned(
            left: p.dx - (size * scale) / 2,
            top: p.dy - (size * scale) / 2,
            width: size * scale,
            height: size * scale,
            child: Opacity(
              opacity: opacity,
              child: Transform.rotate(
                angle: rot,
                child: CustomPaint(
                  painter: _FlyingHeartPainter(
                    color: widget.color,
                    size: size * scale,
                  ),
                ),
              ),
            ),
          );
        }

        return IgnorePointer(
          child: Stack(
            children: [
              for (var i = trailCount; i >= 1; i--)
                if ((posT - trailLag * i) > 0)
                  heartAt(
                    _trajectory((posT - trailLag * i).clamp(0.0, 1.0)),
                    (1.0 - 0.15 * i).clamp(0.4, 1.0),
                    (0.25 / i) * (1.0 - t),
                    rotation * (1.0 - 0.2 * i),
                  ),
              heartAt(pos, 1.0, 1.0, rotation),
            ],
          ),
        );
      },
    );
  }
}

class _FlyingHeartPainter extends CustomPainter {
  _FlyingHeartPainter({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    // Same glyph approach as _BurstPainter for visual consistency.
    const icon = Icons.favorite_rounded;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_FlyingHeartPainter old) =>
      old.color != color || old.size != size;
}

class _Sparkle {
  const _Sparkle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.startDelay,
  });

  final double angle;
  final double distance;
  final double size;
  final double startDelay; // 0..1 within the sparkle envelope
}

/// Single CustomPaint that draws everything — heart, glow ring, sparkles, or
/// the two shattered halves — so a single repaint covers the whole effect
/// without piling Opacity/Transform widgets.
class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.color,
    required this.heartSize,
    required this.isUnlike,
    required this.popScale,
    required this.opacity,
    required this.drift,
    required this.ringT,
    required this.sparkleT,
    required this.shatterT,
    required this.wobble,
    required this.sparkles,
  });

  final Color color;
  final double heartSize;
  final bool isUnlike;
  final double popScale;
  final double opacity;
  final double drift;
  final double ringT;
  final double sparkleT;
  final double shatterT;
  final double wobble;
  final List<_Sparkle> sparkles;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final center = Offset(size.width / 2, size.height / 2 + drift);

    // 1) Glow ring (like only) — expanding circle, fades as it grows.
    if (ringT > 0 && !isUnlike) {
      final ringRadius = heartSize * (0.45 + ringT * 0.85);
      final ringAlpha = (1.0 - ringT).clamp(0.0, 1.0) * 0.55 * opacity;
      final ringPaint = Paint()
        ..color = color.withValues(alpha: ringAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = heartSize * 0.06 * (1.0 - ringT * 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(center, ringRadius, ringPaint);
    }

    // 2) Sparkle mini-hearts (like only).
    if (sparkleT > 0 && !isUnlike) {
      for (final s in sparkles) {
        final local = ((sparkleT - s.startDelay) / (1.0 - s.startDelay))
            .clamp(0.0, 1.0);
        if (local <= 0) continue;
        final t = Curves.easeOutCubic.transform(local);
        final dx = math.cos(s.angle) * s.distance * t;
        final dy = math.sin(s.angle) * s.distance * t;
        final pos = center + Offset(dx, dy);
        final fade = (1.0 - local).clamp(0.0, 1.0);
        final scale = 0.5 + 0.5 * t;
        _drawHeart(
          canvas: canvas,
          center: pos,
          size: s.size * scale,
          fill: color.withValues(alpha: fade * opacity * 0.95),
          shadow: false,
        );
      }
    }

    // 3) Main heart — either the popped single heart (like) or two halves (unlike).
    if (isUnlike && shatterT > 0) {
      _drawShatteredHeart(canvas, center);
    } else {
      // Shake displaces along x via a damped sine.
      final shakeX = math.sin(wobble * math.pi * 6) * heartSize * 0.06 * (1 - wobble);
      _drawHeart(
        canvas: canvas,
        center: center + Offset(shakeX, 0),
        size: heartSize * popScale,
        fill: color.withValues(alpha: opacity),
        shadow: true,
      );
    }
  }

  void _drawShatteredHeart(Canvas canvas, Offset center) {
    // Two halves rotate apart and fall a bit. shatterT goes 0→1.
    final separation = shatterT * heartSize * 0.45;
    final rotL = -shatterT * 0.55; // radians
    final rotR = shatterT * 0.55;
    final fade = opacity;

    for (final isLeft in [true, false]) {
      final sign = isLeft ? -1 : 1;
      final pos = center + Offset(sign * separation, shatterT * 12);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(isLeft ? rotL : rotR);
      // Clip to the half we want, then draw the full heart through the clip.
      canvas.clipRect(
        Rect.fromLTRB(
          isLeft ? -heartSize : 0,
          -heartSize,
          isLeft ? 0 : heartSize,
          heartSize,
        ),
      );
      _drawHeart(
        canvas: canvas,
        center: Offset.zero,
        size: heartSize,
        fill: color.withValues(alpha: fade),
        shadow: false,
        outlined: true,
      );
      canvas.restore();
    }
  }

  void _drawHeart({
    required Canvas canvas,
    required Offset center,
    required double size,
    required Color fill,
    required bool shadow,
    bool outlined = false,
  }) {
    if (size <= 0) return;
    // Soft red blur glow under the heart — kills the cheap white halo and
    // gives depth without a hard outline. Rendered as a slightly larger,
    // blurred copy of the same glyph in a saveLayer so the blur stays inside
    // the heart silhouette. Skipped for outlined hearts (shatter halves)
    // since glowing an outline reads as a smudge.
    if (shadow && !outlined) {
      final glowRect = Rect.fromCenter(
        center: center,
        width: size * 1.6,
        height: size * 1.6,
      );
      canvas.saveLayer(
        glowRect,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      );
      _paintHeartGlyph(
        canvas,
        center: center,
        size: size,
        color: color.withValues(alpha: fill.a * 0.55),
      );
      canvas.restore();
    }
    _paintHeartGlyph(
      canvas,
      center: center,
      size: size,
      color: fill,
      outlined: outlined,
    );
  }

  /// Renders the Material heart glyph on [canvas]. [outlined] picks the
  /// border variant — used for the shatter halves so the "broken" state
  /// reads as an outline drained of fill rather than a red filled heart.
  void _paintHeartGlyph(
    Canvas canvas, {
    required Offset center,
    required double size,
    required Color color,
    bool outlined = false,
  }) {
    final icon =
        outlined ? Icons.favorite_border_rounded : Icons.favorite_rounded;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.popScale != popScale ||
      old.opacity != opacity ||
      old.drift != drift ||
      old.ringT != ringT ||
      old.sparkleT != sparkleT ||
      old.shatterT != shatterT ||
      old.wobble != wobble;
}
