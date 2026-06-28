import 'package:chessever2/utils/location_service_provider.dart';

import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';

class StandingScoreCard extends ConsumerWidget {
  final String countryCode;
  final String? title; // Player title (e.g., "GM") - made nullable
  final String name; // Player name
  final int score; // Current score/rating
  final int? scoreChange; // Score change (can be positive or negative)
  final String? matchScore; // Match score (e.g., "2.5/3")
  final int index;
  final int? rank; // Player ranking position
  final bool isFav;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final ValueChanged<LongPressStartDetails>? onLongPress;
  final VoidCallback onToggleFavorite;
  final bool hideScore;

  const StandingScoreCard({
    super.key,
    required this.countryCode,
    required this.name,
    required this.score,
    required this.onToggleFavorite,
    required this.isFav,
    this.onLongPress,
    this.title, // Changed to optional parameter
    this.scoreChange,
    this.matchScore,
    required this.index,
    this.rank,
    required this.isFirst,
    required this.isLast,
    this.hideScore = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(countryCode);

    final Color backgroundColor =
        index.isOdd ? context.colors.surface : context.colors.surface;
    BorderRadius? borderRadius;
    if (isFirst) {
      borderRadius = BorderRadius.only(
        topLeft: Radius.circular(4.br),
        topRight: Radius.circular(4.br),
      );
    } else if (isLast) {
      borderRadius = BorderRadius.only(
        bottomLeft: Radius.circular(4.br),
        bottomRight: Radius.circular(4.br),
      );
    }
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onLongPress,
      child: Container(
        alignment: Alignment.center,
        height: 49.h,
        padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 4.sp),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left padding before rank
            SizedBox(width: 8.w),
            // Rank column - left aligned for consistent start position
            if (rank != null)
              SizedBox(
                width: 20.w,
                child: Text(
                  rank.toString(),
                  style: AppTypography.textXsMedium.copyWith(
                    color: context.colors.textSecondary,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            // Flag with gap after
            SizedBox(
              width: 16.w,
              height: 12.h,
              child:
                  validCountryCode.isNotEmpty
                      ? CountryFlag.fromCountryCode(
                        validCountryCode,
                        theme: ImageTheme(height: 12.h, width: 16.w),
                      )
                      : null,
            ),
            SizedBox(width: 8.w), // Gap between flag and name
            // Player name - takes remaining space
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: 4.sp),
                child: RichText(
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  text: TextSpan(
                    children: [
                      if (title != null)
                        TextSpan(
                          text: '$title ',
                          style: AppTypography.textXsMedium.copyWith(
                            color: kLightYellowColor,
                          ),
                        ),
                      TextSpan(
                        text: name,
                        style: AppTypography.textXsMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ELO column - LEFT aligned so all ratings start at same position
            SizedBox(
              width: 80.w,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    score.toString(),
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  if (scoreChange != null && scoreChange != 0) ...[
                    SizedBox(width: 2.w),
                    Text(
                      scoreChange! > 0 ? '+$scoreChange' : '$scoreChange',
                      style: AppTypography.textXsMedium.copyWith(
                        color: scoreChange! > 0 ? kGreenColor : kRedColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Match Score column - LEFT aligned for consistent start
            if (!hideScore)
              SizedBox(
                width: 52.w,
                child: Text(
                  matchScore ?? '',
                  textAlign: TextAlign.left,
                  style: AppTypography.textXsMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            // Favorite icon
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleFavorite,
              child: Container(
                alignment: Alignment.center,
                width: 36.w,
                height: 49.h,
                child: SvgWidget(
                  isFav ? SvgAsset.favouriteRedIcon : SvgAsset.favouriteIcon2,
                  semanticsLabel: 'Favorite Icon',
                  height: 18.h,
                  width: 18.w,
                  preserveOriginalColors: isFav,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
