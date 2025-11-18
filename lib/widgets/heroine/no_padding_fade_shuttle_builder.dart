import 'package:flutter/widgets.dart';
import 'package:heroine/heroine.dart';

/// A [FadeShuttleBuilder] variant that ignores [MediaQuery] padding tweaks.
///
/// The default builder tweens the padding between `from` and `to` heroes to
/// account for differing safe areas, which can cause a slight jump when the
/// layout already handles the padding itself. This builder keeps the raw
/// positions so the hero lands exactly where the destination widget is laid out.
class NoPaddingFadeShuttleBuilder extends FadeShuttleBuilder {
  const NoPaddingFadeShuttleBuilder();

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    double remapValue() =>
        flightDirection == HeroFlightDirection.push
            ? animation.value
            : 1 - animation.value;

    return AnimatedBuilder(
      animation: animation,
      builder:
          (context, _) => buildHero(
            flightContext: flightContext,
            fromHero: fromHeroContext.widget,
            toHero: toHeroContext.widget,
            valueFromTo: remapValue(),
            flightDirection: flightDirection,
          ),
    );
  }
}
