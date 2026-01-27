import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

class RoundHeader extends StatelessWidget {
  final GamesAppBarModel round;
  final List<GamesTourModel> roundGames;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const RoundHeader({
    super.key,
    required this.round,
    required this.roundGames,
    this.isExpanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Removed all the individual visibility checking logic
    // Now handled centrally in GamesTourScreen for better performance

    // Format the round name better for knockout tournaments
    final displayName = _formatRoundName(round, roundGames);

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
        decoration: BoxDecoration(
          color: kDarkGreyColor,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                '$displayName ⚫ ${round.formattedRoundDateTime}',
                style: TextStyle(
                  color: kWhiteColor,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onToggle != null) ...[
              SizedBox(width: 12.w),
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
    );
  }

  String _formatRoundName(GamesAppBarModel round, List<GamesTourModel> games) {
    final name = round.name;
    if (games.isEmpty) return name;

    // Check if this is a knockout match format
    final isKnockout = KnockoutMatchDetector.isKnockoutMatchFormat(games);
    final roundIdLower = round.id.toLowerCase();
    final isSyntheticKnockoutRound =
        roundIdLower.startsWith('$kKnockoutStagePrefix-') ||
        roundIdLower.startsWith('knockout-round-');

    // When we're showing a synthetic knockout round (e.g., "Round 1"),
    // keep the tournament stage name instead of downgrading to game slug labels.
    if (isKnockout && isSyntheticKnockoutRound) {
      return name;
    }

    if (isKnockout) {
      // Get first game's round slug to determine display
      final firstSlug = games.first.roundSlug?.toLowerCase() ?? '';

      if (firstSlug.startsWith('game-')) {
        // Standard game format: "Game 1", "Game 2", etc.
        return KnockoutMatchDetector.formatRoundSlug(firstSlug);
      } else if (firstSlug.contains('tiebreak')) {
        // Tiebreak format
        return KnockoutMatchDetector.formatRoundSlug(firstSlug);
      }
    }

    // Default: return the original name
    return name;
  }
}
