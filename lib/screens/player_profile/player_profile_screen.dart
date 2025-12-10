import 'package:chessever2/screens/player_profile/widgets/player_avatar_section.dart';
import 'package:chessever2/screens/player_profile/widgets/performance_stats_row.dart';
import 'package:chessever2/screens/player_profile/widgets/recent_opponents_list.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Player profile screen showing detailed player information
/// including avatar, ratings, performance stats, and recent opponents.
class PlayerProfileScreen extends ConsumerWidget {
  const PlayerProfileScreen({
    super.key,
    required this.playerId,
    required this.playerName,
    required this.title,
    required this.countryCode,
    required this.fideId,
    this.classicalRating,
    this.rapidRating,
    this.blitzRating,
    this.performanceRating,
    this.score,
    this.totalGames,
    this.ratingDiff,
    this.recentOpponents = const [],
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  final String playerId;
  final String playerName;
  final String? title;
  final String countryCode;
  final String? fideId;
  final int? classicalRating;
  final int? rapidRating;
  final int? blitzRating;
  final int? performanceRating;
  final double? score;
  final int? totalGames;
  final int? ratingDiff;
  final List<RecentOpponent> recentOpponents;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.sp),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 24.h),

                    // Avatar and Rating Cards Section
                    PlayerAvatarSection(
                      fideId: fideId,
                      playerName: playerName,
                      classicalRating: classicalRating,
                      rapidRating: rapidRating,
                      blitzRating: blitzRating,
                    ),

                    SizedBox(height: 24.h),

                    // Performance Stats Row
                    if (performanceRating != null ||
                        score != null ||
                        ratingDiff != null)
                      PerformanceStatsRow(
                        performanceRating: performanceRating,
                        score: score,
                        totalGames: totalGames,
                        ratingDiff: ratingDiff,
                      ),

                    SizedBox(height: 24.h),

                    // Recent Opponents Section
                    if (recentOpponents.isNotEmpty) ...[
                      Text(
                        'Recent Opponents',
                        style: AppTypography.textSmBold.copyWith(
                          color: kWhiteColor,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      RecentOpponentsList(opponents: recentOpponents),
                    ],

                    SizedBox(height: 24.h),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.all(4.sp),
              child: Icon(
                Icons.arrow_back_ios,
                color: kWhiteColor,
                size: 20.sp,
              ),
            ),
          ),

          SizedBox(width: 12.w),

          // Flag and Player Name
          Expanded(
            child: GestureDetector(
              onTap: () {
                // TODO: Show player picker dropdown
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Country flag
                  countryCode.toUpperCase() == 'FID'
                      ? Image.asset(
                          PngAsset.fideLogo,
                          height: 16.h,
                          width: 22.w,
                          fit: BoxFit.cover,
                        )
                      : CountryFlag.fromCountryCode(
                          countryCode,
                          height: 16.h,
                          width: 22.w,
                        ),

                  SizedBox(width: 8.w),

                  // Title and Name
                  Flexible(
                    child: Text(
                      '${title != null ? '$title ' : ''}$playerName',
                      style: AppTypography.textMdBold.copyWith(
                        color: kWhiteColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  SizedBox(width: 4.w),

                  // Dropdown indicator
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: kWhiteColor70,
                    size: 20.sp,
                  ),
                ],
              ),
            ),
          ),

          SizedBox(width: 12.w),

          // Favorite button
          GestureDetector(
            onTap: onFavoriteToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.all(4.sp),
              child: SvgWidget(
                isFavorite ? SvgAsset.favouriteRedIcon : SvgAsset.favouriteIcon2,
                semanticsLabel: 'Favorite',
                height: 20.sp,
                width: 20.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Model for recent opponent data
class RecentOpponent {
  const RecentOpponent({
    required this.name,
    required this.title,
    required this.countryCode,
    required this.rating,
    required this.result,
    required this.playedAsWhite,
    this.fideId,
  });

  final String name;
  final String? title;
  final String countryCode;
  final int rating;
  final double result; // 1.0 = win, 0.5 = draw, 0.0 = loss
  final bool playedAsWhite;
  final String? fideId;
}
