import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:country_flags/country_flags.dart';
import '../../../utils/app_typography.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/svg_asset.dart';
import '../../../utils/png_asset.dart';
import '../../../widgets/svg_widget.dart';
import '../../../screens/player_games/player_games_screen.dart';

class PlayerFavoriteCard extends ConsumerWidget {
  final Map<String, dynamic> playerData;
  final int rank;
  final VoidCallback? onRemoveFavorite;

  const PlayerFavoriteCard({
    super.key,
    required this.playerData,
    required this.rank,
    this.onRemoveFavorite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = playerData['name'] as String? ?? 'Unknown Player';
    final title = playerData['title'] as String? ?? '';
    final countryCode = playerData['countryCode'] as String? ?? '';
    final rating = playerData['rating'] as int? ?? 0;

    return GestureDetector(
      onTap: () => _navigateToPlayerScoreCard(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(8.br),
        ),
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
        child: Row(
        children: [
          // Rank
          SizedBox(
            width: 32.w,
            child: Text(
              '$rank.',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(width: 12.w),

          // Country flag
          if (countryCode.isNotEmpty)
            Container(
              margin: EdgeInsets.only(right: 12.w),
              child: countryCode.toUpperCase() == 'FID'
                  ? Image.asset(
                      PngAsset.fideLogo,
                      height: 16.h,
                      width: 24.w,
                      fit: BoxFit.cover,
                    )
                  : CountryFlag.fromCountryCode(
                      countryCode,
                      height: 16.h,
                      width: 24.w,
                    ),
            ),

          // Player info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Player name with title
                RichText(
                  text: TextSpan(
                    children: [
                      if (title.isNotEmpty) ...[
                        TextSpan(
                          text: '$title ',
                          style: AppTypography.textSmMedium.copyWith(
                            color: kPrimaryColor,
                          ),
                        ),
                      ],
                      TextSpan(
                        text: name,
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Rating
                if (rating > 0) ...[
                  SizedBox(height: 4.h),
                  Row(
                    children: [
                      Icon(
                        Icons.trending_up,
                        size: 12.ic,
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        'Rating: $rating',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Remove favorite button
          GestureDetector(
            onTap: onRemoveFavorite,
            child: Container(
              padding: EdgeInsets.all(8.sp),
              child: SvgWidget(
                SvgAsset.favouriteRedIcon,
                semanticsLabel: 'Remove from favorites',
                height: 18.h,
                width: 18.w,
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  void _navigateToPlayerScoreCard(BuildContext context, WidgetRef ref) {
    try {
      final name = playerData['name'] as String? ?? 'Unknown Player';
      final title = playerData['title'] as String?;
      final countryCode = playerData['countryCode'] as String? ?? '';

      // Navigate to player games screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerGamesScreen(
            playerName: name,
            playerTitle: title,
            countryCode: countryCode,
          ),
        ),
      );
    } catch (e) {
      // Handle navigation error silently
    }
  }
}