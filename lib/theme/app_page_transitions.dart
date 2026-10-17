import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Flutter's default page transitions, except on Android, where
/// [GestureSyncedPredictiveBackBuilder] keeps every page's transition in step
/// with the navigator's user-gesture flag.
const PageTransitionsTheme kAppPageTransitionsTheme = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: GestureSyncedPredictiveBackBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: ZoomPageTransitionsBuilder(),
    TargetPlatform.linux: ZoomPageTransitionsBuilder(),
  },
);

/// [PredictiveBackPageTransitionsBuilder] that rebuilds when the navigator's
/// user gesture starts or stops.
///
/// The stock builder picks between two different widget trees by reading
/// `route.popGestureInProgress`, which is the navigator-wide gesture flag,
/// but only rebuilds when the route's own animations tick. A modal sheet's
/// swipe-to-dismiss holds that flag until its exit settles, so the page
/// under it is rebuilt into the predictive-back tree when the sheet pops and
/// is left there. The next route pushed over it swaps it back, creating a
/// fresh `RenderFractionalTranslation` in the same frame that a popup menu
/// positions itself by walking that page's render tree: "RenderBox was not
/// laid out" and a grey screen (CHESSEVER-12R). Listening to the flag makes
/// the swap happen when the gesture ends, with nothing reading the page.
class GestureSyncedPredictiveBackBuilder extends PageTransitionsBuilder {
  const GestureSyncedPredictiveBackBuilder();

  static const PredictiveBackPageTransitionsBuilder _predictiveBack =
      PredictiveBackPageTransitionsBuilder();

  static final ValueNotifier<bool> _noNavigator = ValueNotifier<bool>(false);

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _predictiveBack.delegatedTransition;

  @override
  Duration get transitionDuration => _predictiveBack.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _predictiveBack.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return ListenableBuilder(
      listenable: route.navigator?.userGestureInProgressNotifier ?? _noNavigator,
      builder: (context, _) => _predictiveBack.buildTransitions<T>(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      ),
    );
  }
}
