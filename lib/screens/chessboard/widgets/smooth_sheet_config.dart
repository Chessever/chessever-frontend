/// Enhanced smooth sheet configurations with Motor spring physics
/// Provides buttery-smooth, native-feeling bottom sheet animations
library;

import 'dart:math' as math;
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
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
      snaps: const [
        SheetOffset.proportionalToViewport(0.80),
        SheetOffset.proportionalToViewport(0.95),
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

/// Enhanced material decoration with refined styling
class ChessSheetDecoration {
  ChessSheetDecoration._();

  /// Themed sheet with premium feel
  /// Slightly transparent for depth, generous border radius for modern look
  static MaterialSheetDecoration dark(
    BuildContext context, {
    double alpha = 0.96,
    double borderRadius = 28.0,
  }) {
    return MaterialSheetDecoration(
      size: SheetSize.stretch,
      color: context.colors.surface.withValues(alpha: alpha),
      borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
      clipBehavior: Clip.antiAlias,
    );
  }

  /// Frosted glass effect for overlays
  /// Combines blur and transparency for premium feel
  static MaterialSheetDecoration frosted(
    BuildContext context, {
    double alpha = 0.92,
    double borderRadius = 28.0,
  }) {
    return MaterialSheetDecoration(
      size: SheetSize.stretch,
      color: context.colors.surface.withValues(alpha: alpha),
      borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
      clipBehavior: Clip.antiAlias,
    );
  }
}

/// Animated route that uses spring physics for transitions
class SpringModalSheetRoute<T> extends ModalSheetRoute<T> {
  SpringModalSheetRoute({
    required super.builder,
    Curve springCurve = ChessSheetCurves.snappy,
    super.barrierDismissible = true,
    super.swipeDismissible = true,
    Color? barrierColor,
    super.barrierLabel,
    super.viewportPadding,
    Duration? transitionDuration,
    Duration? reverseTransitionDuration,
  }) : super(
         barrierColor: barrierColor ?? const Color(0xB3000000),
         transitionCurve: springCurve,
         transitionDuration:
             transitionDuration ?? const Duration(milliseconds: 450),
       );
}

/// Modal sheet route whose slide is driven by a real spring simulation rather
/// than by a [Curve] sampled over a fixed duration, and whose entrance is held
/// back until its content has been built once.
///
/// Two problems with the curve-driven version ([SpringModalSheetRoute], and
/// Material's own `showModalBottomSheet`) are fixed here:
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
class MotionSheetRoute<T> extends ModalSheetRoute<T> {
  MotionSheetRoute({
    required super.builder,
    super.barrierColor,
    super.barrierLabel,
    super.barrierDismissible,
    super.swipeDismissible = true,
    super.viewportPadding,
    super.swipeDismissSensitivity,
    this.entranceMotion = const CupertinoMotion.smooth(
      duration: Duration(milliseconds: 400),
      snapToEnd: true,
    ),
    this.exitMotion = const CupertinoMotion.smooth(
      duration: Duration(milliseconds: 320),
      snapToEnd: true,
    ),
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

  /// Spring that carries the sheet up on push. Critically damped by default:
  /// a tall sheet that overshoots its rest position lifts its bottom edge off
  /// the screen and flashes the barrier underneath it.
  final Motion entranceMotion;

  /// Spring that carries the sheet back down on pop. Shorter than
  /// [entranceMotion] so a dismissal feels decided rather than reluctant.
  final Motion exitMotion;

  /// Set between [didPush] and the post-frame callback that releases the
  /// entrance, so a route popped inside that window never starts moving up.
  bool _entrancePending = false;

  @override
  Simulation createSimulation({required bool forward}) {
    // Always start from where the sheet currently is: a pop can arrive
    // mid-entrance, or with the sheet already dragged part of the way down.
    final motion = forward ? entranceMotion : exitMotion;
    return motion.createSimulation(
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

/// Helper to create smooth sheet routes with sensible defaults
class ChessSheetRoutes {
  ChessSheetRoutes._();

  /// Action menu route - snappy and responsive
  static SpringModalSheetRoute<void> actionMenu({
    required WidgetBuilder builder,
    BuildContext? context,
  }) {
    final padding =
        context != null ? MediaQuery.viewPaddingOf(context) : EdgeInsets.zero;
    return SpringModalSheetRoute<void>(
      builder: builder,
      springCurve: ChessSheetCurves.snappy,
      barrierColor: context?.colors.scrim ?? const Color(0xB3000000),
      barrierLabel: 'Close menu',
      // Only respect top padding; allow the sheet to cover the bottom safe area
      viewportPadding: EdgeInsets.only(top: padding.top),
    );
  }

  /// Comment editor route - smooth and gentle
  static SpringModalSheetRoute<void> commentEditor({
    required WidgetBuilder builder,
    BuildContext? context,
  }) {
    final padding =
        context != null ? MediaQuery.viewPaddingOf(context) : EdgeInsets.zero;
    return SpringModalSheetRoute<void>(
      builder: builder,
      springCurve: ChessSheetCurves.smooth,
      barrierColor: context?.colors.scrim ?? const Color(0xB3000000),
      barrierLabel: 'Close editor',
      // Only respect top padding; allow the sheet to cover the bottom safe area
      viewportPadding: EdgeInsets.only(top: padding.top),
    );
  }

  /// Preview route - bouncy and delightful
  static SpringModalSheetRoute<void> preview({
    required WidgetBuilder builder,
    BuildContext? context,
  }) {
    final padding =
        context != null ? MediaQuery.viewPaddingOf(context) : EdgeInsets.zero;
    return SpringModalSheetRoute<void>(
      builder: builder,
      springCurve: ChessSheetCurves.bouncy,
      // Keep background visible while dimming slightly behind the sheet
      barrierColor: context?.colors.scrim ?? const Color(0xB3000000),
      barrierLabel: 'Close preview',
      // Only respect top padding; allow the sheet to cover the bottom safe area
      viewportPadding: EdgeInsets.only(top: padding.top),
    );
  }
}
