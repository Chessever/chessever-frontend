import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PlayerSecondRowDetailWidget extends ConsumerWidget {
  final String name;
  final String secondGmRank;
  final String time;
  final String countryCode;

  const PlayerSecondRowDetailWidget({
    super.key,
    required this.name,
    required this.secondGmRank,
    required this.time,
    required this.countryCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(countryCode);

    return GestureDetector(
      onTap: () {
        final standingsAsync = ref.read(playerTourScreenProvider);

        standingsAsync.whenData((standings) {
          final playerStanding = standings.firstWhere(
            (player) => player.name == name,
            orElse:
                () => PlayerStandingModel(
                  countryCode: countryCode,
                  title: secondGmRank.isNotEmpty ? secondGmRank : null,
                  name: name,
                  score: 0, // Fallback if not found in standings
                  scoreChange: 0,
                  matchScore: null,
                ),
          );

          ref.read(selectedPlayerProvider.notifier).state = playerStanding;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScoreCardScreen(
                name: name,
              ),
            ),
          );
        });
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (validCountryCode.isNotEmpty) ...[
            SizedBox(width: 16.w),
            CountryFlag.fromCountryCode(
              validCountryCode,
              height: 12.h,
              width: 16.w,
            ),
            SizedBox(width: 8.w),
          ],

          Expanded(
            child: Text(
              '$secondGmRank $name',
              style: AppTypography.textXsMedium.copyWith(
                color: kWhiteColor70,
                fontSize: 9.f,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.only(right: 2.sp, left: 2.sp),
            decoration: BoxDecoration(color: kPrimaryColor),
            child: Text(
              time,
              style: AppTypography.textXsMedium.copyWith(
                color: kWhiteColor70,
                fontSize: 9.f,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
