import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// A header's tab moving its pages on a motor spring, the motion every other
/// part of a page's chrome moves on (the search morph, the scroll chrome,
/// the Live first capsule), instead of a stock easing curve.
///
/// ```dart
/// onTabTap: (index) => PageSpring.to(_pages, index, context: context),
/// ```
///
/// - **A real spring.** The page is driven by the spring's own simulation,
///   in real time, from where it is to the page asked for.
/// - **Interruptible.** A finger on the page takes over at once, as with any
///   page animation. Another tab tapped mid-flight retargets the same motion
///   from where it is, carrying its speed: no stop, no restart from rest.
/// - **Reduced motion** jumps straight to the page.
/// - **Lands exactly** on the page (a spring that would creep the last
///   fraction of a pixel is parked there), and the page view settles there
///   as after any swipe.
///
/// The one tab spring: every header's tabs move their pages on it, and a
/// re-tapped tab's list goes back to its top on the same [motion]
/// ([ScrollControllerSpring.springToOffset], or [SpringCurve] for a list
/// whose own API takes a duration and a curve).
abstract final class PageSpring {
  /// The default: critically damped (no overshoot past the page, which would
  /// flash the neighbour's edge), about as long as a tab change reads.
  static const CupertinoMotion motion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 300),
    snapToEnd: true,
  );

  /// Closer than this (logical pixels) and slower than [restVelocity]
  /// (pixels a second), the spring is home: parked on the page.
  static const double restDistance = 0.25;
  static const double restVelocity = 4;

  /// Springs every page view attached to [controller] to [page] on
  /// [motion]. Completes when the motion ends, whether it landed or a
  /// finger, a jump or another call took over.
  ///
  /// With reduced motion ([MediaQuery.disableAnimationsOf] for [context]) it
  /// jumps.
  static Future<void> to(
    PageController controller,
    int page, {
    required BuildContext context,
    Motion motion = PageSpring.motion,
  }) {
    if (!controller.hasClients) return Future<void>.value();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(page);
      return Future<void>.value();
    }
    return Future.wait<void>([
      for (final position in controller.positions)
        _spring(position, controller.viewportFraction, page, motion),
    ]);
  }

  /// Where [page] starts on [position]: `PageController`'s own arithmetic,
  /// kept inside the scroll range.
  static double pixelsFor(
    ScrollPosition position,
    double viewportFraction,
    int page,
  ) {
    final viewport = position.viewportDimension;
    final leading = math.max(0.0, viewport * (viewportFraction - 1) / 2);
    final pixels = page * viewport * viewportFraction + leading;
    return pixels.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  static Future<void> _spring(
    ScrollPosition position,
    double viewportFraction,
    int page,
    Motion motion,
  ) {
    final laidOut =
        position.hasContentDimensions && position.hasViewportDimension;
    if (!laidOut) {
      // No frame of motion to show yet: the page view lands on it as it
      // lays out, as `PageController.jumpToPage` would.
      return Future<void>.value();
    }
    if (position is! ScrollPositionWithSingleContext) {
      // Not a position this can drive: only the page to be on.
      position.jumpTo(pixelsFor(position, viewportFraction, page));
      return Future<void>.value();
    }
    final target = pixelsFor(position, viewportFraction, page);
    if ((position.pixels - target).abs() < restDistance) {
      position.jumpTo(target);
      return Future<void>.value();
    }
    // A spring still moving this page (a tab tapped mid-flight) hands its
    // speed to the new one: the page turns toward the new tab without
    // stopping first.
    final running = _running[position];
    final velocity = running != null && running.moving ? running.velocity : 0.0;
    final simulation = _simulation(motion, position.pixels, target, velocity);
    final activity = _PageSpringActivity(
      position,
      simulation,
      position.context.vsync,
    );
    _running[position] = activity;
    position.beginActivity(activity);
    return activity.done;
  }

  /// The spring last started on each position, while it may still run.
  static final Expando<_PageSpringActivity> _running =
      Expando<_PageSpringActivity>('PageSpring');

  static Simulation _simulation(
    Motion motion,
    double start,
    double end,
    double velocity,
  ) {
    const tolerance = Tolerance(distance: restDistance, velocity: restVelocity);
    if (motion is SpringMotion) {
      return SpringSimulation(
        motion.description,
        start,
        end,
        velocity,
        tolerance: tolerance,
        snapToEnd: true,
      );
    }
    return motion.createSimulation(start: start, end: end, velocity: velocity);
  }
}

/// [PageSpring.to] as a method on the controller.
extension PageControllerSpring on PageController {
  /// See [PageSpring.to].
  Future<void> springTo(
    int page, {
    required BuildContext context,
    Motion motion = PageSpring.motion,
  }) => PageSpring.to(this, page, context: context, motion: motion);
}

/// A scroll view's offset moved on [PageSpring.motion]: a list taken back
/// to its top when its tab is tapped again moves as the tab's pages do.
extension ScrollControllerSpring on ScrollController {
  /// Springs every position attached to this controller to [offset], played
  /// from rest as a [SpringCurve] through the scroll view's own `animateTo`
  /// (which rides out a long list's estimated length changing on the way).
  /// With reduced motion it jumps.
  Future<void> springToOffset(
    double offset, {
    required BuildContext context,
    Motion motion = PageSpring.motion,
  }) {
    if (!hasClients) return Future<void>.value();
    if (MediaQuery.disableAnimationsOf(context)) {
      jumpTo(offset);
      return Future<void>.value();
    }
    final spring = SpringCurve.of(motion);
    return animateTo(offset, duration: spring.duration, curve: spring);
  }
}

/// [motion] from rest to rest as a curve over [duration], the time the
/// spring takes to settle: an animation of that length with this curve moves
/// exactly as the spring does, in real time. For an animation API that only
/// takes a duration and a curve (a positioned list's `scrollTo`).
///
/// (motor's own `toCurve` reads the curve's 0 to 1 as the spring's first
/// second, so with a shorter duration the spring is squeezed, not played.)
class SpringCurve extends Curve {
  const SpringCurve._(this._simulation, this._seconds);

  /// One curve per motion, measured once.
  static SpringCurve of(Motion motion) => _cache.putIfAbsent(motion, () {
    final simulation = motion.createSimulation();
    var seconds = 0.0;
    // Settled to the motion's tolerance, within two seconds at most.
    while (seconds < 2 && !simulation.isDone(seconds)) {
      seconds += 1 / 240;
    }
    return SpringCurve._(simulation, seconds <= 0 ? 1 / 240 : seconds);
  });

  static final Map<Motion, SpringCurve> _cache = <Motion, SpringCurve>{};

  final Simulation _simulation;
  final double _seconds;

  /// How long the spring takes to settle.
  Duration get duration => Duration(microseconds: (_seconds * 1e6).round());

  @override
  double transformInternal(double t) => _simulation.x(t * _seconds);
}

/// The page view's scroll position driven by the spring's simulation: a
/// ballistic activity (taps on the pages wait while it moves, as during any
/// page animation), whose end is reported to [done].
class _PageSpringActivity extends BallisticScrollActivity {
  _PageSpringActivity(
    ScrollActivityDelegate delegate,
    Simulation simulation,
    TickerProvider vsync,
  ) : super(delegate, simulation, vsync, true);

  final Completer<void> _done = Completer<void>();

  Future<void> get done => _done.future;

  /// Still driving its page: not yet landed, nor taken over.
  bool get moving => !_done.isCompleted;

  @override
  void dispose() {
    if (!_done.isCompleted) _done.complete();
    super.dispose();
  }
}
