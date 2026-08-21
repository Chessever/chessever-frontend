import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays its child out at the tallest height this slot has ever offered, and
/// clips whatever no longer fits.
///
/// Use it for the page content underneath something that grows downward — a
/// search panel unrolling, a banner sliding in. Those animations push content
/// down by *taking layout space away from it*, which re-runs layout on
/// everything below on every frame of the animation. On the events screen that
/// was 35 full layout passes of the `PageView`, its viewport and its sliver
/// over a single 200ms focus.
///
/// Holding the child's height turns the subtree into a cached layout that the
/// animation only slides. That is what pushing content down looks like anyway:
/// the content moves down and its bottom edge goes off the slot. The one
/// behavioural difference is that the child keeps its full scroll viewport
/// rather than shrinking, so the hidden strip stays part of the scrollable
/// area instead of being carved out of it.
///
/// The latch resets when the slot's width changes, so rotation and resizes
/// re-measure. It only ever grows, and the resting (nothing pushing) state is
/// the tallest, so a cold start that begins in the pushed state self-corrects
/// on the first resting frame.
class StableHeightSlot extends SingleChildRenderObjectWidget {
  const StableHeightSlot({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderStableHeightSlot();
}

class RenderStableHeightSlot extends RenderProxyBox {
  double _latchedWidth = -1;
  double _latchedHeight = 0;

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) return;

    if (constraints.maxWidth != _latchedWidth) {
      _latchedWidth = constraints.maxWidth;
      _latchedHeight = 0;
    }
    if (constraints.maxHeight.isFinite) {
      _latchedHeight = max(_latchedHeight, constraints.maxHeight);
    }

    child.layout(
      _latchedHeight > 0
          ? BoxConstraints.tight(Size(size.width, _latchedHeight))
          : constraints,
      parentUsesSize: true,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
    );
  }
}
