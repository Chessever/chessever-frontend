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

class PlayerFirstRowDetailWidget extends ConsumerWidget {
  final String name;
  final String firstGmRank;
  final String countryCode;
  final bool isCurrentPlayer;
  final bool showMoveTime;
  final String? moveTime;

  const PlayerFirstRowDetailWidget({
    super.key,
    required this.name,
    required this.firstGmRank,
    required this.countryCode,
    this.isCurrentPlayer = false,
    this.showMoveTime = false,
    this.moveTime,
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
                  title: firstGmRank.isNotEmpty ? firstGmRank : null,
                  name: name,
                  score: 0,
                  // Fallback if not found in standings
                  scoreChange: 0,
                  matchScore: null,
                ),
          );

          ref.read(selectedPlayerProvider.notifier).state = playerStanding;

          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ScoreCardScreen(name: name)),
          );
        });
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (validCountryCode.isNotEmpty) ...[
            SizedBox(width: 16.w),
            CountryFlag.fromCountryCode(
              validCountryCode,
              height: 12.h,
              width: 16.w,
            ),
            SizedBox(width: 8.w),
          ] else
            SizedBox(width: 16.w),
          Expanded(
            child: Text(
              '$firstGmRank $name',
              style: AppTypography.textXsMedium.copyWith(
                color: kWhiteColor70,
                fontSize: 9.f,
              ),
            ),
          ),

          // Show move time when available
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
            decoration: BoxDecoration(
              border: Border.all(
                color: isCurrentPlayer ? kLightBlue : Colors.transparent,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(4.br),
              color:
                  isCurrentPlayer
                      ? kLightBlue.withOpacity(0.1)
                      : Colors.transparent,
            ),
            child: Text(
              moveTime ?? '00:00',
              style: AppTypography.textXsMedium.copyWith(
                color: isCurrentPlayer ? kLightBlue : kWhiteColor70,
                fontSize: 9.f,
                fontWeight:
                    isCurrentPlayer ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(width: 8.w),
        ],
      ),
    );
  }
}
