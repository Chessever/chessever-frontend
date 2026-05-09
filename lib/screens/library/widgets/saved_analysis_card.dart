import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class SavedAnalysisCard extends StatelessWidget {
  final SavedAnalysis analysis;

  const SavedAnalysisCard({super.key, required this.analysis});

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today ${DateFormat('HH:mm').format(date)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return DateFormat('MMM d, y').format(date);
    }
  }

  Future<void> _handleTap(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await loadSavedAnalysis(context, analysis);
  }

  @override
  Widget build(BuildContext context) {
    final game = analysis.chessGame;
    // Extract player names from metadata
    final whiteName = game.metadata['White'] as String? ?? 'White';
    final blackName = game.metadata['Black'] as String? ?? 'Black';
    final lastViewed = analysis.lastOpenedAt ?? analysis.createdAt;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Container(
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color: context.colors.background, // Zinc 950
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(
            color: context.colors.surfaceRecessed, // Zinc 800
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title and favorite
            Row(
              children: [
                Expanded(
                  child: Text(
                    analysis.title,
                    style: AppTypography.textMdMedium.copyWith(
                      color: context.colors.textPrimary, // Zinc 50
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (analysis.isFavorite) ...[
                  SizedBox(width: 8.w),
                  Icon(
                    Icons.star,
                    color: Colors.amber, // Keep amber for favorite
                    size: 16.sp,
                  ),
                ],
              ],
            ),

            SizedBox(height: 4.h),

            // Player names
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$whiteName vs $blackName',
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textSecondary, // Zinc 400
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            SizedBox(height: 12.h),

            // Metadata row
            Row(
              children: [
                // Date
                Icon(
                  Icons.access_time,
                  size: 14.sp,
                  color: context.colors.textSecondary, // Zinc 400
                ),
                SizedBox(width: 4.w),
                Text(
                  _formatDate(lastViewed),
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textSecondary, // Zinc 400
                  ),
                ),

                SizedBox(width: 16.w),

                // Move count
                Icon(
                  Icons.analytics_outlined,
                  size: 14.sp,
                  color: context.colors.textSecondary, // Zinc 400
                ),
                SizedBox(width: 4.w),
                Text(
                  '${game.mainline.length} moves',
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textSecondary, // Zinc 400
                  ),
                ),

                SizedBox(width: 16.w),

                // Comment count
                if (analysis.variationComments.isNotEmpty) ...[
                  Icon(
                    Icons.comment_outlined,
                    size: 14.sp,
                    color: context.colors.textSecondary, // Zinc 400
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    '${analysis.variationComments.length}',
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textSecondary, // Zinc 400
                    ),
                  ),
                ],
              ],
            ),

            // Tags if any
            if (analysis.tags.isNotEmpty) ...[
              SizedBox(height: 12.h),
              Wrap(
                spacing: 6.w,
                runSpacing: 6.h,
                children:
                    analysis.tags.take(3).map((tag) {
                      return Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 2.h,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceRecessed, // Zinc 800
                          borderRadius: BorderRadius.circular(4.br),
                        ),
                        child: Text(
                          tag,
                          style: AppTypography.textXxsRegular.copyWith(
                            color: context.colors.textPrimary, // Zinc 50
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
