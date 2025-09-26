import 'dart:math' as math;
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/providers/player_ratings_provider.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_appbar.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../theme/app_theme.dart';
import '../tour_detail/games_tour/models/games_tour_model.dart';
import '../tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import '../chessboard/chess_board_screen_new.dart';
import '../chessboard/provider/chess_board_screen_provider_new.dart';

final selectedPlayerProvider = StateProvider<PlayerStandingModel?>(
  (ref) => null,
);

class ScoreCardScreen extends ConsumerWidget {
  final String name;
  const ScoreCardScreen({super.key, required this.name});

  // Helper function to extract rating from PGN with multiple fallbacks
  double? _extractRatingFromPGN(String? pgn, bool isWhite) {
    if (pgn == null || pgn.isEmpty) return null;

    // Try multiple PGN formats for rating extraction (supporting decimal ratings)
    final patterns = isWhite
        ? [
            RegExp(r'\[WhiteElo "(\d+(?:\.\d+)?)"\]'),        // Standard format [WhiteElo "2738.5"]
            RegExp(r'\[WhiteElo (\d+(?:\.\d+)?)\]'),          // Without quotes [WhiteElo 2738.5]
            RegExp(r'WhiteElo\s+(\d+(?:\.\d+)?)'),            // Simplified format
          ]
        : [
            RegExp(r'\[BlackElo "(\d+(?:\.\d+)?)"\]'),        // Standard format [BlackElo "2688.5"]
            RegExp(r'\[BlackElo (\d+(?:\.\d+)?)\]'),          // Without quotes [BlackElo 2688.5]
            RegExp(r'BlackElo\s+(\d+(?:\.\d+)?)'),            // Simplified format
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

  // Get player rating from game, with robust PGN fallback
  double _getPlayerRating(GamesTourModel game, String playerName) {
    final isWhite = game.whitePlayer.name == playerName;
    final playerCard = isWhite ? game.whitePlayer : game.blackPlayer;

    // First try to get rating from player card
    if (playerCard.rating > 0) {
      return playerCard.rating.toDouble();
    }

    // Fallback to PGN
    final pgnRating = _extractRatingFromPGN(game.pgn, isWhite);
    if (pgnRating != null && pgnRating > 0) {
      return pgnRating;
    }

    // If both fail, use a default rating to ensure we don't skip the game
    // Using 1500 as a reasonable default for unrated players
    return 1500.0;
  }

  // Calculate K-factor based on FIDE official rules
  // Note: This is a simplified implementation. Full FIDE rules require:
  // - Player age (for under 18 rule)
  // - Number of games played (for new player rule)
  // - Historical peak rating (for "ever reached 2400" rule)
  int _getKFactor(double rating) {
    // FIDE Rules:
    // K = 40: For new players until 30 games completed, OR under 18 with rating < 2300
    // K = 20: For players with rating under 2400 (and not in above categories)
    // K = 10: Once published rating reached 2400 (stays 10 even if drops below)

    // Simplified implementation based on current rating only:
    // Since we don't have player age or games played data, we use conservative values
    if (rating >= 2400) {
      return 10; // Once published rating reached 2400
    } else {
      // For all players under 2400 (most common case)
      // We use K=20 as the standard value for established players
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
    // Determine actual score based on game result
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
        return 0; // Ongoing or unknown games don't have rating changes
    }

    // Calculate rating difference (capped at 400 per FIDE rules)
    double ratingDiff = (opponentRating - playerRating).clamp(-400.0, 400.0);

    // Calculate expected score using FIDE formula
    double expectedScore = 1 / (1 + math.pow(10, ratingDiff / 400.0));

    // Get K-factor
    int kFactor = _getKFactor(playerRating);

    // Calculate rating change
    double ratingChange = kFactor * (actualScore - expectedScore);

    return ratingChange;
  }

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
            ? player.name.trim().substring(0, math.min(2, player.name.trim().length))
            : '';

    // Calculate total performance as sum of all individual game rating changes
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

    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
          ScoreboardAppbar(playerName: name),
          SizedBox(height: 24.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    // Title badge/chip
                    if (player.title != null && player.title!.isNotEmpty)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
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
                    // Player initials container
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
                      // First row: Performance and Score
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
                                totalPerformance >= 0
                                    ? '+${totalPerformance.toStringAsFixed(1)}'
                                    : totalPerformance.toStringAsFixed(1),
                                style: AppTypography.textSmMedium.copyWith(
                                  color: totalPerformance > 0
                                      ? kGreenColor
                                      : totalPerformance < 0
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
                                player.matchScore ?? "",
                                style: AppTypography.textSmMedium.copyWith(
                                  color: kWhiteColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      // Second row: Ratings displayed horizontally
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Classical Rating
                          _RatingDisplay(
                            playerName: player.name,
                            timeControlType: "standard",
                            icon: Icons.access_time,
                            iconColor: kWhiteColor,
                          ),
                          // Rapid Rating
                          _RatingDisplay(
                            playerName: player.name,
                            timeControlType: "rapid",
                            icon: Icons.flash_on,
                            iconColor: Colors.orange,
                          ),
                          // Blitz Rating
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
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: playerGames.length,
              itemBuilder: (context, index) {
                final game = playerGames[index];
                final isWhite = game.whitePlayer.name == player.name;
                final opponent = isWhite ? game.blackPlayer : game.whitePlayer;
                final result = _getGameResult(game, player.name);

                // Get player and opponent ratings
                final playerRating = _getPlayerRating(game, player.name);
                final opponentRating = _getPlayerRating(game, opponent.name);

                // Calculate FIDE Elo rating change for this game
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
                    score: opponent.rating,  // Show opponent's rating
                    scoreChange: ratingChange != 0.0 ? ratingChange : null,  // Show precise decimal value
                    matchScore: result,  // Show result without rating change (it's now in scoreChange)
                    index: index,
                    isFirst: index == 0,
                    isLast: index == playerGames.length - 1,
                    onTap: () {
                      // Navigate to ChessBoardScreenNew
                      ref.read(chessboardViewFromProviderNew.notifier).state =
                          ChessboardView.tour;

                      // Use the same games list that was used to filter playerGames
                      // to ensure consistency in gameId matching
                      final gameIndex = allGames.indexWhere((g) => g.gameId == game.gameId);

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
        Icon(
          icon,
          size: 16.sp,
          color: iconColor,
        ),
        SizedBox(width: 4.w),
        ratingAsync.when(
          data: (rating) => Text(
            rating?.toString() ?? '-',
            style: AppTypography.textSmMedium.copyWith(
              color: kWhiteColor,
              fontSize: 14.sp,
            ),
          ),
          loading: () => Skeletonizer(
            enabled: true,
            ignoreContainers: true,
            effect: ShimmerEffect(
              baseColor: Color(0xFF2A2A2A),
              highlightColor: Color(0xFF3A3A3A),
            ),
            child: Text(
              '2400', // 4-digit placeholder
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor,
                fontSize: 14.sp,
              ),
            ),
          ),
          error: (_, __) => Text(
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
