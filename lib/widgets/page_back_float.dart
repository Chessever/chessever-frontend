import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/material.dart';

/// Retired: draws nothing.
///
/// It used to lay a glass back disc where the header's chevron was while the
/// header was scrolled away. The owner and PM removed it (2026-11-22: "a
/// standalone floating back button on the top left is redundant", seen on the
/// player profile, Events, Favorites and smart events): the way back is the
/// header itself (scrolling up brings it home, as the scroll chrome does
/// everywhere), the iOS edge swipe and the system back.
///
/// The call sites go with this class in a follow-up; until then it is a
/// zero-cost leaf, so no page shows a floating back.
class PageBackFloat extends StatelessWidget {
  const PageBackFloat({
    super.key,
    required this.controller,
    this.top,
    this.onPressed,
  });

  final ScrollChromeController controller;
  final double? top;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
