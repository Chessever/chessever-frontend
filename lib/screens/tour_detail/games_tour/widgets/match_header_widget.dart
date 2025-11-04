import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Widget to display a match header in knockout tournaments
/// Shows player names, current score, and match status
class MatchHeader extends ConsumerWidget {
  final MatchHeaderModel match;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const MatchHeader({
    super.key,
    required this.match,
    this.isExpanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h, left: 4.w, right: 4.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.br),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12.br),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Row(
            children: [
              // Status indicator bar
              Container(
                width: 3.w,
                height: 48.h,
                decoration: BoxDecoration(
                  color: _getStatusColor(),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              SizedBox(width: 12.w),

              // Match info - Player names with scores
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Player 1 with score
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            match.player1,
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        // Player 1 score badge
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimaryColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6.br),
                          ),
                          child: Text(
                            '${match.player1Score}',
                            style: AppTypography.textSmMedium.copyWith(
                              color: kPrimaryColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    // Player 2 with score
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            match.player2,
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        // Player 2 score badge
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimaryColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6.br),
                          ),
                          child: Text(
                            '${match.player2Score}',
                            style: AppTypography.textSmMedium.copyWith(
                              color: kPrimaryColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Optional expand/collapse icon
              if (onToggle != null) ...[
                SizedBox(width: 8.w),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: kWhiteColor.withValues(alpha: 0.5),
                  size: 20.sp,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (match.isComplete) {
      return kPrimaryColor.withValues(alpha: 0.5);
    }

    // Check if there are any ongoing games
    final hasOngoingGames = match.games.any(
      (g) => !g.effectiveGameStatus.isFinished,
    );

    if (hasOngoingGames) {
      return kPrimaryColor;
    }

    // Matches with all games finished (draws) or scheduled
    return kWhiteColor.withValues(alpha: 0.25);
  }
}

/// Simplified match header for compact display
class CompactMatchHeader extends ConsumerWidget {
  final MatchHeaderModel match;

  const CompactMatchHeader({
    super.key,
    required this.match,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: EdgeInsets.only(bottom: 6.h, left: 4.w, right: 4.w),
      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 8.sp),
      decoration: BoxDecoration(
        color: kBlack2Color.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Row(
        children: [
          Container(
            width: 3.w,
            height: 20.h,
            decoration: BoxDecoration(
              color: match.isComplete ? Colors.green : kPrimaryColor,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              match.matchTitle,
              style: AppTypography.textXsMedium.copyWith(
                color: kWhiteColor,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            match.scoreDisplay,
            style: AppTypography.textXsMedium.copyWith(
              color: kPrimaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
