import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// The app's one press: whatever it wraps goes down under the finger and,
/// let go, springs back with a little overshoot.
///
/// Every tap shows it. A quick tap lifts the finger before a press would
/// have drawn a frame, so the press is held for [minHold] before it lets go:
/// the control always answers. A finger that starts to drag (a scroll) is
/// not a press, and the control goes back at once with no pop.
///
/// It only draws. Taps, long presses and semantics stay with the control
/// it wraps; this reads raw pointer events beside the gesture arena and
/// never enters it.
class PressSpring extends StatefulWidget {
  const PressSpring({
    super.key,
    required this.child,
    this.pressedScale = 0.94,
    this.delay = Duration.zero,
    this.builder,
  });

  final Widget child;

  /// The scale at full press.
  final double pressedScale;

  /// How long a touch waits before it shows as a press. Zero for controls
  /// off any scroll (a bar, a floating button); a beat for rows in a list,
  /// so a scroll that starts on a row does not dip it first.
  final Duration delay;

  /// Draws [child] at press `press` (0 at rest, 1 fully pressed; a little
  /// under 0 in the overshoot of the release). Null scales [child] by
  /// [pressedScale].
  final Widget Function(BuildContext context, double press, Widget child)?
  builder;

  /// The shortest press a tap shows.
  static const minHold = Duration(milliseconds: 90);

  /// Down: fast, following the finger.
  static const down = CupertinoMotion.interactive(
    duration: Duration(milliseconds: 140),
  );

  /// Up: back past rest and settling, the control popping into place.
  static const up = CupertinoMotion.bouncy(
    duration: Duration(milliseconds: 420),
    extraBounce: 0.05,
    snapToEnd: true,
  );

  @override
  State<PressSpring> createState() => _PressSpringState();
}

class _PressSpringState extends State<PressSpring> {
  bool _pressed = false;
  int? _pointer;
  Offset _origin = Offset.zero;
  DateTime? _pressedAt;
  Timer? _delay;
  Timer? _release;

  @override
  void dispose() {
    _delay?.cancel();
    _release?.cancel();
    super.dispose();
  }

  void _set(bool value) {
    if (value) _pressedAt = DateTime.now();
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _origin = event.position;
    _release?.cancel();
    if (widget.delay == Duration.zero) {
      _set(true);
    } else {
      _delay = Timer(widget.delay, () => _set(true));
    }
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if ((event.position - _origin).distance <= kTouchSlop) return;
    // A drag: a scroll or a swipe, not a press.
    _end();
    _set(false);
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final waiting = _delay?.isActive ?? false;
    _end();
    if (waiting) _set(true);
    if (!_pressed) return;
    final held = DateTime.now().difference(_pressedAt ?? DateTime.now());
    final left = PressSpring.minHold - held;
    if (left <= Duration.zero) {
      _set(false);
    } else {
      _release = Timer(left, () => _set(false));
    }
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _end();
    _set(false);
  }

  void _end() {
    _pointer = null;
    _delay?.cancel();
    _delay = null;
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final pressedScale = widget.pressedScale;
    final builder =
        widget.builder ??
        (context, press, child) {
          final scale = 1 - (1 - pressedScale) * press;
          return Transform.scale(
            scale: (scale - 1).abs() < 0.001 ? 1.0 : scale,
            child: child,
          );
        };
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: SingleMotionBuilder(
        motion: _pressed ? PressSpring.down : PressSpring.up,
        value: _pressed ? 1.0 : 0.0,
        // Reduced motion: no travel, and no pop.
        active: !reduce,
        child: widget.child,
        builder: (context, press, child) =>
            builder(context, reduce ? 0 : press, child!),
      ),
    );
  }
}
