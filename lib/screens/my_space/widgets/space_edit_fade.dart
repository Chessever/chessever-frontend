import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// Edit's own pace for a card's control fading out and back: quick and calm,
/// landing exactly on its end.
const Motion kSpaceEditFadeMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 220),
  snapToEnd: true,
);

/// A card's own control (a smart event's or a Prep profile's star) while My
/// Space is in Edit, where a tap selects the card: the control keeps its
/// place, so nothing on the card reflows as Edit comes and goes, but fades
/// out on [kSpaceEditFadeMotion] and takes no taps or screen-reader actions
/// until Edit ends. Under reduced motion it simply hides and shows.
class SpaceEditFade extends StatelessWidget {
  const SpaceEditFade({super.key, required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: hidden,
      child: ExcludeSemantics(
        excluding: hidden,
        child: SingleMotionBuilder(
          value: hidden ? 0.0 : 1.0,
          motion: kSpaceEditFadeMotion,
          active: !reduceMotion,
          // A spring only approaches its end: land exactly on it, so a
          // hidden control is not painted at all and a shown one is whole.
          builder: (context, value, child) => Opacity(
            opacity: value < 0.01
                ? 0.0
                : value > 0.99
                ? 1.0
                : value,
            child: child,
          ),
          child: child,
        ),
      ),
    );
  }
}
