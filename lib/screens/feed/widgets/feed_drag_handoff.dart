import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Lets a vertical scroll inside a Feed page give its drag to the pages.
///
/// A scrollable inside a page wins every vertical drag that starts on it. One
/// that has nowhere to go (its content fits, or it stands at its edge) would
/// hold the finger there and the Feed would not turn. Here that drag carries
/// on, the same gesture, on the enclosing vertical Scrollable (Feed's
/// PageView, the first page's pull-to-refresh included) until the finger
/// lifts.
///
/// It only listens: the scrollable under it keeps every drag it can use.
class FeedDragHandoff extends StatefulWidget {
  const FeedDragHandoff({required this.child, this.enabled = true, super.key});

  /// False keeps the drag where it started.
  final bool enabled;
  final Widget child;

  @override
  State<FeedDragHandoff> createState() => _FeedDragHandoffState();
}

class _FeedDragHandoffState extends State<FeedDragHandoff> {
  ScrollableState? _pages;
  Drag? _pageDrag;
  ScrollHoldController? _innerHold;
  VelocityTracker? _velocity;
  int? _pointer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pages = Scrollable.maybeOf(context, axis: Axis.vertical);
  }

  @override
  void dispose() {
    // The enclosing Scrollable owns its drag activity's disposal. Avoid
    // calling back into that ancestor while its subtree is being removed.
    _pageDrag = null;
    _innerHold = null;
    super.dispose();
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _velocity?.addPosition(event.timeStamp, event.position);
    _pageDrag?.update(
      DragUpdateDetails(
        sourceTimeStamp: event.timeStamp,
        delta: Offset(0, event.delta.dy),
        primaryDelta: event.delta.dy,
        globalPosition: event.position,
        localPosition: event.localPosition,
      ),
    );
  }

  void _pointerEnd(PointerEvent event, {bool cancelled = false}) {
    if (event.pointer != _pointer) return;
    _velocity?.addPosition(event.timeStamp, event.position);
    final drag = _pageDrag;
    _pageDrag = null;
    if (cancelled) {
      drag?.cancel();
    } else {
      final speed = (_velocity?.getVelocity().pixelsPerSecond.dy ?? 0).clamp(
        -4000.0,
        4000.0,
      );
      drag?.end(
        DragEndDetails(
          velocity: Velocity(pixelsPerSecond: Offset(0, speed)),
          primaryVelocity: speed,
        ),
      );
    }
    _innerHold?.cancel();
    _innerHold = null;
    _pointer = null;
    _velocity = null;
  }

  bool _handoff(ScrollNotification notification) {
    if (!widget.enabled ||
        notification.depth != 0 ||
        notification is! OverscrollNotification ||
        notification.metrics.axis != Axis.vertical ||
        notification.dragDetails == null ||
        _pageDrag != null ||
        _pointer == null) {
      return false;
    }
    final pages = _pages;
    if (pages == null ||
        !pages.mounted ||
        !pages.position.physics.shouldAcceptUserOffset(pages.position)) {
      return false;
    }
    final details = notification.dragDetails!;
    final remainder = -notification.overscroll;
    _pageDrag = pages.position.drag(
      DragStartDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        globalPosition: details.globalPosition - Offset(0, remainder),
        localPosition: details.localPosition - Offset(0, remainder),
      ),
      () => _pageDrag = null,
    );
    // Cancel the inner recognizer's scroll activity. Its Scrollable clears
    // its drag reference, and the raw pointer listener continues the SAME
    // gesture on the outer position until release or cancellation.
    final from = notification.context;
    final inner = from == null ? null : Scrollable.maybeOf(from);
    if (inner != null && !identical(inner, pages)) {
      _innerHold = inner.position.hold(() => _innerHold = null);
    }
    _pageDrag?.update(
      DragUpdateDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        delta: Offset(0, remainder),
        primaryDelta: remainder,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _pointerDown,
    onPointerMove: _pointerMove,
    onPointerUp: _pointerEnd,
    onPointerCancel: (event) => _pointerEnd(event, cancelled: true),
    child: NotificationListener<ScrollNotification>(
      onNotification: _handoff,
      child: widget.child,
    ),
  );
}
