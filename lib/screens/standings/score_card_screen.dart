import 'dart:math' as math;
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/providers/player_ratings_provider.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_appbar.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';

final selectedPlayerProvider = StateProvider<PlayerStandingModel?>(
  (ref) => null,
);

final playerGamesProvider =
    FutureProvider.family<List<GamesTourModel>, PlayerStandingModel>((
      ref,
      player,
    ) async {
      try {
        final gameRepo = ref.read(gameRepositoryProvider);

        List<dynamic> games = [];

        if (player.fideId != null) {
          try {
            games = await gameRepo.getGamesByFideId(
              player.fideId.toString(),
              limit: 50,
            );
          } catch (e) {
            debugPrint('Error fetching by fideId: $e');
          }
        }

        if (games.isEmpty) {
          games = await gameRepo.getGamesByPlayerName(player.name, limit: 50);
        }

        return games.map((game) => GamesTourModel.fromGame(game)).toList();
      } catch (e, stack) {
        debugPrint('Error: $e');
        return [];
      }
    });

class ScoreCardScreen extends ConsumerWidget {
  const ScoreCardScreen({super.key});

  double? _extractRatingFromPGN(String? pgn, bool isWhite) {
    if (pgn == null || pgn.isEmpty) return null;

    final patterns =
        isWhite
            ? [
              RegExp(r'\[WhiteElo "(\d+(?:\.\d+)?)"\]'),
              RegExp(r'\[WhiteElo (\d+(?:\.\d+)?)\]'),
              RegExp(r'WhiteElo\s+(\d+(?:\.\d+)?)'),
            ]
            : [
              RegExp(r'\[BlackElo "(\d+(?:\.\d+)?)"\]'),
              RegExp(r'\[BlackElo (\d+(?:\.\d+)?)\]'),
              RegExp(r'BlackElo\s+(\d+(?:\.\d+)?)'),
            ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(pgn);
      if (match != null && match.group(1) != null) {
        final rating = double.tryParse(match.group(1)!);
        if (rating != null && rating > 0) {
          return rating;
        }
      }
    }
    return null;
  }

  // Get player rating from game
  double _getPlayerRating(GamesTourModel game, String playerName) {
    final isWhite = game.whitePlayer.name == playerName;
    final playerCard = isWhite ? game.whitePlayer : game.blackPlayer;

    if (playerCard.rating > 0) {
      return playerCard.rating.toDouble();
    }

    final pgnRating = _extractRatingFromPGN(game.pgn, isWhite);
    if (pgnRating != null && pgnRating > 0) {
      return pgnRating;
    }

    return 1500.0;
  }

  // Calculate K-factor
  int _getKFactor(double rating) {
    if (rating >= 2400) {
      return 10;
    } else {
      return 20;
    }
  }

  // Calculate FIDE Elo rating change
  double _calculateFideRatingChange(
    double playerRating,
    double opponentRating,
    GameStatus gameStatus,
    String playerName,
    GamesTourModel game,
  ) {
    double actualScore;
    final isWhite = game.whitePlayer.name == playerName;

    switch (gameStatus) {
      case GameStatus.whiteWins:
        actualScore = isWhite ? 1.0 : 0.0;
        break;
      case GameStatus.blackWins:
        actualScore = isWhite ? 0.0 : 1.0;
        break;
      case GameStatus.draw:
        actualScore = 0.5;
        break;
      default:
        return 0;
    }

    double ratingDiff = (opponentRating - playerRating).clamp(-400.0, 400.0);
    double expectedScore = 1 / (1 + math.pow(10, ratingDiff / 400.0));
    int kFactor = _getKFactor(playerRating);
    double ratingChange = kFactor * (actualScore - expectedScore);

    return ratingChange;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(selectedPlayerProvider);

    if (player == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedBroadcast = ref.watch(selectedBroadcastModelProvider);

    List<GamesTourModel> allGames = [];
    bool isLoadingGames = false;
    bool hasTournamentContext = false;

    if (selectedBroadcast != null) {
      hasTournamentContext = true;
      final gamesTourAsync = ref.watch(gamesTourScreenProvider);
      allGames = gamesTourAsync.when(
        data: (data) => data.gamesTourModels,
        loading: () {
          isLoadingGames = true;
          return [];
        },
        error: (_, __) => [],
      );
    } else {
      hasTournamentContext = false;
      final playerGamesAsync = ref.watch(playerGamesProvider(player));
      allGames = playerGamesAsync.when(
        data: (games) => games,
        loading: () {
          isLoadingGames = true;
          return [];
        },
        error: (_, __) => [],
      );
    }

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
            ? player.name.trim().substring(
              0,
              math.min(2, player.name.trim().length),
            )
            : '';

    // Calculate total performance
    double totalPerformance = 0.0;
    for (final game in playerGames) {
      final playerRating = _getPlayerRating(game, player.name);
      final isWhite = game.whitePlayer.name == player.name;
      final opponent = isWhite ? game.blackPlayer : game.whitePlayer;
      final opponentRating = _getPlayerRating(game, opponent.name);

      if (playerRating > 0 && opponentRating > 0) {
        final ratingChange = _calculateFideRatingChange(
          playerRating,
          opponentRating,
          game.gameStatus,
          player.name,
          game,
        );
        totalPerformance += ratingChange;
      }
    }

    final displayPerformance =
        playerGames.isEmpty
            ? (player.scoreChange.toDouble())
            : totalPerformance;
    final displayScore = player.matchScore ?? "0 / 0";

    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
          ScoreboardAppbar(),
          SizedBox(height: 24.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    if (player.title != null && player.title!.isNotEmpty)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 2.h,
                        ),
                        margin: EdgeInsets.only(bottom: 4.h),
                        decoration: BoxDecoration(
                          color: kGreenColor,
                          borderRadius: BorderRadius.circular(12.sp),
                        ),
                        child: Text(
                          player.title!,
                          style: AppTypography.textXsMedium.copyWith(
                            color: Colors.white,
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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
                  ],
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                                displayPerformance >= 0
                                    ? '+${displayPerformance.toStringAsFixed(1)}'
                                    : displayPerformance.toStringAsFixed(1),
                                style: AppTypography.textSmMedium.copyWith(
                                  color:
                                      displayPerformance > 0
                                          ? kGreenColor
                                          : displayPerformance < 0
                                          ? kRedColor
                                          : kWhiteColor,
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
                                displayScore,
                                style: AppTypography.textSmMedium.copyWith(
                                  color: kWhiteColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _RatingDisplay(
                            playerName: player.name,
                            timeControlType: "standard",
                            icon: Icons.access_time,
                            iconColor: kWhiteColor,
                          ),
                          _RatingDisplay(
                            playerName: player.name,
                            timeControlType: "rapid",
                            icon: Icons.flash_on,
                            iconColor: Colors.orange,
                          ),
                          _RatingDisplay(
                            playerName: player.name,
                            timeControlType: "blitz",
                            icon: Icons.bolt,
                            iconColor: kRedColor,
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
            child:
                isLoadingGames
                    ? const Center(child: CircularProgressIndicator())
                    : playerGames.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 48.ic,
                            color: kWhiteColor.withOpacity(0.5),
                          ),
                          SizedBox(height: 16.h),
                          Text(
                            hasTournamentContext
                                ? 'No games in this tournament'
                                : 'No games available',
                            style: AppTypography.textMdMedium.copyWith(
                              color: kWhiteColor.withOpacity(0.7),
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            hasTournamentContext
                                ? 'This player has not played in this tournament yet'
                                : 'Games will appear once they are played',
                            textAlign: TextAlign.center,
                            style: AppTypography.textSmRegular.copyWith(
                              color: kWhiteColor.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: playerGames.length,
                      itemBuilder: (context, index) {
                        final game = playerGames[index];
                        final isWhite = game.whitePlayer.name == player.name;
                        final opponent =
                            isWhite ? game.blackPlayer : game.whitePlayer;
                        final result = _getGameResult(game, player.name);

                        final playerRating = _getPlayerRating(
                          game,
                          player.name,
                        );
                        final opponentRating = _getPlayerRating(
                          game,
                          opponent.name,
                        );

                        double ratingChange = 0.0;
                        if (playerRating > 0 && opponentRating > 0) {
                          ratingChange = _calculateFideRatingChange(
                            playerRating,
                            opponentRating,
                            game.gameStatus,
                            player.name,
                            game,
                          );
                        }

                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.0.sp),
                          child: ScoreboardCardWidget(
                            countryCode: opponent.countryCode,
                            title: opponent.title,
                            name: opponent.name,
                            score: opponent.rating,
                            scoreChange:
                                ratingChange != 0.0 ? ratingChange : null,
                            matchScore: result,
                            index: index,
                            isFirst: index == 0,
                            isLast: index == playerGames.length - 1,
                            onTap: () {
                              ref
                                  .read(chessboardViewFromProviderNew.notifier)
                                  .state = ChessboardView.tour;

                              final gameIndex = allGames.indexWhere(
                                (g) => g.gameId == game.gameId,
                              );

                              if (gameIndex != -1) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => ChessBoardScreenNew(
                                          games: allGames,
                                          currentIndex: gameIndex,
                                        ),
                                  ),
                                );
                              }
                            },
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
        return isWhite ? '1-0' : '0-1';
      case GameStatus.blackWins:
        return isWhite ? '0-1' : '1-0';
      case GameStatus.draw:
        return '½-½';
      case GameStatus.ongoing:
        return isWhite ? 'White to move' : 'Black to move';
      case GameStatus.unknown:
        return '-';
    }
  }
}

class _RatingDisplay extends ConsumerWidget {
  final String playerName;
  final String timeControlType;
  final IconData icon;
  final Color iconColor;

  const _RatingDisplay({
    required this.playerName,
    required this.timeControlType,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingRequest = PlayerRatingRequest(
      playerName: playerName,
      timeControlType: timeControlType,
    );

    final ratingAsync = ref.watch(playerLatestRatingProvider(ratingRequest));

    return Row(
      children: [
        Icon(icon, size: 16.sp, color: iconColor),
        SizedBox(width: 4.w),
        ratingAsync.when(
          data:
              (rating) => Text(
                rating?.toString() ?? '-',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor,
                  fontSize: 14.sp,
                ),
              ),
          loading:
              () => Skeletonizer(
                enabled: true,
                ignoreContainers: true,
                effect: ShimmerEffect(
                  baseColor: Color(0xFF2A2A2A),
                  highlightColor: Color(0xFF3A3A3A),
                ),
                child: Text(
                  '2400',
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor,
                    fontSize: 14.sp,
                  ),
                ),
              ),
          error:
              (_, __) => Text(
                '-',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor,
                  fontSize: 14.sp,
                ),
              ),
        ),
      ],
    );
  }
}
