import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';

/// Row displaying performance statistics: Performance rating, Score, and Rating diff.
class PerformanceStatsRow extends StatelessWidget {
  const PerformanceStatsRow({
    super.key,
    this.performanceRating,
    this.score,
    this.totalGames,
    this.ratingDiff,
    this.showCombinedEstimates = false,
  });

  final int? performanceRating;
  final double? score;
  final int? totalGames;
  final int? ratingDiff;
  final bool showCombinedEstimates;

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
          _buildStatItem(
            context,
            label: 'Performance',
            value: _formatRatingValue(performanceRating),
            showInfo: showCombinedEstimates,
          ),

          // Score - always show, "-" when no data
          _buildStatItem(
            context,
            label: 'Score',
            value: (score != null && totalGames != null)
                ? _formatScore(score!, totalGames!)
                : '-',
          ),

          _buildStatItem(
            context,
            label: 'Rating',
            value: _formatRatingValue(ratingDiff, signed: true),
            valueColor: ratingDiff == null
                ? null
                : ratingDiff! >= 0
                ? context.colors.successStrong
                : context.colors.danger,
            showInfo: showCombinedEstimates,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
    bool showInfo = false,
    Color? valueColor,
  }) {
    final labelText = Text(
      label,
      style: AppTypography.textXsMedium.copyWith(
        color: context.colors.textPrimaryMuted,
      ),
    );
    final item = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showInfo)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              labelText,
              SizedBox(width: 4.sp),
              Icon(
                Icons.info_outline,
                size: 12.sp,
                color: context.colors.textPrimaryMuted,
              ),
            ],
          )
        else
          labelText,
        SizedBox(height: 4.h),
        Text(
          value,
          style: AppTypography.textLgBold.copyWith(
            color: valueColor ?? context.colors.textPrimary,
          ),
        ),
      ],
    );
    if (!showInfo) return item;
    return Tooltip(
      message: 'About combined $label',
      child: InkWell(onTap: () => _showTimeControlHelp(context), child: item),
    );
  }

  String _formatRatingValue(int? value, {bool signed = false}) {
    if (value == null) return '-';
    final estimate = showCombinedEstimates ? '≈' : '';
    final sign = signed && value >= 0 ? '+' : '';
    return '$estimate$sign$value';
  }

  void _showTimeControlHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Combined estimates'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tap a rating box above to see that format’s stats.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final (asset, label) in const [
                  (PngAsset.classicalIcon, 'Classical'),
                  (PngAsset.rapidIcon, 'Rapid'),
                  (PngAsset.blitzIcon, 'Blitz'),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TimeControlGlyph(asset, size: 16),
                      const SizedBox(width: 4),
                      Text(label),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Combined stats are estimates, not official Elo changes.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatScore(double score, int totalGames) {
    // Format score as "2.5/3" or "2/3"
    final scoreStr = score == score.truncate()
        ? score.truncate().toString()
        : score.toString();
    return '$scoreStr/$totalGames';
  }
}
