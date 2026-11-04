import 'dart:math' as math;

import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Keeps a playable board and its controls reachable in a short, wide window.
///
/// Normal pages retain their exact geometry. A short landscape post scrolls
/// within a readable column. At either edge its drag continues on the enclosing
/// PageView, including the first page's existing pull-to-refresh gesture.
class FeedPageViewport extends StatefulWidget {
  const FeedPageViewport({required this.builder, super.key});

  final LayoutWidgetBuilder builder;

  @override
  State<FeedPageViewport> createState() => _FeedPageViewportState();
}

class _FeedPageViewportState extends State<FeedPageViewport> {
  final ScrollController _content = ScrollController();
  ScrollableState? _pages;
  Drag? _pageDrag;
  ScrollHoldController? _contentHold;
  VelocityTracker? _velocity;
  int? _pointer;
  bool _shortWide = false;

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
    _contentHold = null;
    _content.dispose();
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
    _contentHold?.cancel();
    _contentHold = null;
    _pointer = null;
    _velocity = null;
  }

  bool _handoff(ScrollNotification notification) {
    if (!_shortWide ||
        notification.depth != 0 ||
        notification is! OverscrollNotification ||
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
    _contentHold = _content.position.hold(() => _contentHold = null);
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _shortWide =
          constraints.maxHeight < 500 &&
          constraints.maxWidth > constraints.maxHeight * 1.6;
      final width = _shortWide
          ? math.min(420.0, constraints.maxWidth)
          : constraints.maxWidth;
      final height = _shortWide
          ? math.max(
              constraints.maxHeight,
              FeedLayout.naturalHeight(
                    width,
                    MediaQuery.textScalerOf(context),
                    evalWidth: 20.w,
                  ) +
                  96,
            )
          : constraints.maxHeight;
      return Align(
        alignment: Alignment.topCenter,
        child: Listener(
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerEnd,
          onPointerCancel: (event) => _pointerEnd(event, cancelled: true),
          child: NotificationListener<ScrollNotification>(
            onNotification: _handoff,
            child: SingleChildScrollView(
              controller: _content,
              primary: false,
              physics: _shortWide
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: width,
                height: height,
                child: LayoutBuilder(builder: widget.builder),
              ),
            ),
          ),
        ),
      );
    },
  );
}
