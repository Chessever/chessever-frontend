import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import '../theme/app_theme.dart';
import '../utils/app_typography.dart';

class StandingScoreCard extends StatelessWidget {
  final String countryCode;
  final String? title; // Player title (e.g., "GM") - made nullable
  final String name; // Player name
  final int score; // Current score/rating
  final int? scoreChange; // Score change (can be positive or negative)
  final String? matchScore; // Match score (e.g., "2.5/3")

  const StandingScoreCard({
    super.key,
    required this.countryCode,
    this.title, // Changed to optional parameter
    required this.name,
    required this.score,
    this.scoreChange,
    this.matchScore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48.h,
      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4.br),
          topRight: Radius.circular(4.br),
        ),
      ),
      child: Row(
        children: [
          // Player Info (flag + name)
          Expanded(
            child: Row(
              children: [
                if (countryCode.isNotEmpty) ...[
                  SizedBox(
                    width: 16.w,
                    height: 12.h,
                    child: CountryFlag.fromCountryCode(
                      countryCode,
                      height: 12.h,
                      width: 16.w,
                    ),
                  ),
                  SizedBox(width: 4.w),
                ],
                Flexible(
                  child: RichText(
                    overflow: TextOverflow.ellipsis,
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
    );
  }
}
