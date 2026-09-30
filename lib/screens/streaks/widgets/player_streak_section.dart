import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// A section's title with an optional quiet detail on the same line
/// ("This run · since Sep 13").
class StreakSectionHead extends StatelessWidget {
  const StreakSectionHead({super.key, required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    // A floor, not a fixed height: at larger text scales the 16/24 title
    // line outgrows 24.w, and a fixed box would shave its descenders.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 24.w),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: streakText(
                context,
                size: 16,
                line: 24,
                weight: FontWeight.w700,
              ),
            ),
          ),
          if (detail != null) ...[
            SizedBox(width: 12.w),
            Text.rich(
              streakFigures(detail!),
              maxLines: 1,
              style: streakText(
                context,
                size: 12,
                line: 16,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
