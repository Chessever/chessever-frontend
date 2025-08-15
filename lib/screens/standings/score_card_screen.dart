import 'dart:math';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_appbar.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../theme/app_theme.dart';
import '../tournaments/model/games_tour_model.dart';
import '../tournaments/providers/games_tour_screen_provider.dart';

final selectedPlayerProvider = StateProvider<PlayerStandingModel?>(
  (ref) => null,
);

class ScoreCardScreen extends ConsumerWidget {
  const ScoreCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(selectedPlayerProvider);

    if (player == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final allGames =
        ref.watch(gamesTourScreenProvider).value?.gamesTourModels ?? [];
    final playerGames =
        allGames
            .where(
              (game) =>
                  game.whitePlayer.name == player.name ||
                  game.blackPlayer.name == player.name,
            )
            .toList()
          ..sort((a, b) {
            final aOpponent =
                a.whitePlayer.name == player.name
                    ? a.blackPlayer
                    : a.whitePlayer;
            final bOpponent =
                b.whitePlayer.name == player.name
                    ? b.blackPlayer
                    : b.whitePlayer;
            return bOpponent.rating.compareTo(aOpponent.rating);
          });

    final nameParts = player.name.split(',');
    final initials =
        nameParts.length > 1
            ? '${nameParts[0].trim().isNotEmpty ? nameParts[0].trim()[0] : ''}'
                '${nameParts[1].trim().isNotEmpty ? nameParts[1].trim()[0] : ''}'
            : player.name.trim().isNotEmpty
            ? player.name.trim().substring(0, min(2, player.name.trim().length))
            : '';

    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
          const ScoreboardAppbar(),
          SizedBox(height: 16.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 65.h,
                  width: 64.w,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: kPrimaryColor,
                  ),
                  child: Center(
                    child: Text(
                      initials.toUpperCase(),
                      style: AppTypography.textSmMedium.copyWith(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "PERFORMANCE",
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            player.score.toString(),
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "SCORE",
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            player.matchScore ?? "",
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "RATING",
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            "${player.scoreChange >= 0 ? '+' : ''}${player.scoreChange}",
                            style: AppTypography.textSmMedium.copyWith(
                              color: kGreenColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24.h),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: playerGames.length,
              itemBuilder: (context, index) {
                final game = playerGames[index];
                final isWhite = game.whitePlayer.name == player.name;
                final opponent = isWhite ? game.blackPlayer : game.whitePlayer;
                final result = _getGameResult(game, player.name);

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0.sp),
                  child: ScoreboardCardWidget(
                    countryCode: opponent.countryCode,
                    title: opponent.title,
                    name: opponent.name,
                    score: opponent.rating,
                    scoreChange: null,
                    matchScore: result,
                    index: index,
                    isFirst: index == 0,
                    isLast: index == playerGames.length - 1,
                    onTap: () {},
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getGameResult(GamesTourModel game, String playerName) {
    final isWhite = game.whitePlayer.name == playerName;
    switch (game.gameStatus) {
      case GameStatus.whiteWins:
        return isWhite ? '1-0 (W)' : '0-1 (L)';
      case GameStatus.blackWins:
        return isWhite ? '0-1 (L)' : '1-0 (W)';
      case GameStatus.draw:
        return '½-½ (D)';
      case GameStatus.ongoing:
        return isWhite ? 'White to move' : 'Black to move';
      case GameStatus.unknown:
        return '-';
    }
  }
}
