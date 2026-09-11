import 'package:flutter/material.dart';

/// Follow a move within its notation viewport without scrolling the board,
/// video column, or enclosing game PageView.
void scrollNotationToMove(
  ScrollController controller,
  BuildContext targetContext, {
  double alignment = 0.5,
  bool animate = true,
}) {
  if (!controller.hasClients || !targetContext.mounted) return;
  final target = targetContext.findRenderObject();
  if (target == null || !target.attached) return;
  // Unlike Scrollable.ensureVisible, this only moves the owned position.
  controller.position.ensureVisible(
    target,
    alignment: alignment,
    duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
    curve: Curves.easeInOut,
  );
}
