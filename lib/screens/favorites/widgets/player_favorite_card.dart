import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:country_flags/country_flags.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/png_asset.dart';

class PlayerFavoriteCard extends ConsumerWidget {
  final PlayerStandingModel playerData;
  final int rank;
  final bool isEven;
  final VoidCallback? onRemoveFavorite;

  const PlayerFavoriteCard({
    super.key,
    required this.playerData,
    required this.rank,
    required this.isEven,
    this.onRemoveFavorite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(playerData.countryCode);

    return GestureDetector(
      onTap: () => _navigateToPlayerScoreCard(context, ref),
      onLongPressStart: (details) {
        HapticFeedback.lightImpact();
        _showContextMenu(context, details.globalPosition, playerData.name);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isEven ? kBlack2Color : kBackgroundColor.withOpacity(0.5),
        ),
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 8.sp),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 24.w,
              child: Text(
                '$rank.',
                style: AppTypography.textXsMedium.copyWith(fontSize: 16.sp),
              ),
            ),
            SizedBox(width: 16.w),
            // Country flag
            if (playerData.countryCode.toUpperCase() == 'FID') ...[
              Container(
                margin: EdgeInsets.only(right: 12.w),
                child: Image.asset(
                  PngAsset.fideLogo,
                  height: 12.h,
                  width: 16.w,
                  fit: BoxFit.cover,
                ),
              ),
            ] else if (validCountryCode.isNotEmpty) ...[
              Container(
                margin: EdgeInsets.only(right: 12.w),
                child: CountryFlag.fromCountryCode(
                  validCountryCode,
                  height: 12.h,
                  width: 16.w,
                ),
              ),
            ],

            Expanded(
              child: RichText(
                text: TextSpan(
                  children: [
                    if (playerData.title?.isNotEmpty ?? false) ...[
                      TextSpan(
                        text: '${playerData.title} ',
                        style: AppTypography.textXsMedium.copyWith(
                          color: kLightYellowColor,
                        ),
                      ),
                    ],
                    TextSpan(
                      text: playerData.name,
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            SizedBox(width: 16.w),

            // Rating
            if (playerData.score > 0)
              SizedBox(
                width: 60.w,
                child: Text(
                  '${playerData.score}',
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            SizedBox(width: 16.w),

            // Remove favorite button (heart icon)
            GestureDetector(
              onTap: onRemoveFavorite,
              child: Container(
                padding: EdgeInsets.all(8.sp),
                child: Icon(Icons.favorite, color: kRedColor, size: 20.ic),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToPlayerScoreCard(BuildContext context, WidgetRef ref) {
    try {
      FocusScope.of(context).unfocus();
      ref.read(selectedPlayerProvider.notifier).state = playerData;
      Navigator.pushNamed(context, '/scorecard_screen');
    } catch (e) {}
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    String playerName,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: kBlack2Color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.br)),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: kRedColor, size: 20.ic),
              SizedBox(width: 12.w),
              Text(
                'Remove from favorites',
                style: AppTypography.textSmRegular.copyWith(color: kRedColor),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        _showDeleteConfirmation(context, playerName).then((confirmed) {
          if (confirmed == true && onRemoveFavorite != null) {
            HapticFeedback.mediumImpact();
            onRemoveFavorite!();
          }
        });
      }
    });
  }

  Future<bool?> _showDeleteConfirmation(
    BuildContext context,
    String playerName,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: kBlack2Color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.br),
          ),
          title: Text(
            'Remove from favorites?',
            style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
          ),
          content: Text(
            'Are you sure you want to remove $playerName from your favorites?',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.7),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
                if (onRemoveFavorite != null) {
                  onRemoveFavorite!();
                }
              },
              child: Text(
                'Remove',
                style: AppTypography.textSmMedium.copyWith(color: kRedColor),
              ),
            ),
          ],
        );
      },
    );
  }
}
