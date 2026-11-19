import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/widgets.dart';

/// The tone that rises under the foot of every Feed post, from the board
/// block's foot down to the screen's edge, under the dock.
///
/// It is one still layer under the pages: the posts are transparent, so
/// they page over it the way a reel's shade stays put while the reel moves.
/// The chart is drawn straight on it with no box of its own, so the board
/// flows into the curve below it.
///
/// It starts at the page's own ground, so its top has no edge, and deepens
/// over many eased steps (no band, no seam): in dark toward the surface
/// tone, on paper toward a step of the recessed tone.
class FeedBottomDeck extends StatelessWidget {
  const FeedBottomDeck({super.key});

  /// Steps the gradient is drawn in.
  static const int steps = 14;

  /// How far toward the recessed tone the deck reaches on paper.
  static const double lightStrength = 0.45;

  /// The deck's tone [t] of the way down it (0 at its top, the page's own
  /// ground; 1 at its foot).
  static Color toneAt(BuildContext context, double t) {
    final colors = context.colors;
    final from = colors.background;
    final to = context.isLightTheme
        ? Color.alphaBlend(
            colors.surfaceRecessed.withValues(alpha: lightStrength),
            colors.background,
          )
        : colors.surface;
    return Color.lerp(from, to, _ease(t.clamp(0.0, 1.0)))!;
  }

  /// Eased in and out (smoothstep), so the deck neither starts nor ends on
  /// a slope break the eye reads as a line.
  static double _ease(double t) => t * t * (3 - 2 * t);

  @override
  Widget build(BuildContext context) {
    final stops = <double>[];
    final tones = <Color>[];
    for (var i = 0; i < steps; i++) {
      final t = i / (steps - 1);
      stops.add(t);
      tones.add(toneAt(context, t));
    }
    return IgnorePointer(
      child: DecoratedBox(
        key: const ValueKey('feed_bottom_deck'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: tones,
            stops: stops,
          ),
        ),
      ),
    );
  }
}
