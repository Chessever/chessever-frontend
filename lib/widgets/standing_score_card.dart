import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import '../theme/app_theme.dart';
import '../utils/app_typography.dart';

class ScoreCard extends StatelessWidget {
  final String countryCode;
  final String? title; // Player title (e.g., "GM") - made nullable
  final String name; // Player name
  final int score; // Current score/rating
  final int? scoreChange; // Score change (can be positive or negative)
  final String matchScore; // Match score (e.g., "2.5/3")

  const ScoreCard({
    super.key,
    required this.countryCode,
    this.title, // Changed to optional parameter
    required this.name,
    required this.score,
    this.scoreChange,
    required this.matchScore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
        ),
      ),
      child: Row(
        children: [
          // Player Info (flag + name)
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 12,
                  child: CountryFlag.fromCountryCode(
                    countryCode,
                    height: 12,
                    width: 16,
                  ),
                ),
                const SizedBox(width: 4),
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
            width: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  score.toString(),
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                  ),
                ),
                if (scoreChange != null) ...[
                  const SizedBox(width: 4),
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
            width: 60,
            child: Text(
              matchScore,
              textAlign: TextAlign.end,
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
            ),
          ),
        ],
      ),
    );
  }
}
