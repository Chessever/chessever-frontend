import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:country_flags/country_flags.dart';
import '../../../utils/app_typography.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/png_asset.dart';

class PlayerFavoriteCard extends ConsumerWidget {
  final Map<String, dynamic> playerData;
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
    final name = playerData['name'] as String? ?? 'Unknown Player';
    final title = playerData['title'] as String? ?? '';
    final countryCode = playerData['countryCode'] as String? ?? '';
    final rating = playerData['rating'] as int? ?? 0;

    return Dismissible(
      key: Key(playerData['fideId']?.toString() ?? name),
      direction: DismissDirection.endToStart,
      background: Container(
        color: kRedColor,
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20.sp),
        child: Icon(Icons.delete_outline, color: kWhiteColor, size: 24.ic),
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
            color: isEven ? kBlack2Color : kBackgroundColor.withOpacity(0.5),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
          child: Row(
            children: [
              // Rank
              SizedBox(
                width: 24.w,
                child: Text(
                  '$rank.',
                  style: AppTypography.textMdMedium.copyWith(
                    color: kWhiteColor,
                    fontSize: 16.sp,
                  ),
                ),
              ),

              SizedBox(width: 16.w),

              // Country flag
              if (countryCode.isNotEmpty)
                Container(
                  margin: EdgeInsets.only(right: 12.w),
                  child:
                      countryCode.toUpperCase() == 'FID'
                          ? Image.asset(
                            PngAsset.fideLogo,
                            height: 20.h,
                            width: 28.w,
                            fit: BoxFit.cover,
                          )
                          : CountryFlag.fromCountryCode(
                            countryCode,
                            height: 20.h,
                            width: 28.w,
                          ),
                ),

              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      if (title.isNotEmpty) ...[
                        TextSpan(
                          text: '$title ',
                          style: AppTypography.textMdMedium.copyWith(
                            color: kWhiteColor,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      TextSpan(
                        text: name,
                        style: AppTypography.textMdMedium.copyWith(
                          color: kWhiteColor,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              SizedBox(width: 16.w),

              // Rating
              if (rating > 0)
                SizedBox(
                  width: 60.w,
                  child: Text(
                    '$rating',
                    style: AppTypography.textMdMedium.copyWith(
                      color: kWhiteColor,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w500,
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
      ),
    );
  }

  void _navigateToPlayerScoreCard(BuildContext context, WidgetRef ref) {
    try {
      final name = playerData['name'] as String? ?? 'Unknown Player';
      final title = playerData['title'] as String?;
      final countryCode = playerData['countryCode'] as String? ?? '';
      final rating = playerData['score'] as int? ?? 0;
      final fideId =
          playerData['fideId'] != null
              ? int.tryParse(playerData['fideId'].toString())
              : null;
      final matchScore = playerData['matchScore'] as String?;
      final scoreChange = (playerData['scoreChange'] as int?) ?? 0;

      final player = PlayerStandingModel(
        countryCode: countryCode,
        title: title,
        name: name,
        score: rating,
        scoreChange: scoreChange,
        matchScore: matchScore,
        fideId: fideId,
      );

      ref.read(selectedPlayerProvider.notifier).state = player;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ScoreCardScreen(name: name)),
      );
    } catch (e) {
      debugPrint('===== ERROR navigating to player games: $e =====');
    }
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
