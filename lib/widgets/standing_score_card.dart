import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../theme/app_theme.dart';
import '../utils/app_typography.dart';

class StandingScoreCard extends ConsumerWidget {
  final String countryCode;
  final String? title; // Player title (e.g., "GM") - made nullable
  final String name; // Player name
  final int score; // Current score/rating
  final int? scoreChange; // Score change (can be positive or negative)
  final String? matchScore; // Match score (e.g., "2.5/3")
  final int index;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const StandingScoreCard({
    super.key,
    required this.countryCode,
    required this.name,
    required this.score,
    this.title, // Changed to optional parameter
    this.scoreChange,
    this.matchScore,
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
                        'assets/pngs/fide_logo.png',
                        height: 12.h,
                        width: 16.w,
                        fit: BoxFit.cover,
                        cacheWidth: 48,
                        cacheHeight: 36,
                      ),
                    ),
                    SizedBox(width: 4.w),
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
                    SizedBox(width: 4.w),
                  ],
                  Flexible(
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
                                  color: kWhiteColor,
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

            // ELO column (fixed width to match header)
            SizedBox(
              width: 100.w,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    score.toString(),
                    style: AppTypography.textXsMedium.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                  if (scoreChange != null && scoreChange != 0) ...[
                    SizedBox(width: 4.w),
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

            // Match Score column (fixed width to match header)
            SizedBox(
              width: 60.w,
              child: Text(
                matchScore == null ? '' : matchScore!,
                textAlign: TextAlign.end,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
