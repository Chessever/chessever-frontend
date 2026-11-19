import 'package:flutter/widgets.dart';

/// Plays the app's motion as designed whatever the system's motion setting.
///
/// Android reports reduced motion ([MediaQueryData.disableAnimations])
/// whenever the animator duration scale is 0, which many OEM battery savers
/// set without the reader asking for it; there the scroll chrome, the search
/// morph and every spring lost their motion. Product decision (2026-11-20):
/// the app looks the same on every phone, so the flag reads false for
/// everything under the app's navigator. Screen readers
/// ([MediaQueryData.accessibleNavigation]) are still honoured.
class AppMotionAlwaysOn extends StatelessWidget {
  const AppMotionAlwaysOn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    if (!data.disableAnimations) return child;
    return MediaQuery(
      data: data.copyWith(disableAnimations: false),
      child: child,
    );
  }
}
