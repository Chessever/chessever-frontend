import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// The single motion vocabulary for the home search field.
///
/// The focus morph has four moving parts — the avatar squeezing out of the
/// row, the field taking the freed width, the field edge lifting off the
/// surface, and the results panel unrolling underneath. Before this they were
/// four independent `AnimatedX` widgets on three different `Curves`, which is
/// why the transition read as a pile of tweens rather than one gesture.
///
/// Everything now runs on [morph], driven from one controller in
/// `EnhancedRoundedSearchBar` plus [ParkedMotionBuilder]s started on the same
/// frame, so the parts stay in lockstep for the whole travel.
class SearchMotion {
  const SearchMotion._();

  /// The field morph itself.
  ///
  /// `.smooth` means bounce 0 — critically damped, no overshoot. That is not a
  /// taste call here, it is required: the collapse hands horizontal room
  /// straight to the text field and the panel expands against the page content
  /// below it, so any overshoot would visibly shove text past its resting
  /// position and drag it back.
  ///
  /// 200ms is the spring's perceptual duration, not its settling time: it is
  /// ~95% home at 200ms and parked by ~320ms (see [restEpsilon]). That keeps
  /// the field feeling attached to the tap rather than trailing it.
  static const morph = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 200),
  );

  /// Small affordances riding on top of the morph — the clear button, the
  /// magnifier tint. Quicker so they land with the touch instead of arriving
  /// after the panel.
  static const accent = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 180),
  );

  /// [morph] expressed as a [Curve], for the handful of Flutter APIs that only
  /// accept duration + curve (`AnimatedSize`). Pair it with [morphDuration] so
  /// the spring plays over its own timeframe. Must be `static final`: `toCurve`
  /// is a getter, so it cannot be `const`.
  static final morphCurve = morph.toCurve;

  /// Timeframe to pair with [morphCurve].
  static const morphDuration = Duration(milliseconds: 200);

  /// How close to its target a spring has to get before it counts as arrived.
  ///
  /// A spring's approach is asymptotic. [morph] is 95% of the way home at
  /// 200ms but does not satisfy the simulation's own tolerance until roughly
  /// 500ms. Those last 300ms move things by a small fraction of a pixel while
  /// still scheduling a frame apiece — 36 of them on a 120Hz panel, per
  /// spring, per focus change. 0.0015 of any travel here is well under a
  /// logical pixel, so parking at that point is invisible and gives every one
  /// of those frames back.
  static const restEpsilon = 0.0015;
}

/// Animates a single value on a spring and parks it the moment it is visually
/// at rest, rather than ticking out the tail described in
/// [SearchMotion.restEpsilon].
///
/// Motor's own `SingleMotionBuilder` has no hook for that, which is the only
/// reason this exists. Use it for anything on the search morph.
class ParkedMotionBuilder extends StatefulWidget {
  const ParkedMotionBuilder({
    super.key,
    required this.value,
    required this.motion,
    required this.builder,
    this.child,
  });

  final double value;
  final Motion motion;
  final ValueWidgetBuilder<double> builder;

  /// Subtree that does not depend on the animated value. Built once and handed
  /// to [builder] on every frame.
  final Widget? child;

  @override
  State<ParkedMotionBuilder> createState() => _ParkedMotionBuilderState();
}

class _ParkedMotionBuilderState extends State<ParkedMotionBuilder>
    with SingleTickerProviderStateMixin {
  late final BoundedSingleMotionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BoundedSingleMotionController(
      motion: widget.motion,
      vsync: this,
      initialValue: widget.value,
    );
    _controller.addListener(_onValue);
  }

  @override
  void didUpdateWidget(covariant ParkedMotionBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _controller.animateTo(widget.value);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onValue)
      ..dispose();
    super.dispose();
  }

  void _onValue() {
    if (!_controller.isAnimating) return;
    if ((_controller.value - widget.value).abs() > SearchMotion.restEpsilon) {
      return;
    }
    // The stop is not optional: BoundedMotionController overrides the `value`
    // setter and, unlike the unbounded base class, does not stop its own
    // ticker — assigning alone would leave the spring running and this
    // listener would re-enter itself until the stack blew.
    _controller
      ..stop(canceled: true)
      ..value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder:
          (context, child) => widget.builder(context, _controller.value, child),
    );
  }
}

/// Squeezes a control out of its row slot as [open] goes false.
///
/// The slot's width factor and the child's scale come off the same value, so
/// the child shrinks to exactly fill its closing slot — it is never sliced by
/// the clip on the way out, which is what a plain `SizeTransition` does to a
/// round avatar or a round button.
///
/// Only the width closes. The child keeps its full height for the whole
/// travel and never leaves the tree, so the row it sits in cannot change
/// height. That matters more than it sounds: the home bar's height is set by
/// the 44.w profile avatar, and dropping the avatar on the last frame used to
/// take 40dp out of the row in a single frame, snapping the results panel and
/// the entire page below it back up. Width shrinks, height holds.
///
/// Scale is the whole fade. There is deliberately no [Opacity] here: opacity
/// between 0 and 1 forces an offscreen render pass, and the profile avatar's
/// premium ring paints a `MaskFilter.blur` into it on every frame. An opacity
/// that only engaged partway through the squeeze meant that offscreen — and
/// the blur inside it — appeared mid-animation, at a size that changed every
/// frame. Scaling to nothing reads the same and costs no layer at all.
///
/// At rest the child is laid out but not painted ([Transform] skips a subtree
/// whose matrix has a zero determinant), it is dropped from the semantics
/// tree, its tickers are muted, and its picture is cached behind a
/// [RepaintBoundary] so scaling re-composites rather than re-records it. A
/// closed slot costs a cached layout and nothing else.
class SqueezeSlot extends StatelessWidget {
  const SqueezeSlot({
    super.key,
    required this.open,
    required this.motion,
    required this.child,
  });

  final bool open;
  final Motion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ParkedMotionBuilder(
      value: open ? 1.0 : 0.0,
      motion: motion,
      child: child,
      builder: (context, factor, child) {
        final f = factor.clamp(0.0, 1.0);
        return TickerMode(
          enabled: f > 0,
          child: ExcludeSemantics(
            excluding: f <= 0,
            child: Align(
              widthFactor: f,
              child: Transform.scale(
                scale: f,
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}
