import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Keeps the page's iOS edge swipe off the board.
///
/// The board route pops by the iOS back swipe, which listens on a strip
/// along the leading edge of the screen (20pt, or the notch's inset in
/// landscape). With the eval bar hidden the board starts at that edge, so a
/// piece dragged off the a-file (the h-file, flipped) would start the swipe
/// too and could pop the board in the middle of a move.
///
/// A pointer that goes down on [child] inside that strip is claimed for the
/// board as soon as it travels [claimSlop] across, well before the swipe's
/// own slop: the swipe loses and the piece moves. A finger held still (the
/// board's long press) or one that only travels up or down is never
/// claimed, and a swipe that starts anywhere off the board (the app bar,
/// the notation) still goes back. Only where the platform swipes back
/// (iOS, macOS); elsewhere [child] is returned as it is.
class BoardEdgeGuard extends StatelessWidget {
  const BoardEdgeGuard({super.key, required this.child});

  final Widget child;

  /// The edge strip the iOS back swipe listens on (Flutter's
  /// `_kBackGestureWidth`, widened to the notch's inset).
  static const double backSwipeStrip = 20;

  /// How far across a pointer from the strip travels before the board
  /// claims it: a third of the touch slop the back swipe waits for, past a
  /// held finger's wobble.
  static const double claimSlop = kTouchSlop / 3;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform != TargetPlatform.iOS && platform != TargetPlatform.macOS) {
      return child;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final padding = MediaQuery.paddingOf(context);
    final strip = math.max(backSwipeStrip, rtl ? padding.right : padding.left);
    final width = MediaQuery.sizeOf(context).width;
    bool inStrip(Offset global) =>
        rtl ? global.dx >= width - strip : global.dx <= strip;
    return RawGestureDetector(
      behavior: HitTestBehavior.deferToChild,
      gestures: <Type, GestureRecognizerFactory>{
        BoardEdgeClaim: GestureRecognizerFactoryWithHandlers<BoardEdgeClaim>(
          () => BoardEdgeClaim(debugOwner: this),
          (claim) => claim.inStrip = inStrip,
        ),
      },
      child: child,
    );
  }
}

/// Claims a pointer that went down in the back-swipe strip once it has
/// travelled [BoardEdgeGuard.claimSlop] across ([BoardEdgeGuard]).
class BoardEdgeClaim extends OneSequenceGestureRecognizer {
  BoardEdgeClaim({super.debugOwner});

  /// Whether a pointer going down at this global position is in the strip.
  bool Function(Offset globalPosition) inStrip = _nowhere;

  static bool _nowhere(Offset _) => false;

  final Map<int, double> _downX = <int, double>{};

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      inStrip(event.position) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _downX[event.pointer] = event.position.dx;
  }

  @override
  void handleEvent(PointerEvent event) {
    final from = _downX[event.pointer];
    if (from == null) return;
    if (event is PointerMoveEvent) {
      if ((event.position.dx - from).abs() <= BoardEdgeGuard.claimSlop) return;
      _downX.remove(event.pointer);
      resolvePointer(event.pointer, GestureDisposition.accepted);
      stopTrackingPointer(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _downX.remove(event.pointer);
      resolvePointer(event.pointer, GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    _downX.remove(pointer);
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    _downX.clear();
    super.dispose();
  }

  @override
  String get debugDescription => 'board edge claim';
}
