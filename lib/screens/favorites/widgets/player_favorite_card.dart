import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:country_flags/country_flags.dart';
import '../../../utils/app_typography.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/svg_asset.dart';
import '../../../utils/png_asset.dart';
import '../../../widgets/svg_widget.dart';
import '../player_games/player_games_screen.dart';

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

    return Dismissible(
      key: Key(playerData['fideId']?.toString() ?? name),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: kRedColor,
          borderRadius: BorderRadius.circular(8.br),
        ),
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20.sp),
        child: Icon(
          Icons.delete_outline,
          color: kWhiteColor,
          size: 24.ic,
        ),
      ),
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        return await _showDeleteConfirmation(context, name);
      },
      onDismissed: (direction) {
        if (onRemoveFavorite != null) {
          onRemoveFavorite!();
        }
      },
      child: GestureDetector(
        onTap: () => _navigateToPlayerScoreCard(context, ref),
        onLongPressStart: (details) {
          HapticFeedback.lightImpact();
          _showContextMenu(context, details.globalPosition, name);
        },
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
      ),
    );
  }

  void _navigateToPlayerScoreCard(BuildContext context, WidgetRef ref) {
    try {
      debugPrint('===== PlayerFavoriteCard: playerData keys: ${playerData.keys.toList()} =====');
      debugPrint('===== PlayerFavoriteCard: fideId value: ${playerData['fideId']} (type: ${playerData['fideId'].runtimeType}) =====');

      final fideId = playerData['fideId']?.toString() ?? '';
      final name = playerData['name'] as String? ?? 'Unknown Player';
      final title = playerData['title'] as String?;
      final countryCode = playerData['countryCode'] as String? ?? '';

      debugPrint('===== Navigating with fideId: $fideId, name: $name =====');

      if (fideId.isEmpty) {
        // Handle missing fideId silently
        debugPrint('===== ERROR: fideId is empty! =====');
        return;
      }

      // Navigate to player games screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerGamesScreen(
            fideId: fideId,
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

  void _showContextMenu(BuildContext context, Offset position, String playerName) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: kBlack2Color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.br),
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: kRedColor,
                size: 20.ic,
              ),
              SizedBox(width: 12.w),
              Text(
                'Remove from favorites',
                style: AppTypography.textSmRegular.copyWith(
                  color: kRedColor,
                ),
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

  Future<bool?> _showDeleteConfirmation(BuildContext context, String playerName) {
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
              onPressed: () => Navigator.of(context).pop(true),
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