/// Enhanced smooth sheet configurations with Motor spring physics
/// Provides buttery-smooth, native-feeling bottom sheet animations
library;

import 'dart:math' as math;

import 'package:chessever2/widgets/glass_sheet.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:motor/motor.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Collection of spring curve presets optimized for different sheet interactions
/// These curves use physics-based spring motion for natural, responsive animations
class ChessSheetCurves {
  ChessSheetCurves._();

  /// Snappy, responsive curve for quick interactions (taps, quick drags)
  /// High response rate with controlled bounce - feels instant yet smooth
  static const Curve snappy = _SpringCurve(
    stiffness: 420.0,
    damping: 32.0,
    mass: 1.0,
  );

  /// Bouncy, playful curve for prominent interactions (long-press reveals)
  /// Lower damping creates subtle overshoot for satisfying feedback
  static const Curve bouncy = _SpringCurve(
    stiffness: 280.0,
    damping: 22.0,
    mass: 1.0,
  );

  /// Smooth, gentle curve for content scrolling and settling
  /// Balanced parameters feel natural without being sluggish
  static const Curve smooth = _SpringCurve(
    stiffness: 320.0,
    damping: 28.0,
    mass: 1.0,
  );

  /// Crisp curve for dismissals and quick exits
  /// High stiffness ensures rapid completion without lag
  static const Curve crisp = _SpringCurve(
    stiffness: 480.0,
    damping: 35.0,
    mass: 1.0,
  );
}

/// Physics-based spring curve for natural animations
/// Simulates real spring behavior with stiffness, damping, and mass
class _SpringCurve extends Curve {
  final double stiffness;
  final double damping;
  final double mass;

  const _SpringCurve({
    required this.stiffness,
    required this.damping,
    required this.mass,
  });

  @override
  double transformInternal(double t) {
    if (t == 0.0 || t == 1.0) return t;

    // Calculate spring physics using underdamped harmonic oscillator
    final omega = math.sqrt(stiffness / mass);
    final zeta = damping / (2 * mass * omega);

    if (zeta < 1.0) {
      // Underdamped: creates subtle overshoot (bouncy feel)
      final omegaD = omega * math.sqrt(1.0 - zeta * zeta);
      final envelope = math.exp(-zeta * omega * t);
      final phase = math.atan2(zeta * omega, omegaD);
      return 1.0 - envelope * math.cos(omegaD * t + phase) / math.cos(phase);
    } else if (zeta == 1.0) {
      // Critically damped: fastest approach without overshoot
      final r = omega;
      return 1.0 - math.exp(-r * t) * (1.0 + r * t);
    } else {
      // Overdamped: smooth, slow approach
      final r1 = omega * (zeta - math.sqrt(zeta * zeta - 1.0));
      final r2 = omega * (zeta + math.sqrt(zeta * zeta - 1.0));
      final c1 = r2 / (r2 - r1);
      final c2 = -r1 / (r2 - r1);
      return 1.0 - (c1 * math.exp(-r1 * t) + c2 * math.exp(-r2 * t));
    }
  }
}

/// Configuration presets for different sheet types
class ChessSheetConfigs {
  ChessSheetConfigs._();

  /// Config for action menus (move actions, variation actions)
  /// Opens quickly, snaps crisply, dismisses instantly
  static const SheetDragConfiguration actionMenu = SheetDragConfiguration();

  /// Config for comment editors
  /// Smooth appearance, gentle settling when keyboard appears
  static const SheetDragConfiguration commentEditor = SheetDragConfiguration();

  /// Config for PV preview cards
  /// Bouncy entrance for visual delight, responsive dragging
  static const SheetDragConfiguration pvPreview = SheetDragConfiguration();

  /// Snap grid for action sheets - two comfortable positions
  /// 35% for quick peek, 75% for full interaction
  static SheetSnapGrid actionMenuSnaps({double minFlingSpeed = 800.0}) {
    return SheetSnapGrid(
      snaps: const [
        SheetOffset.proportionalToViewport(0.35),
        SheetOffset.proportionalToViewport(0.75),
      ],
      minFlingSpeed: minFlingSpeed,
    );
  }

  /// Snap grid for comment editors - high position for keyboard visibility
  /// 80% default, 95% when user wants more space
  static SheetSnapGrid commentEditorSnaps({double minFlingSpeed = 600.0}) {
    return SheetSnapGrid(
      // A comment editor over the board stays a panel, not a takeover:
      // enough for the field plus the keyboard, never the whole screen.
      snaps: const [
        SheetOffset.proportionalToViewport(0.56),
        SheetOffset.proportionalToViewport(0.72),
      ],
      minFlingSpeed: minFlingSpeed,
    );
  }

  /// Snap grid for full-height previews
  /// Single snap point at near-full height
  static SheetSnapGrid previewSnaps({double minFlingSpeed = 700.0}) {
    return SheetSnapGrid(
      snaps: const [SheetOffset.proportionalToViewport(0.92)],
      minFlingSpeed: minFlingSpeed,
    );
  }
}

/// The surface of every smooth_sheets sheet: the popups' frosted glass
/// ([ChessSheetGlass]), rounded at the top.
class ChessSheetDecoration {
  ChessSheetDecoration._();

  /// The sheet in [ChessSheetGlass], averaging out to the theme's surface.
  ///
  /// [alpha] is what the opaque sheet's surface used to be laid at. It is
  /// kept so callers compile; the glass's density is [PopupGlassStyle]'s,
  /// solved for legible text over the busiest page. [solid] is
  /// [GlassSheet.solid].
  static SheetDecoration dark(
    BuildContext context, {
    double alpha = 0.96,
    double borderRadius = 28.0,
    bool solid = false,
    bool lip = true,
  }) {
    return SheetDecorationBuilder(
      size: SheetSize.stretch,
      builder: (context, child) => ChessSheetGlass(
        radius: borderRadius,
        solid: solid,
        lip: lip,
        child: child,
      ),
    );
  }

  /// The same glass as [dark]: there is one sheet material.
  static SheetDecoration frosted(
    BuildContext context, {
    double alpha = 0.92,
    double borderRadius = 28.0,
    bool solid = false,
    bool lip = true,
  }) {
    return dark(
      context,
      alpha: alpha,
      borderRadius: borderRadius,
      solid: solid,
      lip: lip,
    );
  }
}

/// The smooth_sheets sheets' name for the one sheet glass ([GlassSheet]):
/// rounded at 28 by default, on a transparent [Material] (ink and the
/// default text style, as the opaque `MaterialSheetDecoration` gave them).
/// It has no surface of its own: everything it draws is [GlassSheet]'s,
/// frosted or solid by [GlassSheet]'s one rule.
class ChessSheetGlass extends GlassSheet {
  const ChessSheetGlass({
    super.key,
    required super.child,
    super.radius = 28,
    super.tone,
    super.solid,
    super.lip,
  }) : super(inkSurface: true);

  /// The barrier a glass sheet opens over: the theme's scrim at the
  /// popups' strength, which the plate is solved over.
  static Color barrierColor(BuildContext context) => glassSheetBarrier(context);
}

/// Where a 0-to-1 spring that moves a surface counts as at rest: within two
/// thousandths of its travel (about a pixel for a full-height sheet, and it
/// then lands exactly) and slower than four hundredths of it a second (under
/// half a pixel a frame). The default tolerance waits for a thousandth of a
/// unit a second, and a critically damped spring spends a third of its
/// frames creeping sub-pixel to it, every one of them a redraw of the glass
/// over the page.
const Tolerance kSurfaceSpringTolerance = Tolerance(
  distance: 2e-3,
  velocity: 4e-2,
);

/// [motion]'s simulation from [start] to [end], at rest at
/// [kSurfaceSpringTolerance] and landing exactly on [end].
Simulation settlingSimulation(
  Motion motion, {
  required double start,
  required double end,
}) {
  if (motion is SpringMotion) {
    return SpringSimulation(
      motion.description,
      start,
      end,
      0,
      tolerance: kSurfaceSpringTolerance,
      snapToEnd: true,
    );
  }
  return motion.createSimulation(start: start, end: end);
}

/// [spring] for a motion builder that moves a surface through 0 to 1 (a
/// sheet's slide, its scrim): the same spring, at rest at
/// [kSurfaceSpringTolerance] and landing exactly on its target, so the
/// builder stops ticking once nothing moves by a pixel.
@immutable
class SurfaceSpring extends Motion {
  const SurfaceSpring(this.spring) : super(tolerance: kSurfaceSpringTolerance);

  final SpringMotion spring;

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
    spring.description,
    start,
    end,
    velocity,
    tolerance: tolerance,
    snapToEnd: true,
  );

  @override
  bool operator ==(Object other) =>
      other is SurfaceSpring && other.spring == spring;

  @override
  int get hashCode => Object.hash(SurfaceSpring, spring);
}

/// A sheet route's slide on a spring: a real simulation for each direction
/// ([createSimulation]) rather than a [Curve] sampled over a fixed duration,
/// and an entrance held back until the sheet's content has been built once.
///
/// Two problems with a curve-driven sheet route (the old
/// `SpringModalSheetRoute`, and Material's own `showModalBottomSheet`) are
/// fixed here:
///
///  * **The entrance was skipped on heavy sheets.** A route starts its
///    transition clock the moment it is pushed, but the frame that follows the
///    push is the frame that builds the sheet's whole subtree. If that build
///    takes longer than the transition, the first frame the user actually sees
///    is already at (or near) the resting position, so the sheet appears to
///    jump into place instead of sliding. [didPush] parks the sheet off-screen
///    for that frame and starts the spring from a post-frame callback, so the
///    motion always begins on a frame with nothing left to build.
///  * **The exit was back-loaded.** Spring-shaped curves spend most of their
///    travel in the first fraction of the timeline; played in reverse that
///    becomes a pause followed by a drop. A simulation is asked for each
///    direction separately ([createSimulation]), so the exit accelerates away
///    from rest exactly like the entrance accelerates towards it.
///
/// The route's own curve must map 1:1 (linear): the simulation carries all
/// of the easing.
mixin SpringSheetTransition<T> on TransitionRoute<T> {
  /// Spring that carries the sheet up on push. Critically damped by default:
  /// a tall sheet that overshoots its rest position lifts its bottom edge off
  /// the screen and flashes the barrier underneath it.
  Motion get entranceMotion;

  /// Spring that carries the sheet back down on pop. Shorter than
  /// [entranceMotion] so a dismissal feels decided rather than reluctant.
  Motion get exitMotion;

  /// Set between [didPush] and the post-frame callback that releases the
  /// entrance, so a route popped inside that window never starts moving up.
  bool _entrancePending = false;

  @override
  Simulation createSimulation({required bool forward}) {
    // Always start from where the sheet currently is: a pop can arrive
    // mid-entrance, or with the sheet already dragged part of the way down.
    return settlingSimulation(
      forward ? entranceMotion : exitMotion,
      start: controller!.value,
      end: forward ? 1.0 : 0.0,
    );
  }

  @override
  TickerFuture didPush() {
    final transition = controller!;
    final future = super.didPush();
    // Freeze the spring that `super.didPush()` just started. `canceled: false`
    // completes `future` normally (the navigator only uses it to mark the push
    // finished) and leaves the status alone, so the route is not mistaken for
    // a dismissed one while it waits.
    transition.stop(canceled: false);
    _entrancePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_entrancePending) {
        return;
      }
      _entrancePending = false;
      if (transition.isCompleted || transition.isAnimating) {
        return;
      }
      transition.animateWith(createSimulation(forward: true));
    });
    // The push already schedules the frame whose end releases the entrance,
    // but ask for one anyway: a sheet parked off-screen behind a transparent
    // barrier would block taps while showing nothing.
    WidgetsBinding.instance.ensureVisualUpdate();
    return future;
  }

  @override
  bool didPop(T? result) {
    _entrancePending = false;
    return super.didPop(result);
  }
}

/// The default springs of a sheet's slide.
const Motion kSheetEntranceMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 400),
  snapToEnd: true,
);
const Motion kSheetExitMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 320),
  snapToEnd: true,
);

/// smooth_sheets' modal sheet route on [SpringSheetTransition]'s springs.
class MotionSheetRoute<T> extends ModalSheetRoute<T>
    with SpringSheetTransition<T> {
  MotionSheetRoute({
    required super.builder,
    super.barrierColor,
    super.barrierLabel,
    super.barrierDismissible,
    super.swipeDismissible = true,
    super.viewportPadding,
    super.swipeDismissSensitivity,
    this.entranceMotion = kSheetEntranceMotion,
    this.exitMotion = kSheetExitMotion,
  }) : super(
         // The simulation carries all of the easing, so the curve has to map
         // it 1:1. It doubles as the curve smooth_sheets falls back to while a
         // swipe is in progress, where linear is exactly what tracks a finger.
         transitionCurve: Curves.linear,
         // Ignored while a simulation drives the controller, but smooth_sheets
         // still reads it to time the snap-back after a released swipe that
         // did not dismiss.
         transitionDuration: const Duration(milliseconds: 300),
       );

  @override
  final Motion entranceMotion;

  @override
  final Motion exitMotion;
}

/// Page route for nested sheet navigation
class SpringPagedSheetRoute extends PagedSheetRoute {
  SpringPagedSheetRoute({
    required super.builder,
    super.scrollConfiguration = const SheetScrollConfiguration(),
    super.dragConfiguration = const SheetDragConfiguration(),
    super.initialOffset = const SheetOffset.proportionalToViewport(0.5),
    required super.snapGrid,
    super.transitionDuration = const Duration(milliseconds: 350),
  });
}

/// The modal sheets' routes: each slides on a spring ([MotionSheetRoute])
/// over the plain scrim the sheet glass is solved over
/// ([ChessSheetGlass.barrierColor]).
class ChessSheetRoutes {
  ChessSheetRoutes._();

  /// The barrier when no [BuildContext] is given: the dark scrim at the
  /// popups' strength.
  static const Color _fallbackBarrier = Color(0x9E000000);

  static MotionSheetRoute<void> _route({
    required WidgetBuilder builder,
    required BuildContext? context,
    required String label,
    Color? barrierColor,
  }) {
    final padding = context != null
        ? MediaQuery.viewPaddingOf(context)
        : EdgeInsets.zero;
    return MotionSheetRoute<void>(
      builder: builder,
      barrierColor:
          barrierColor ??
          (context != null
              ? ChessSheetGlass.barrierColor(context)
              : _fallbackBarrier),
      barrierLabel: label,
      barrierDismissible: true,
      // Only respect top padding; allow the sheet to cover the bottom safe area
      viewportPadding: EdgeInsets.only(top: padding.top),
    );
  }

  /// Action menu route (move, variation and line actions).
  static MotionSheetRoute<void> actionMenu({
    required WidgetBuilder builder,
    BuildContext? context,
    Color? barrierColor,
  }) => _route(
    builder: builder,
    context: context,
    label: 'Close menu',
    barrierColor: barrierColor,
  );

  /// Comment editor route, and the Library's save sheets.
  static MotionSheetRoute<void> commentEditor({
    required WidgetBuilder builder,
    BuildContext? context,
    Color? barrierColor,
  }) => _route(
    builder: builder,
    context: context,
    label: 'Close editor',
    barrierColor: barrierColor,
  );

  /// Preview route.
  static MotionSheetRoute<void> preview({
    required WidgetBuilder builder,
    BuildContext? context,
  }) => _route(builder: builder, context: context, label: 'Close preview');
}
