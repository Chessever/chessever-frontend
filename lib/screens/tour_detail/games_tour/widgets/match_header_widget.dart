import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_flags/country_flags.dart';
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
    final player1Card = _matchPlayerCard(match, match.player1);
    final player2Card = _matchPlayerCard(match, match.player2);
    final player1Flag = _playerFlag(ref, player1Card);
    final player2Flag = _playerFlag(ref, player2Card);

    return Container(
      margin: EdgeInsets.zero,
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
          padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
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
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (player1Flag != null) ...[
                                player1Flag,
                                SizedBox(width: 6.w),
                              ],
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
                            ],
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
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (player2Flag != null) ...[
                                player2Flag,
                                SizedBox(width: 6.w),
                              ],
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
                            ],
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

  const CompactMatchHeader({super.key, required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player1Card = _matchPlayerCard(match, match.player1);
    final player2Card = _matchPlayerCard(match, match.player2);
    final player1Flag = _playerFlag(ref, player1Card);
    final player2Flag = _playerFlag(ref, player2Card);

    return Container(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 10.sp),
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
            child: Row(
              children: [
                if (player1Flag != null) ...[player1Flag, SizedBox(width: 4.w)],
                Flexible(
                  child: Text(
                    match.player1,
                    style: AppTypography.textXsMedium.copyWith(
                      color: kWhiteColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 6.w),
                Text(
                  'vs',
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(width: 6.w),
                if (player2Flag != null) ...[player2Flag, SizedBox(width: 4.w)],
                Flexible(
                  child: Text(
                    match.player2,
                    style: AppTypography.textXsMedium.copyWith(
                      color: kWhiteColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
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

PlayerCard? _matchPlayerCard(MatchHeaderModel match, String playerName) {
  for (final game in match.games) {
    final white = game.whitePlayer;
    if (white.name == playerName) return white;

    final black = game.blackPlayer;
    if (black.name == playerName) return black;
  }
  return null;
}

Widget? _playerFlag(WidgetRef ref, PlayerCard? player) {
  if (player == null) return null;

  final countryCode = player.countryCode.trim();
  if (countryCode.isEmpty) return null;

  // Check for FIDE flag
  if (countryCode.toUpperCase() == 'FID') {
    return Image.asset(
      PngAsset.fideLogo,
      height: 12.h,
      width: 16.w,
      fit: BoxFit.cover,
      cacheWidth: 48,
      cacheHeight: 36,
    );
  }

  // Validate country code using the location service
  final validCountryCode = ref
      .read(locationServiceProvider)
      .getValidCountryCode(countryCode);

  if (validCountryCode.isEmpty) return null;

  return CountryFlag.fromCountryCode(
validCountryCode,
  theme: ImageTheme(height: 12.h,
    width: 16.w,),
);
}
