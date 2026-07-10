import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';

/// Edge-to-edge content with liquid-glass controls floating above it.
///
/// The content layer always fills the viewport and stays opaque. Optional
/// control islands are positioned over that layer, so a page never needs a
/// fixed app-bar/search strip. [contentPadding] protects the first and last
/// actionable content without changing the full-screen composition.
class GlassFullScreenPage extends StatelessWidget {
  const GlassFullScreenPage({
    required this.content,
    super.key,
    this.topOverlay,
    this.bottomOverlay,
    this.contentPadding = EdgeInsets.zero,
    this.topOverlayPadding = EdgeInsets.zero,
    this.bottomOverlayPadding = EdgeInsets.zero,
    this.backgroundColor,
    this.includeContentSafeArea = true,
    this.avoidKeyboard = true,
  });

  final Widget content;
  final Widget? topOverlay;
  final Widget? bottomOverlay;
  final EdgeInsets contentPadding;
  final EdgeInsets topOverlayPadding;
  final EdgeInsets bottomOverlayPadding;
  final Color? backgroundColor;
  final bool includeContentSafeArea;
  final bool avoidKeyboard;

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final keyboardInset =
        avoidKeyboard ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
    final contentSafePadding =
        includeContentSafeArea ? viewPadding : EdgeInsets.zero;
    final resolvedContentPadding = EdgeInsets.fromLTRB(
      contentPadding.left + contentSafePadding.left,
      contentPadding.top + contentSafePadding.top,
      contentPadding.right + contentSafePadding.right,
      contentPadding.bottom + contentSafePadding.bottom,
    );
    final resolvedTopPadding = EdgeInsets.fromLTRB(
      topOverlayPadding.left + viewPadding.left,
      topOverlayPadding.top + viewPadding.top,
      topOverlayPadding.right + viewPadding.right,
      topOverlayPadding.bottom,
    );
    final resolvedBottomPadding = EdgeInsets.fromLTRB(
      bottomOverlayPadding.left + viewPadding.left,
      bottomOverlayPadding.top,
      bottomOverlayPadding.right + viewPadding.right,
      bottomOverlayPadding.bottom +
          (keyboardInset > 0 ? 0 : viewPadding.bottom),
    );

    return ScreenWrapper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: backgroundColor ?? context.colors.background,
                child: Padding(padding: resolvedContentPadding, child: content),
              ),
            ),
            if (topOverlay case final overlay?)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: resolvedTopPadding,
                  child: Semantics(container: true, child: overlay),
                ),
              ),
            if (bottomOverlay case final overlay?)
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboardInset,
                child: Padding(
                  padding: resolvedBottomPadding,
                  child: Semantics(container: true, child: overlay),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
