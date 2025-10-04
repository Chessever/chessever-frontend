import 'package:chessever2/screens/favorites/player_games/view_model/player_games_state.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TournamentGroupHeader extends StatelessWidget {
  final TournamentGamesGroup tournamentGroup;

  const TournamentGroupHeader({
    super.key,
    required this.tournamentGroup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(8.br),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
      child: Row(
        children: [
          // Tournament image (if available)
          if (tournamentGroup.tourImage != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6.br),
              child: Image.network(
                tournamentGroup.tourImage!,
                width: 56.w,
                height: 56.h,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _buildPlaceholderImage();
                },
              ),
            ),
            SizedBox(width: 12.w),
          ],

          // Tournament info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tournament name
                Text(
                  tournamentGroup.tourName,
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),

                // Game count and date range
                Row(
                  children: [
                    // Game count
                    Text(
                      '${tournamentGroup.games.length} game${tournamentGroup.games.length == 1 ? '' : 's'}',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                    ),

                    // Date range if available
                    if (tournamentGroup.startDate != null) ...[
                      Text(
                        ' • ',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          _formatDateRange(
                            tournamentGroup.startDate!,
                            tournamentGroup.endDate,
                          ),
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: 56.w,
      height: 56.h,
      decoration: BoxDecoration(
        color: kDarkGreyColor,
        borderRadius: BorderRadius.circular(6.br),
      ),
      child: Icon(
        Icons.emoji_events,
        color: kWhiteColor.withValues(alpha: 0.5),
        size: 28.ic,
      ),
    );
  }

  String _formatDateRange(DateTime start, DateTime? end) {
    final dateFormat = DateFormat('MMM d, yyyy');

    if (end == null || start.year == end.year && start.month == end.month && start.day == end.day) {
      return dateFormat.format(start);
    }

    // Same month and year
    if (start.year == end.year && start.month == end.month) {
      return '${DateFormat('MMM d').format(start)}-${end.day}, ${end.year}';
    }

    // Same year
    if (start.year == end.year) {
      return '${DateFormat('MMM d').format(start)} - ${dateFormat.format(end)}';
    }

    // Different years
    return '${dateFormat.format(start)} - ${dateFormat.format(end)}';
  }
}
