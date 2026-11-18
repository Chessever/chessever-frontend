import 'dart:math' as math;

import 'package:chessever2/widgets/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// The search button turning into the search field.
///
/// A list's search floats as a round glass button. Tapped, the page swaps its
/// header for the search field (already there, already focused, the list
/// still under it); this draws, over that, the button's own glass growing
/// from where the button was into the field's place on a spring, its
/// magnifier gliding to the field's leading icon, then lets go of the field
/// underneath. Nothing waits on it: the field is live from the first frame
/// and the morph is only paint on top.
///
/// The field is found as whatever holds focus once the page has swapped its
/// header, so every page with an autofocused search field gets the morph
/// without knowing about it.
class SearchMorph {
  const SearchMorph._();

  /// The spring the glass travels on: critically damped, a touch longer
  /// than a press so the eye can follow the shape across the screen.
  static const CupertinoMotion motion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 320),
    snapToEnd: true,
  );

  /// Plays from [from] (the button, in global coordinates) to the focused
  /// field, a frame after the page has rebuilt with it.
  static void play(BuildContext context, Rect from) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    // Two frames: the header swap builds, then the field takes focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final to = _focusedFieldRect();
        if (to == null || !overlay.mounted) return;
        final overlayBox = overlay.context.findRenderObject() as RenderBox?;
        if (overlayBox == null || !overlayBox.hasSize) return;
        final origin = overlayBox.localToGlobal(Offset.zero);
        late final OverlayEntry entry;
        entry = OverlayEntry(
          builder: (_) => IgnorePointer(
            child: _MorphLayer(
              from: from.shift(-origin),
              to: to.shift(-origin),
              onDone: () {
                if (entry.mounted) entry.remove();
              },
            ),
          ),
        );
        overlay.insert(entry);
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  /// The search field's box: the focused text's nearest ancestor that is a
  /// field-shaped row (wider than the text, about a finger tall).
  static Rect? _focusedFieldRect() {
    final focused = FocusManager.instance.primaryFocus?.context;
    final box = focused?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final text = box.localToGlobal(Offset.zero) & box.size;
    RenderObject? node = box.parent;
    Rect best = text;
    while (node != null) {
      if (node is RenderBox && node.hasSize) {
        final size = node.size;
        if (size.height > 64) break;
        if (size.width >= text.width + 24 && size.height >= 32) {
          best = node.localToGlobal(Offset.zero) & size;
        }
      }
      node = node.parent;
    }
    return best;
  }
}

class _MorphLayer extends StatefulWidget {
  const _MorphLayer({
    required this.from,
    required this.to,
    required this.onDone,
  });

  final Rect from;
  final Rect to;
  final VoidCallback onDone;

  @override
  State<_MorphLayer> createState() => _MorphLayerState();
}

class _MorphLayerState extends State<_MorphLayer>
    with SingleTickerProviderStateMixin {
  late final BoundedSingleMotionController _t = BoundedSingleMotionController(
    motion: SearchMorph.motion,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _t.animateTo(1).whenCompleteOrCancel(widget.onDone);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value.clamp(0.0, 1.0);
        final rect = Rect.lerp(widget.from, widget.to, t)!;
        final startRadius = widget.from.shortestSide / 2;
        final endRadius = math.min(12.0, widget.to.height / 2);
        final radius = startRadius + (endRadius - startRadius) * t;
        // The field underneath takes over for the last stretch.
        final fade = t < 0.72 ? 1.0 : (1 - (t - 0.72) / 0.28).clamp(0.0, 1.0);
        // The magnifier glides from the button's centre to the field's
        // leading icon.
        final iconFrom = widget.from.center;
        final iconTo = Offset(widget.to.left + 22, widget.to.center.dy);
        final icon = Offset.lerp(iconFrom, iconTo, t)!;
        final style = GlassStyle.of(context);
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Opacity(
                opacity: fade,
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(radius),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              left: icon.dx - 11,
              top: icon.dy - 11,
              width: 22,
              height: 22,
              child: Opacity(
                opacity: fade,
                child: Icon(Icons.search_rounded, size: 22, color: style.ink),
              ),
            ),
          ],
        );
      },
    );
  }
}
