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

enum PlayerView { listView, boardView }

class PlayerFirstRowDetailWidget extends ConsumerWidget {
  final String name;
  final String firstGmRank;
  final String countryCode;
  final int rating;
  final bool isCurrentPlayer;
  final bool showMoveTime;
  final String? moveTime;
  final PlayerView playerView;

  const PlayerFirstRowDetailWidget({
    super.key,
    required this.name,
    required this.firstGmRank,
    required this.countryCode,
    required this.rating,
    required this.playerView,
    this.isCurrentPlayer = false,
    this.showMoveTime = false,
    this.moveTime,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(countryCode);

    final rankStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              fontSize: 8.5.f,
              fontWeight: FontWeight.w600,
              color: kLightYellowColor,
              height: 14.23.h / 8.5.h,
            )
            : AppTypography.textXsMedium.copyWith(
              color: kLightYellowColor,
              fontWeight: FontWeight.w600,
              fontSize: 14.f,
            );

    final nameStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              fontSize: 8.5.f,
              fontWeight: FontWeight.w500,
              color: kWhiteColor,
              height: 14.23.h / 8.5.h,
            )
            : AppTypography.textXsMedium.copyWith(
              color: kWhiteColor,
              fontWeight: FontWeight.w600,
              fontSize: 14.f,
            );

    final ratingStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              fontSize: 8.5.f,
              fontWeight: FontWeight.w500,
              color: kWhiteColor70,
              height: 14.23.h / 8.5.h,
            )
            : AppTypography.textXsMedium.copyWith(
              color: kWhiteColor70,
              fontWeight: FontWeight.w500,
              fontSize: 14.f,
            );

    final flagHeight = playerView == PlayerView.listView ? 10.h : 12.h;
    final flagWidth = playerView == PlayerView.listView ? 12.w : 16.w;

    final timeStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              color: isCurrentPlayer ? kWhiteColor70 : kWhiteColor,
              fontSize: 8.5.f,
              fontWeight: FontWeight.w500,
            )
            : AppTypography.textXsMedium.copyWith(
              color: isCurrentPlayer ? kWhiteColor70 : kWhiteColor,
              fontSize: 14.f,
              fontWeight: FontWeight.w500,
            );

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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (validCountryCode.isNotEmpty) ...[
            SizedBox(width: 16.w),
            CountryFlag.fromCountryCode(
              validCountryCode,
              height: flagHeight,
              width: flagWidth,
            ),
            SizedBox(width: 8.w),
          ] else
            SizedBox(width: 16.w),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$firstGmRank ',
                        style: rankStyle,
                      ),
                      TextSpan(
                        text: '$name ',
                        style: nameStyle,
                      ),
                      TextSpan(
                        text: '$rating',
                        style: ratingStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Show move time when available
          Container(
            padding: EdgeInsets.symmetric(horizontal: 4.sp),
            decoration: BoxDecoration(
              color: isCurrentPlayer ? kDarkBlue : Colors.transparent,
            ),
            child: Text(
              moveTime ?? '--:--',
              style: timeStyle,
            ),
          ),
          SizedBox(width: 8.w),
        ],
      ),
    );
  }
}
