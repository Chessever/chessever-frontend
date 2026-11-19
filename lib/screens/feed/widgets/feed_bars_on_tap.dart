import 'dart:async';

import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A tap on a Feed post brings the tab's bars back, the way a tap on a reel
/// brings its chrome back: the reader who paged on and wants to leave never
/// has to page back first to find the bar.
///
/// Only a tap: a finger that moves past the touch slop is a page swipe, a
/// scrub or a drag, and a finger held past [kLongPressTimeout] is a press
/// (a player's focus menu, the hold-to-speed-up): neither changes anything
/// here. Nor a tap on the parts of a post that answer taps of their own in
/// quick succession ([FeedKeepsBars]: the board, which plays and pauses and
/// takes a move in two taps, the
/// chart, the scrub line and the action rail): bringing the bars back moves
/// the post to its place between them, and the second tap would land beside
/// the first, or the post would slide under the action that just answered.
///
/// It never takes a gesture from anything under it: it only listens.
class FeedBarsOnTap extends StatefulWidget {
  const FeedBarsOnTap({super.key, required this.chrome, required this.child});

  /// The tab's chrome; null (Feed pushed as a page) does nothing.
  final ScrollChromeController? chrome;
  final Widget child;

  /// Marks the pointer that went down at [context] as one a [FeedKeepsBars]
  /// part took: its tap leaves the bars where they are.
  static void keep(BuildContext context, int pointer) {
    context
        .getInheritedWidgetOfExactType<_FeedBarsOnTapScope>()
        ?.state
        ._kept
        .add(pointer);
  }

  @override
  State<FeedBarsOnTap> createState() => _FeedBarsOnTapState();
}

class _FeedBarsOnTapState extends State<FeedBarsOnTap> {
  /// Pointers a [FeedKeepsBars] part took, as they went down (it hears them
  /// first: a pointer's events reach the deepest listener first).
  final Set<int> _kept = {};

  /// The pointer that may still turn out a tap, and where it went down.
  int? _pointer;
  Offset? _down;

  /// Runs out when the pointer has been held long enough to be a press: it
  /// is no longer a tap.
  Timer? _pressDeadline;

  void _forget() {
    _pointer = null;
    _pressDeadline?.cancel();
    _pressDeadline = null;
  }

  void _onDown(PointerDownEvent event) {
    if (_pointer != null || _kept.contains(event.pointer)) {
      _forget();
      return;
    }
    _pointer = event.pointer;
    _down = event.position;
    _pressDeadline = Timer(kLongPressTimeout, _forget);
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final slop =
        MediaQuery.maybeGestureSettingsOf(context)?.touchSlop ?? kTouchSlop;
    if ((event.position - _down!).distance > slop) _forget();
  }

  void _onUp(PointerUpEvent event) {
    _kept.remove(event.pointer);
    if (event.pointer != _pointer) return;
    _forget();
    final chrome = widget.chrome;
    if (chrome != null && chrome.value < 1) chrome.show();
  }

  void _onCancel(PointerCancelEvent event) {
    _kept.remove(event.pointer);
    if (event.pointer == _pointer) _forget();
  }

  @override
  void dispose() {
    _pressDeadline?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FeedBarsOnTapScope(
      state: this,
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: widget.child,
      ),
    );
  }
}

class _FeedBarsOnTapScope extends InheritedWidget {
  const _FeedBarsOnTapScope({required this.state, required super.child});

  final _FeedBarsOnTapState state;

  @override
  bool updateShouldNotify(_FeedBarsOnTapScope oldWidget) => false;
}

/// A part of a post whose taps leave Feed's bars where they are (see
/// [FeedBarsOnTap]). It only listens; its child keeps every gesture.
class FeedKeepsBars extends StatelessWidget {
  const FeedKeepsBars({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => FeedBarsOnTap.keep(context, event.pointer),
    child: child,
  );
}
