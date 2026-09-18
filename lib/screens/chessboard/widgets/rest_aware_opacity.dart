import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// [Opacity] for a fade that spends almost all of its life at rest.
///
/// [RenderOpacity] is a repaint boundary with its own [OpacityLayer] at every
/// opacity above zero, a resting 1.0 included. Left around the whole board
/// body for a watch-mode fade, that kept an extra composited layer on every
/// game page for the life of the screen, video on or off. This paints its
/// child straight through when fully opaque and only pushes a layer while it
/// is actually translucent.
class RestAwareOpacity extends SingleChildRenderObjectWidget {
  const RestAwareOpacity({super.key, required this.opacity, super.child})
    : assert(opacity >= 0.0 && opacity <= 1.0);

  final double opacity;

  @override
  RenderRestAwareOpacity createRenderObject(BuildContext context) =>
      RenderRestAwareOpacity(opacity: opacity);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRestAwareOpacity renderObject,
  ) {
    renderObject.opacity = opacity;
  }
}

class RenderRestAwareOpacity extends RenderProxyBox {
  RenderRestAwareOpacity({double opacity = 1.0, RenderBox? child})
    : _alpha = Color.getAlphaFromOpacity(opacity),
      super(child);

  int _alpha;

  set opacity(double value) {
    final alpha = Color.getAlphaFromOpacity(value);
    if (alpha == _alpha) return;
    final wasComposited = alwaysNeedsCompositing;
    _alpha = alpha;
    // Ancestors clip with layers only while a layer exists below them.
    if (wasComposited != alwaysNeedsCompositing) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _alpha > 0 && _alpha < 255;

  @override
  bool paintsChild(RenderBox child) => _alpha > 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _alpha == 0) {
      layer = null;
      return;
    }
    if (_alpha == 255) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushOpacity(
      offset,
      _alpha,
      super.paint,
      oldLayer: layer as OpacityLayer?,
    );
  }
}
