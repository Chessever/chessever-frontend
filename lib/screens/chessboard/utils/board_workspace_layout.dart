import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Budgets a square board and a usable analysis pane from the actual viewport.
/// An unfolded phone may need two panes without reporting landscape.
abstract final class BoardWorkspaceLayout {
  static const double minimumAnalysisWidth = 260;

  static bool usesSideBySide(
    Size size, {
    double boardChrome = 44,
    double verticalChrome = 144,
    double minimumAnalysisHeight = 240,
  }) {
    if (size.width < 600) return false;
    final stackedBoard = math.min(size.width * .85, 720) - boardChrome;
    return size.height < stackedBoard + verticalChrome + minimumAnalysisHeight;
  }

  static double boardSize({
    required Size viewport,
    required double boardChrome,
    required double horizontalPadding,
    required double verticalChrome,
    required double gap,
    double? leadingExtent,
  }) {
    var widthBudget =
        viewport.width -
        horizontalPadding * 2 -
        gap -
        minimumAnalysisWidth -
        boardChrome;
    if (leadingExtent != null) {
      widthBudget = math.min(widthBudget, leadingExtent - boardChrome);
    }
    return math.max(1, math.min(viewport.height - verticalChrome, widthBudget));
  }
}

/// Lets nested explorer lists follow their actual position beside the board.
class BoardWorkspaceScope extends InheritedWidget {
  const BoardWorkspaceScope({
    super.key,
    required this.sideBySide,
    required super.child,
  });

  final bool sideBySide;

  static bool sideBySideOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BoardWorkspaceScope>()
          ?.sideBySide ??
      false;

  @override
  bool updateShouldNotify(BoardWorkspaceScope oldWidget) =>
      sideBySide != oldWidget.sideBySide;
}
