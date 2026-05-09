import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Row displaying performance statistics: Performance rating, Score, and Rating diff.
class PerformanceStatsRow extends StatelessWidget {
  const PerformanceStatsRow({
    super.key,
    this.performanceRating,
    this.score,
    this.totalGames,
    this.ratingDiff,
  });

  final int? performanceRating;
  final double? score;
  final int? totalGames;
  final int? ratingDiff;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Performance Rating - always show, "-" when no data
          _buildStatItem(
            label: 'Performance',
            value: performanceRating?.toString() ?? '-',
          ),

          // Score - always show, "-" when no data
          _buildStatItem(
            label: 'Score',
            value:
                (score != null && totalGames != null)
                    ? _formatScore(score!, totalGames!)
                    : '-',
          ),

          // Rating Diff - always show, "-" when no data
          if (ratingDiff != null)
            _buildRatingDiffItem(label: 'Rating', diff: ratingDiff!)
          else
            _buildStatItem(label: 'Rating', value: '-'),
        ],
      ),
    );
  }

  Widget _buildStatItem({required String label, required String value}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
        ),
        SizedBox(height: 4.h),
        Text(
          value,
          style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
        ),
      ],
    );
  }

  Widget _buildRatingDiffItem({required String label, required int diff}) {
    final isPositive = diff >= 0;
    final displayText = isPositive ? '+$diff' : '$diff';
    final color = isPositive ? kGreenColor : kRedColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
        ),
        SizedBox(height: 4.h),
        Text(
          displayText,
          style: AppTypography.textLgBold.copyWith(color: color),
        ),
      ],
    );
  }

  String _formatScore(double score, int totalGames) {
    // Format score as "2.5/3" or "2/3"
    final scoreStr =
        score == score.truncate()
            ? score.truncate().toString()
            : score.toString();
    return '$scoreStr/$totalGames';
  }
}
