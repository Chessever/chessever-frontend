import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/date_time_provider.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_flags/country_flags.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum PlayerView { listView, boardView }

class PlayerFirstRowDetailWidget extends HookConsumerWidget {
  final bool isCurrentPlayer;
  final PlayerView playerView;
  final GamesTourModel gamesTourModel;
  final bool isWhitePlayer;
  final ChessBoardStateNew?
  chessBoardState; // Optional state for move time calculation

  const PlayerFirstRowDetailWidget({
    super.key,
    required this.playerView,
    required this.isWhitePlayer,
    required this.gamesTourModel,
    this.isCurrentPlayer = false,
    this.chessBoardState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerCard = useMemoized(() {
      return isWhitePlayer
          ? gamesTourModel.whitePlayer
          : gamesTourModel.blackPlayer;
    }, [gamesTourModel, isWhitePlayer]);
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(playerCard.countryCode);

    // Calculate move time from state if available, otherwise use game model's time
    final moveTime = useMemoized(() {
      if (chessBoardState != null &&
          chessBoardState!.moveTimes.isNotEmpty &&
          chessBoardState!.currentMoveIndex >= 0) {
        // Look for this player's most recent move
        for (int i = chessBoardState!.currentMoveIndex; i >= 0; i--) {
          final wasMoveByThisPlayer =
              (i % 2 == 0 && isWhitePlayer) || (i % 2 == 1 && !isWhitePlayer);

          if (wasMoveByThisPlayer && i < chessBoardState!.moveTimes.length) {
            return chessBoardState!.moveTimes[i];
          }
        }
      }
      // Fallback to game model's time
      return isWhitePlayer
          ? gamesTourModel.whiteTimeDisplay
          : gamesTourModel.blackTimeDisplay;
    }, [chessBoardState, isWhitePlayer, gamesTourModel]);

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

    // Determine if we're showing scores
    final isShowingScore =
        gamesTourModel.gameStatus.isFinished &&
        (chessBoardState == null || chessBoardState!.isAtEnd);

    final timeStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              // Use same white color for both players when showing scores
              color:
                  isShowingScore
                      ? kWhiteColor
                      : (isCurrentPlayer ? kWhiteColor70 : kWhiteColor),
              fontSize: 8.5.f,
              fontWeight: FontWeight.w500,
            )
            : AppTypography.textXsMedium.copyWith(
              // Use same white color for both players when showing scores
              color:
                  isShowingScore
                      ? kWhiteColor
                      : (isCurrentPlayer ? kWhiteColor70 : kWhiteColor),
              fontSize: 14.f,
              fontWeight: FontWeight.w500,
            );

    return GestureDetector(
      onTap: () {
        final standingsAsync = ref.read(playerTourScreenProvider);

        standingsAsync.whenData((standings) {
          final playerStanding = standings.firstWhere(
            (player) => player.name == playerCard.name,
            orElse:
                () => PlayerStandingModel(
                  countryCode: playerCard.countryCode,
                  title: playerCard.title.isNotEmpty ? playerCard.title : null,
                  name: playerCard.name,
                  score: 0,
                  // Fallback if not found in standings
                  scoreChange: 0,
                  matchScore: null,
                ),
          );

          ref.read(selectedPlayerProvider.notifier).state = playerStanding;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScoreCardScreen(name: playerCard.displayName),
            ),
          );
        });
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (playerCard.countryCode.toUpperCase() == 'FID') ...[
            SizedBox(width: 16.w),
            Image.asset(
              PngAsset.fideLogo,
              height: flagHeight,
              width: flagWidth,
              fit: BoxFit.cover,
              cacheWidth: 48,
              cacheHeight: 36,
            ),
            SizedBox(width: 8.w),
          ] else if (validCountryCode.isNotEmpty) ...[
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
                      TextSpan(text: '${playerCard.title} ', style: rankStyle),
                      TextSpan(text: '${playerCard.name} ', style: nameStyle),
                      TextSpan(
                        text: '${playerCard.rating}',
                        style: ratingStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Show score for finished games at latest move, or time otherwise
          isShowingScore
              ? Container(
                  padding: EdgeInsets.symmetric(horizontal: 4.sp),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: Text(
                    gamesTourModel.gameStatus == GameStatus.whiteWins
                        ? (isWhitePlayer ? '1' : '0')
                        : gamesTourModel.gameStatus == GameStatus.blackWins
                        ? (isWhitePlayer ? '0' : '1')
                        : '½',
                    style: timeStyle,
                  ),
                )
              : _PlayerClock(
                  isWhitePlayer: isWhitePlayer,
                  gamesTourModel: gamesTourModel,
                  chessBoardState: chessBoardState,
                  isCurrentPlayer: isCurrentPlayer,
                  timeStyle: timeStyle,
                  moveTime: moveTime,
                ),
          SizedBox(width: 8.w),
        ],
      ),
    );
  }
}

class _PlayerClock extends StatelessWidget {
  const _PlayerClock({
    required this.isWhitePlayer,
    required this.gamesTourModel,
    required this.chessBoardState,
    required this.isCurrentPlayer,
    required this.timeStyle,
    required this.moveTime,
  });

  final bool isWhitePlayer;
  final GamesTourModel gamesTourModel;
  final ChessBoardStateNew? chessBoardState;
  final bool isCurrentPlayer;
  final TextStyle timeStyle;
  final String? moveTime;

  @override
  Widget build(BuildContext context) {
    // Determine if this player's clock should be counting down
    final isClockRunning = gamesTourModel.gameStatus.isOngoing &&
        gamesTourModel.lastMoveTime != null &&
        gamesTourModel.activePlayer != null &&
        ((isWhitePlayer && gamesTourModel.activePlayer == Side.white) ||
         (!isWhitePlayer && gamesTourModel.activePlayer == Side.black));

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.sp),
      decoration: BoxDecoration(
        color: isCurrentPlayer ? kDarkBlue : Colors.transparent,
      ),
      child: isClockRunning
          ? HookConsumer(builder: (context, ref, child) {
              final displayTime = ref.watch(dateTimeProvider.select((timeAsync) {
                final currentTime = timeAsync.valueOrNull;
                if (currentTime == null || gamesTourModel.lastMoveTime == null) {
                  return moveTime ?? '--:--';
                }

                // Parse static time to get total milliseconds
                final staticTime = moveTime ?? '--:--';
                final timeParts = staticTime.split(':');
                if (timeParts.length != 2) {
                  return staticTime;
                }

                try {
                  final minutes = int.parse(timeParts[0]);
                  final seconds = int.parse(timeParts[1]);
                  final totalMs = (minutes * 60 + seconds) * 1000;

                  // Calculate remaining time
                  final elapsedMs = currentTime.difference(gamesTourModel.lastMoveTime!).inMilliseconds;
                  final remainingMs = totalMs - elapsedMs;

                  // Ensure time doesn't go below 0
                  if (remainingMs <= 0) {
                    return '00:00';
                  }

                  // Format the remaining time
                  final remainingSeconds = (remainingMs / 1000).floor();
                  final displayMinutes = remainingSeconds ~/ 60;
                  final displaySecondsRem = remainingSeconds % 60;

                  return '${displayMinutes.toString().padLeft(2, '0')}:${displaySecondsRem.toString().padLeft(2, '0')}';
                } catch (e) {
                  return staticTime;
                }
              }));

              return Text(
                displayTime,
                style: timeStyle,
              );
            })
          : Text(
              moveTime ?? '--:--',
              style: timeStyle,
            ),
    );
  }
}
