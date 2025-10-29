import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_typography.dart';

class ScoreboardCardWidget extends ConsumerWidget {
  final String countryCode;
  final String? title; // Player title (e.g., "GM") - made nullable
  final String name; // Player name
  final int score; // Current score/rating
  final double? scoreChange; // Score change (can be positive or negative)
  final String? matchScore; // Match score (e.g., "2.5/3")
  final bool? isWhite; // Whether the player played white
  final String? roundLabel;
  final int index;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const ScoreboardCardWidget({
    super.key,
    required this.countryCode,
    required this.name,
    required this.score,
    this.title, // Changed to optional parameter
    this.scoreChange,
    this.matchScore,
    this.isWhite,
    this.roundLabel,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(countryCode);

    final Color backgroundColor =
        index.isOdd ? kBlack2Color : Color(0xff111111);
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
      child: Container(
        alignment: Alignment.center,
        height: 49.h,
        padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (roundLabel != null) ...[
              Padding(
                padding: EdgeInsets.only(right: 12.w),
                child: Text(
                  roundLabel!,
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor70,
                  ),
                ),
              ),
            ],
            // Player Info (flag + name)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (countryCode.toUpperCase() == 'FID') ...[
                    SizedBox(
                      width: 16.w,
                      height: 12.h,
                      child: Image.asset(
                        PngAsset.fideLogo,
                        height: 12.h,
                        width: 16.w,
                        fit: BoxFit.cover,
                        cacheWidth: 48,
                        cacheHeight: 36,
                      ),
                    ),
                    SizedBox(width: 6.w),
                  ] else if (validCountryCode.isNotEmpty) ...[
                    SizedBox(
                      width: 16.w,
                      height: 12.h,
                      child: CountryFlag.fromCountryCode(
                        validCountryCode,
                        height: 12.h,
                        width: 16.w,
                      ),
                    ),
                    SizedBox(width: 6.w),
                  ],
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
                                  color: kWhiteColor70,
                                ),
                              ),
                            TextSpan(
                              text: name,
                              style: AppTypography.textXsMedium.copyWith(
                                color: kWhiteColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            // ELO column (compact width)
            SizedBox(
              width: 70.w,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    score.toString(),
                    style: AppTypography.textXsMedium.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                  if (scoreChange != null && scoreChange != 0.0) ...[
                    SizedBox(width: 4.w),
                    Text(
                      scoreChange! > 0
                          ? '+${scoreChange!.toStringAsFixed(1)}'
                          : scoreChange!.toStringAsFixed(1),
                      style: AppTypography.textXsMedium.copyWith(
                        color: scoreChange! > 0 ? kGreenColor : kRedColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 8.w),
            // Match Score column (compact width)
            SizedBox(
              width: 50.w,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (isWhite != null) ...[
                    Container(
                      width: 8.w,
                      height: 8.h,
                      decoration: BoxDecoration(
                        color: isWhite! ? Colors.white : Colors.black,
                        shape: BoxShape.circle,
                        border: isWhite!
                            ? null
                            : Border.all(
                                color: kWhiteColor.withValues(alpha: 0.3),
                                width: 0.5,
                              ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                  ],
                  Expanded(
                    child: Text(
                      matchScore == null ? '' : matchScore!,
                      textAlign: TextAlign.start,
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
