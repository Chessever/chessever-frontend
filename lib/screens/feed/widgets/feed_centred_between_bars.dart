import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A Feed page's post, kept centred in what the bars leave of the screen as
/// they come and go, without being laid out again.
///
/// The page is laid out once, clear of the bars as they stand when shown
/// (see `FeedScreen`), so a post never changes size and is never under a bar
/// at rest. As the bars leave, the post moves by [travel] times how far they
/// have gone (`1 - chrome.value`), on the bars' own spring value, so in every
/// frame its centre sits on the centre of the room between them: with the
/// bars away the post is framed in the middle of the screen rather than
/// sitting under one empty strip and over another.
///
/// The move is a transform: taps, the semantics tree and every measurement
/// follow the post to where it is drawn. Nothing rebuilds and nothing lays
/// out while it moves; the post is repainted at its new place from its own
/// layer.
class FeedCentredBetweenBars extends SingleChildRenderObjectWidget {
  FeedCentredBetweenBars({
    super.key,
    required this.chrome,
    required this.travel,
    required Widget child,
  }) : super(child: RepaintBoundary(child: child));

  /// How much of the bars is on screen: 1 shown, 0 away (the shell's scroll
  /// chrome).
  final ValueListenable<double> chrome;

  /// How far the post moves (down positive) once the bars are all the way
  /// away ([travelFor]).
  final double travel;

  /// The move that keeps a post centred between the bars: half of what its
  /// room gains at the bottom when the bars go, less half of what it gains
  /// at the top. [shown] and [away] are the room's insets from the screen's
  /// edges with the bars shown and with them away.
  static double travelFor({
    required EdgeInsets shown,
    required EdgeInsets away,
  }) => ((shown.bottom - away.bottom) - (shown.top - away.top)) / 2;

  @override
  RenderFeedCentredBetweenBars createRenderObject(BuildContext context) =>
      RenderFeedCentredBetweenBars(chrome: chrome, travel: travel);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFeedCentredBetweenBars renderObject,
  ) {
    renderObject
      ..chrome = chrome
      ..travel = travel;
  }
}

/// The render object of [FeedCentredBetweenBars]: paints, hit-tests and
/// reports its child [offsetY] down from where it is laid out.
class RenderFeedCentredBetweenBars extends RenderProxyBox {
  RenderFeedCentredBetweenBars({required this._chrome, required this._travel});

  ValueListenable<double> _chrome;
  set chrome(ValueListenable<double> value) {
    if (identical(value, _chrome)) return;
    if (attached) {
      _chrome.removeListener(_moved);
      value.addListener(_moved);
    }
    _chrome = value;
    _moved();
  }

  double _travel;
  set travel(double value) {
    if (value == _travel) return;
    _travel = value;
    _moved();
  }

  /// Where the child was last painted, to skip a repaint that moves nothing.
  double? _paintedAt;

  /// How far below its laid-out place the child is drawn now.
  double get offsetY => (1 - _chrome.value.clamp(0.0, 1.0)) * _travel;

  void _moved() {
    if (offsetY == _paintedAt) return;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _chrome.addListener(_moved);
  }

  @override
  void detach() {
    _chrome.removeListener(_moved);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final dy = offsetY;
    _paintedAt = dy;
    context.paintChild(child, offset.translate(0, dy));
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // The post answers where it is drawn, moved or not.
    if (!(Offset(0, offsetY) & size).contains(position)) return false;
    if (hitTestChildren(result, position: position) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintOffset(
      offset: Offset(0, offsetY),
      position: position,
      hitTest: (result, transformed) =>
          child?.hitTest(result, position: transformed) ?? false,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, offsetY, 0, 1);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('travel', _travel))
      ..add(DoubleProperty('offsetY', offsetY));
  }
}
