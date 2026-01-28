import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart' as skel;

/// A player card widget matching the Figma design.
///
/// Two modes:
/// - [showFavoriteButton] = true: Shows heart icon on the right (for players/favorites lists)
/// - [showFavoriteButton] = false: Shows score on the right (for standings)
class FigmaPlayerCard extends ConsumerWidget {
  final PlayerStandingModel player;
  final int rank;
  final bool isFavorite;
  final bool showFavoriteButton;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final ValueChanged<LongPressStartDetails>? onLongPress;

  const FigmaPlayerCard({
    super.key,
    required this.player,
    required this.rank,
    this.isFavorite = false,
    this.showFavoriteButton = true,
    required this.onTap,
    this.onToggleFavorite,
    this.onLongPress,
  });

  String _getInitials(String name) {
    final parts = name.split(',');
    if (parts.length > 1) {
      final first = parts[0].trim();
      final second = parts[1].trim();
      return '${first.isNotEmpty ? first[0] : ''}${second.isNotEmpty ? second[0] : ''}'
          .toUpperCase();
    }
    final words = name.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0].isNotEmpty ? words[0][0] : ''}${words[1].isNotEmpty ? words[1][0] : ''}'
          .toUpperCase();
    }
    return name.isNotEmpty
        ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase()
        : '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(playerPhotoProvider(player.fideId));
    final avatarSize = 56.w;
    final initials = _getInitials(player.name);
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(player.countryCode);

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onLongPress,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Color(0xFF1F1F1F),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Rank number
            SizedBox(
              width: 24.w,
              child: Text(
                rank.toString(),
                style: AppTypography.textSmMedium.copyWith(
                  color: const Color(0xFF71717A),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(width: 12.w),
            // Player photo with title badge overlay
            photoAsync.when(
              data: (photoUrl) => PlayerInitialsAvatar(
                photoUrl: photoUrl,
                initials: initials,
                size: avatarSize,
                borderRadius: 8.br,
                title: player.title,
              ),
              loading: () => skel.Skeletonizer(
                enabled: true,
                effect: const skel.ShimmerEffect(
                  baseColor: Color(0xFF2A2A2A),
                  highlightColor: Color(0xFF3A3A3A),
                ),
                child: Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                ),
              ),
              error: (_, __) => PlayerInitialsAvatar(
                initials: initials,
                size: avatarSize,
                borderRadius: 8.br,
                title: player.title,
              ),
            ),
            SizedBox(width: 12.w),
            // Player info (name + flag/rating)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Player name
                  Text(
                    player.name,
                    style: AppTypography.textSmBold.copyWith(
                      color: kWhiteColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  // Flag + Rating (+ optional change)
                  Row(
                    children: [
                      // Country flag
                      if (player.countryCode.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(right: 6.w),
                          child: SizedBox(
                            width: 18.w,
                            height: 12.h,
                            child: player.countryCode.toUpperCase() == 'FID'
                                ? Image.asset(
                                    PngAsset.fideLogo,
                                    height: 12.h,
                                    width: 18.w,
                                    fit: BoxFit.contain,
                                    cacheWidth: 48,
                                    cacheHeight: 36,
                                  )
                                : validCountryCode.isNotEmpty
                                    ? CountryFlag.fromCountryCode(
                                        validCountryCode,
                                        height: 12.h,
                                        width: 18.w,
                                        shape: RoundedRectangle(2.br),
                                      )
                                    : null,
                          ),
                        ),
                      // Rating
                      Text(
                        player.score.toString(),
                        style: AppTypography.textSmRegular.copyWith(
                          color: const Color(0xFFA1A1AA),
                        ),
                      ),
                      // Rating change (if any)
                      if (player.scoreChange != 0)
                        Text(
                          player.scoreChange > 0
                              ? '+${player.scoreChange}'
                              : '${player.scoreChange}',
                          style: AppTypography.textSmMedium.copyWith(
                            color: player.scoreChange > 0
                                ? kGreenColor
                                : kRedColor,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Right side: either heart or score
            if (showFavoriteButton && onToggleFavorite != null)
              GestureDetector(
                onTap: onToggleFavorite,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: EdgeInsets.all(8.sp),
                  child: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF71717A),
                    size: 24.ic,
                  ),
                ),
              )
            else if (!showFavoriteButton)
              Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: Text(
                  player.matchScore ?? '',
                  style: AppTypography.textMdMedium.copyWith(
                    color: kWhiteColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Header row for standings lists matching the Figma design.
class FigmaStandingsHeader extends StatelessWidget {
  final bool showScore;

  const FigmaStandingsHeader({
    super.key,
    this.showScore = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      child: Row(
        children: [
          // # column
          SizedBox(
            width: 24.w,
            child: Text(
              '#',
              style: AppTypography.textXsMedium.copyWith(
                color: const Color(0xFF71717A),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: 12.w),
          // Player column
          Expanded(
            child: Text(
              'Player',
              style: AppTypography.textXsMedium.copyWith(
                color: const Color(0xFF71717A),
              ),
            ),
          ),
          // Score column
          if (showScore)
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: Text(
                'Score',
                style: AppTypography.textXsMedium.copyWith(
                  color: const Color(0xFF71717A),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
