import 'dart:math' as math;

import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/player_class_scoreboard.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';

/// Classical · Rapid · Blitz, each with how many players are on its wall.
///
/// The app's own segmented track (the one the Events screen uses), so the
/// wall reads as part of ChessEver: the selected class is white, the others
/// sit at 70 %, and each carries the event-card time-control glyph.
///
/// The three labels always share one type size. "Classical 1,105" is the
/// only one that outgrows its third on a phone, so every label is laid out
/// at the width of the widest one and each segment's scale-down then lands
/// on the same factor, instead of shrinking Classical alone.
class WallClassSwitch extends StatelessWidget {
  const WallClassSwitch({
    super.key,
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  final StreakTimeClass selected;

  /// Null while the wall is still loading: labels only, never a fake "0".
  final Map<StreakTimeClass, int>? counts;
  final ValueChanged<StreakTimeClass> onChanged;

  @override
  Widget build(BuildContext context) {
    const classes = StreakTimeClass.values;
    final contentWidth = _widestLabelWidth(context, classes);
    return SegmentedSwitcher(
      options: [for (final tc in classes) tc.label],
      currentSelection: selected.index,
      initialSelection: selected.index,
      backgroundColor: context.colors.popup,
      selectedBackgroundColor: context.colors.popup,
      borderRadius: 8.br,
      optionLabels: [
        for (final tc in classes)
          _ClassLabel(
            key: ValueKey<String>('streak-class-${tc.wire}'),
            timeClass: tc,
            count: counts?[tc],
            selected: tc == selected,
            contentWidth: contentWidth,
          ),
      ],
      onSelectionChanged: (i) {
        final tc = classes[i];
        if (tc == selected) return;
        HapticFeedbackService.selection();
        onChanged(tc);
      },
    );
  }

  /// Natural width of the widest label at the current text size. The count
  /// is measured at the bold weight the selected segment wears, so the shared
  /// size does not shift when the selection moves.
  double _widestLabelWidth(
    BuildContext context,
    List<StreakTimeClass> classes,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final ink = context.colors.textPrimary;
    // The labels inherit what their style leaves unset (letter spacing, for
    // one) from the ambient text style, so the measurement does too.
    final ambient = DefaultTextStyle.of(context).style;
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: ambient.merge(style)),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var widest = 0.0;
    for (final tc in classes) {
      var width =
          _glyphSize.w + _glyphGap.w + measure(tc.label, _labelStyle(ink));
      final n = counts?[tc];
      if (n != null) {
        width +=
            _countGap.w + measure(wallCount(n), _countStyle(ink, bold: true));
      }
      widest = math.max(widest, width);
    }
    return widest.ceilToDouble();
  }
}

const double _glyphSize = 14;
const double _glyphGap = 6;
const double _countGap = 5;

TextStyle _labelStyle(Color color) => wallText(14, 22, FontWeight.w500, color);

TextStyle _countStyle(Color color, {required bool bold}) => wallText(
  13,
  22,
  bold ? FontWeight.w700 : FontWeight.w500,
  color,
  tabular: true,
);

class _ClassLabel extends StatelessWidget {
  const _ClassLabel({
    super.key,
    required this.timeClass,
    required this.count,
    required this.selected,
    required this.contentWidth,
  });

  final StreakTimeClass timeClass;
  final int? count;
  final bool selected;

  /// The widest label's natural width. Every label is laid out at least this
  /// wide, so the three FittedBoxes all scale by the same factor.
  final double contentWidth;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textPrimary;
    final tone = selected ? ink : ink.withValues(alpha: 0.7);
    final n = count;
    return Semantics(
      selected: selected,
      label: n == null
          ? timeClass.label
          : '${timeClass.label}, ${wallCount(n)} players on a run',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6.w),
        // Scales down rather than clipping "Classical 1,105" on a narrow
        // phone; the shared minimum width keeps all three at one type size.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: contentWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Opacity(
                  opacity: selected ? 1 : 0.7,
                  // Owl and rabbit are white art; on the light track they
                  // draw their paper twins rather than vanish.
                  child: StreakClassIcon(
                    timeClass: timeClass,
                    size: _glyphSize.w,
                  ),
                ),
                SizedBox(width: _glyphGap.w),
                Text(timeClass.label, maxLines: 1, style: _labelStyle(tone)),
                if (n != null) ...[
                  SizedBox(width: _countGap.w),
                  Text(
                    wallCount(n),
                    maxLines: 1,
                    style: _countStyle(tone, bold: selected),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
