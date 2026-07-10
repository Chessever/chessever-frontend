import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Thin package composition wrapper for secondary full-screen routes.
///
/// Uses [GlassPage] so glass chrome on the route (app bars, chips, buttons)
/// has correct background sampling / isolation without forcing every screen
/// onto a full [GlassScaffold] shell.
class ScreenWrapper extends StatelessWidget {
  const ScreenWrapper({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      background: ColoredBox(color: context.colors.background),
      statusBarStyle: GlassStatusBarStyle.auto,
      child: child,
    );
  }
}
