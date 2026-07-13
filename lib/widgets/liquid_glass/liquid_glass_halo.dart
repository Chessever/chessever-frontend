import 'package:flutter/material.dart';

/// Readability backing for a floating liquid-glass island.
///
/// Glass chips float over live, scrolling page content. Because the glass is
/// translucent, whatever sits directly behind a chip bleeds through and can
/// wreck the legibility of the chip's own text/icons (bright board images,
/// white cards, etc.). Native "liquid glass" UIs solve this with a cheap
/// contrast layer *between* the page and the glass — a subtle tint/halo — never
/// an extra `BackdropFilter` (that would double the blur cost).
///
/// The trick here: a chip is translucent, so a plain [BoxShadow] painted behind
/// it is *visible through the glass*. One soft dark shadow therefore does two
/// jobs at once:
///   1. its solid centre tints the whole chip footprint darker → text pops;
///   2. its blurred edge reads as a floating drop halo → the chip lifts off the
///      content instead of dissolving into it.
///
/// Cost: shadows are a single rasterised rounded rect — no `saveLayer`, no
/// backdrop sampling, no per-frame blur. Effectively free, unlike a real blur
/// scrim. Wrap each discrete floating island (back button, segment bar, pill…)
/// so the readability travels *with* the chip and never reads as a solid bar.
class LiquidGlassHalo extends StatelessWidget {
  const LiquidGlassHalo({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.intensity = 1.0,
  });

  final Widget child;

  /// Corner radius of the tint/halo. Match the wrapped chip so the tint doesn't
  /// peek past rounded corners. A plain rounded rect approximates the glass
  /// superellipse closely enough once blurred.
  final double borderRadius;

  /// Scales the whole effect (0 = off). Nudge down for already-dark surfaces,
  /// up over especially busy content.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    if (intensity <= 0) return child;

    final radius = BorderRadius.circular(borderRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          // Tight, denser fill — sits right behind the chip footprint and
          // shows through the glass as a contrast tint under the text.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22 * intensity),
            blurRadius: 8,
            spreadRadius: 0.5,
          ),
          // Wider, softer ambient halo — the visible "floating" lift.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16 * intensity),
            blurRadius: 22,
            spreadRadius: -3,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // Clip so the tint fill never bleeds over the chip's own rounded edge.
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}
