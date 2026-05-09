import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class GamebaseSearchPlayerCard extends StatelessWidget {
  const GamebaseSearchPlayerCard({
    super.key,
    required this.player,
    required this.onTap,
    required this.onAdd,
    this.animationIndex = 0,
  });

  final GamebasePlayer player;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final int animationIndex;

  @override
  Widget build(BuildContext context) {
    final card = _PlayerCardContent(
      player: player,
      onTap: onTap,
      onLongPress: onAdd,
    );

    // Simple entry animation only - no swipe showcase
    final entryDelay = Duration(milliseconds: (animationIndex % 10) * 40);
    return card
        .animate()
        .fadeIn(duration: 200.ms, delay: entryDelay)
        .slideY(begin: 0.05, end: 0, duration: 200.ms, curve: Curves.easeOut);
  }
}

class _PlayerCardContent extends StatelessWidget {
  const _PlayerCardContent({
    required this.player,
    required this.onTap,
    required this.onLongPress,
  });

  final GamebasePlayer player;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final title = ChessTitleUtils.normalize(player.title);
    final fed = player.fed.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14.br),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: context.colors.surfaceRecessed,
            borderRadius: BorderRadius.circular(14.br),
            border: Border.all(color: context.colors.textPrimary.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(
                    color: context.colors.textPrimary.withValues(alpha: 0.08),
                  ),
                ),
                alignment: Alignment.center,
                child: FederationFlag(
                  federation: fed,
                  width: 22.w,
                  height: 16.h,
                  borderRadius: BorderRadius.circular(3.br),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (title.isNotEmpty) ...[
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.textPrimary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6.br),
                            ),
                            child: Text(
                              title,
                              style: AppTypography.textXsBold.copyWith(
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                        ],
                        Expanded(
                          child: Text(
                            player.displayName,
                            style: AppTypography.textSmBold.copyWith(
                              color: context.colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    Row(
                      children: [
                        if (fed.isNotEmpty)
                          Text(
                            fed,
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textPrimary.withValues(alpha: 0.55),
                            ),
                          ),
                        if (fed.isNotEmpty) SizedBox(width: 10.w),
                        ..._buildRatings(context),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.all(8.sp),
                decoration: BoxDecoration(
                  color: context.colors.textPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10.br),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18.sp,
                  color: context.colors.textPrimary.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRatings(BuildContext context) {
    final ratings = <Widget>[];

    if (player.ratingClassical != null && player.ratingClassical! > 0) {
      ratings.add(_RatingChip(label: 'C', value: player.ratingClassical!));
    }
    if (player.ratingRapid != null && player.ratingRapid! > 0) {
      if (ratings.isNotEmpty) ratings.add(SizedBox(width: 8.w));
      ratings.add(_RatingChip(label: 'R', value: player.ratingRapid!));
    }
    if (player.ratingBlitz != null && player.ratingBlitz! > 0) {
      if (ratings.isNotEmpty) ratings.add(SizedBox(width: 8.w));
      ratings.add(_RatingChip(label: 'B', value: player.ratingBlitz!));
    }

    if (ratings.isEmpty) {
      ratings.add(
        Text(
          'Unrated',
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    return ratings;
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.textXsBold.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
        ),
        SizedBox(width: 2.w),
        Text(
          value.toString(),
          style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
