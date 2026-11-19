import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
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
    showAlertModal<void>(
      context: context,
      child: Builder(
        builder: (dialogContext) {
          final colors = dialogContext.colors;
          final bodyStyle = AppTypography.textSmRegular.copyWith(
            color: colors.textPrimary.withValues(alpha: 0.7),
          );
          return Container(
            width: double.infinity,
            padding: EdgeInsets.all(24.sp),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16.br),
              border: Border.all(
                color: colors.textPrimary.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Combined estimates',
                  style: AppTypography.textMdBold.copyWith(
                    color: colors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12.h),
                Text(
                  'Tap a rating box above to see that format’s stats.',
                  style: bodyStyle,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12.h),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12.sp,
                  runSpacing: 8.sp,
                  children: [
                    for (final (asset, label) in const [
                      (PngAsset.classicalIcon, 'Classical'),
                      (PngAsset.rapidIcon, 'Rapid'),
                      (PngAsset.blitzIcon, 'Blitz'),
                    ])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TimeControlGlyph(asset, size: 16.sp),
                          SizedBox(width: 4.sp),
                          Text(
                            label,
                            style: AppTypography.textSmMedium.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                SizedBox(height: 12.h),
                Text(
                  'Combined stats are estimates, not official Elo changes.',
                  style: bodyStyle,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 44.h,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: kBlackColor,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.br),
                      ),
                    ),
                    child: Text(
                      'OK',
                      style: AppTypography.textSmBold.copyWith(
                        color: kBlackColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
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
