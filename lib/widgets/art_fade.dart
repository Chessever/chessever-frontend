import 'dart:math' as math;

import 'package:flutter/widgets.dart';

// Light-theme pictures on cards (a player's photo, a federation's flag, a
// favourites mosaic) fade by masking their OWN alpha into the card surface
// with a `BlendMode.dstIn` mask. Nothing is laid over them: wherever the
// picture shows it shows at its true colour, and it only thins out where
// the card needs the room for its words. A wash of the surface colour over
// the picture (the old light veil) bleached photos and flags from one edge.
//
// Every ramp here is smootherstep-eased over many stops, so even a long
// fade never shows a band or a line where it starts.

/// Steps in each fade. Enough that a fade across a whole card is smooth.
const int kArtFadeSteps = 16;

/// Smootherstep: no slope at either end, so a fade neither starts nor
/// stops on an edge the eye can find.
double artFadeEase(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * x * (x * (x * 6 - 15) + 10);
}

const Color _kOpaque = Color(0xFF000000);

/// The alpha ramp every fade here shares: opaque from 0 to [hold], then
/// eased to clear at 1.
({List<Color> colors, List<double> stops}) _ramp(double hold, int steps) {
  final start = hold.clamp(0.0, 1.0);
  final colors = <Color>[_kOpaque];
  final stops = <double>[0];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    stops.add(start + (1 - start) * t);
    colors.add(_kOpaque.withValues(alpha: 1 - artFadeEase(t)));
  }
  return (colors: colors, stops: stops);
}

/// A straight fade for a `dstIn` mask: opaque at [opaque], and for the
/// first [hold] of the way, then eased to clear at [clear].
LinearGradient artFadeLinear({
  required Alignment opaque,
  required Alignment clear,
  double hold = 0,
  int steps = kArtFadeSteps,
}) {
  final ramp = _ramp(hold, steps);
  return LinearGradient(
    begin: opaque,
    end: clear,
    colors: ramp.colors,
    stops: ramp.stops,
  );
}

/// An elliptical fade for a `dstIn` mask, anchored on [corner] of [bounds]:
/// opaque for the first [hold] of the way out, clear at the ellipse whose
/// half-axes are [reach] (shares of the box's width and height).
///
/// Unlike two crossed straight fades it needs one layer, and its falloff
/// is round, so a picture leaves the corner it sits in as a single soft
/// shape instead of a rectangle with blurred sides.
Shader artFadeCorner(
  Rect bounds, {
  Alignment corner = Alignment.topRight,
  required Size reach,
  double hold = 0.5,
  int steps = kArtFadeSteps,
}) {
  if (bounds.isEmpty) {
    return const LinearGradient(
      colors: [_kOpaque, _kOpaque],
    ).createShader(bounds);
  }
  final rx = math.max(1.0, bounds.width * reach.width);
  final ry = math.max(1.0, bounds.height * reach.height);
  final ramp = _ramp(hold, steps);
  return RadialGradient(
    center: corner,
    // A circle of radius ry, stretched sideways about the corner into the
    // rx-by-ry ellipse.
    radius: ry / bounds.shortestSide,
    colors: ramp.colors,
    stops: ramp.stops,
    transform: _StretchX(corner.withinRect(bounds).dx, rx / ry),
  ).createShader(bounds);
}

/// Scales a gradient horizontally by [factor] about the vertical line at
/// [originX].
class _StretchX extends GradientTransform {
  const _StretchX(this.originX, this.factor);

  final double originX;
  final double factor;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.diagonal3Values(factor, 1, 1)
        ..setTranslationRaw(originX * (1 - factor), 0, 0);
}

/// [child], faded through its own alpha by [shader].
class ArtFade extends StatelessWidget {
  const ArtFade({super.key, required this.shader, required this.child});

  final Shader Function(Rect bounds) shader;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: shader,
      child: child,
    );
  }
}

/// Light theme: a player search card's flag and portrait as one picture,
/// at true colour, leaving the card from its top-right corner. The name,
/// rating and title sit bottom-left on the card's own surface, which the
/// picture dissolves into before it gets there; a compact (half-width)
/// card, whose name runs further right, dissolves sooner toward the foot.
///
/// The flag keeps its own proportions, anchored right behind the portrait,
/// so it reads as the whole flag (not a zoomed crop of one stripe), and the
/// fade never reaches past its left edge, so that edge never shows.
///
/// For a card's [Stack]: it fills the card.
class PlayerCardLightArt extends StatelessWidget {
  const PlayerCardLightArt({
    super.key,
    required this.compact,
    required this.portrait,
    this.flag,
  });

  final bool compact;

  /// The flag, covering a box of [flagAspect] at the card's right.
  final Widget? flag;

  /// The portrait, positioned in the card's [Stack] (it overhangs the
  /// card's right edge). Fade it with [portraitFade] so it gives way to the
  /// flag on its left.
  final Widget portrait;

  /// Width over height of the flag's box (the flags are drawn 3:2).
  static const double flagAspect = 1.5;

  /// How far the picture reaches from the top-right corner at most, as
  /// shares of the card's width and height.
  static Size reach({required bool compact}) =>
      compact ? const Size(0.82, 0.86) : const Size(0.62, 1.25);

  /// Opaque for this share of the way out.
  static const double hold = 0.45;

  /// The flag's width on a card of [size].
  static double flagWidth(Size size) =>
      math.min(size.width, size.height * flagAspect);

  /// The picture's fade on a card of [size]: [reach], held inside the
  /// flag's box.
  static Size fadeReach(Size size, {required bool compact}) {
    final share = reach(compact: compact);
    if (size.width <= 0) return share;
    final rx = math.min(share.width * size.width, flagWidth(size));
    return Size(rx / size.width, share.height);
  }

  /// A compact card's flag leaves the corner sooner than the portrait: a
  /// long name reaches under the portrait's side, and with no photo over it
  /// the flag would sit at full strength behind the name's last letters.
  static const Size compactFlagReach = Size(0.72, 0.64);
  static const double compactFlagHold = 0.3;

  /// The portrait's own fade: whole on the right, giving way to the flag
  /// over its left two thirds.
  static final LinearGradient portraitFade = artFadeLinear(
    opaque: Alignment.centerRight,
    clear: Alignment.centerLeft,
    hold: 0.3,
  );

  @override
  Widget build(BuildContext context) {
    final flagWidget = flag;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          final fade = fadeReach(size, compact: compact);
          final flagBox = flagWidth(size);
          // The flag's box shares the card's top-right corner, so its own
          // fade is the card's, measured in the box.
          final flagFade = Size(
            flagBox > 0 ? compactFlagReach.width * size.width / flagBox : 0,
            compactFlagReach.height,
          );
          return ArtFade(
            shader: (bounds) => artFadeCorner(bounds, reach: fade, hold: hold),
            child: Stack(
              children: [
                if (flagWidget != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: flagBox,
                    child: compact
                        ? ArtFade(
                            shader: (bounds) => artFadeCorner(
                              bounds,
                              reach: flagFade,
                              hold: compactFlagHold,
                            ),
                            child: flagWidget,
                          )
                        : flagWidget,
                  ),
                portrait,
              ],
            ),
          );
        },
      ),
    );
  }
}
