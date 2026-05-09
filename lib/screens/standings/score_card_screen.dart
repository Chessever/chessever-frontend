import 'dart:math' as math;
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/player_backfill_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:chessever2/widgets/fullscreen_image_viewer.dart';
import 'package:chessever2/screens/standings/providers/player_ratings_provider.dart'
    show AllRatingsRequest, allRatingsProvider;
import 'package:chessever2/screens/standings/providers/twic_scorecard_event_games_provider.dart';
import 'package:chessever2/screens/standings/providers/player_utils_provider.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/player_profile/widgets/performance_stats_row.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:heroine/heroine.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/favorite_limit_guard.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:motor/motor.dart';

final selectedPlayerProvider = StateProvider<PlayerStandingModel?>(
  (ref) => null,
);

/// Provider to store the current games context for ScoreCardScreen.
/// This allows the screen to display games from the correct source (favorites, countrymen, etc.)
/// instead of falling back to fetching all player games globally.
final scoreCardGamesContextProvider = StateProvider<List<GamesTourModel>?>(
  (ref) => null,
);

/// Explicit flag to indicate whether ScoreCardScreen should display event context.
/// This is set by the navigation source (ChessBoard player tap, Favorites tabs, etc.)
/// to explicitly control whether performance/score/rating should be calculated
/// and whether games should show round numerization.
///
/// - true: Games are from a specific event (tournament), show round numbers, calculate stats
/// - false: Games are from player's full history, no round numbers, show "-" for stats
final scoreCardHasEventContextProvider = StateProvider<bool>((ref) => false);

/// Source context used when opening PlayerProfileScreen from scorecard.
/// Defaults to Supabase to preserve existing flows.
final scoreCardPlayerProfileDataSourceProvider =
    StateProvider<PlayerProfileDataSource>(
      (ref) => PlayerProfileDataSource.supabase,
    );

final playerGamesProvider = FutureProvider.family<
  List<GamesTourModel>,
  PlayerStandingModel
>((ref, player) async {
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
    var allGames = games.map((game) => GamesTourModel.fromGame(game)).toList();

    // Sort by date (descending) - most recent games first
    final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
    allGames.sort((a, b) {
      final aTime = a.lastMoveTime ?? epochFallback;
      final bTime = b.lastMoveTime ?? epochFallback;
      return bTime.compareTo(aTime);
    });

    return allGames;
  } catch (e, _) {
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

  // Get player rating from game. `isWhite` must be resolved by the caller
  // (via fide/fuzzy-name matching) since some broadcasts emit the same
  // player under different name spellings across rounds.
  double _getPlayerRatingForSide(GamesTourModel game, bool isWhite) {
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

  // Heuristic K-factor fallback used only when FIDE's per-time-control K is
  // unavailable. FIDE's authoritative K (sticky 2400 → 10, U18 < 2300 → 40,
  // default 20) is stored in `chess_players.{k,rapid_k,blitz_k}` and should
  // be preferred via `fideK` in `_calculateFideRatingChange`.
  int _heuristicKFactor(double rating, {String? title, String? timeControl}) {
    final tc = timeControl?.toLowerCase();
    if (tc == 'rapid' || tc == 'blitz') {
      return 20;
    }

    if (rating >= 2400) {
      return 10;
    }

    if (title != null) {
      final t = title.toUpperCase();
      if (t == 'GM' || t == 'IM') {
        return 10;
      }
    }

    return 20;
  }

  // Calculate FIDE Elo rating change.
  // Pass [fideK] from `chess_players` for the event's time control to use
  // FIDE's authoritative K. Pass [playerRatingOverride] to use the player's
  // FIDE rating for that same time control instead of the per-game PGN value.
  double _calculateFideRatingChange(
    double playerRating,
    double opponentRating,
    GameStatus gameStatus,
    bool isWhite,
    GamesTourModel game, {
    int? fideK,
    double? playerRatingOverride,
  }) {
    double actualScore;

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

    final effectivePlayerRating = playerRatingOverride ?? playerRating;
    double ratingDiff =
        (opponentRating - effectivePlayerRating).clamp(-400.0, 400.0);
    double expectedScore = 1 / (1 + math.pow(10, ratingDiff / 400.0));
    final playerTitle =
        isWhite ? game.whitePlayer.title : game.blackPlayer.title;
    final int kFactor = fideK ??
        _heuristicKFactor(
          effectivePlayerRating,
          title: playerTitle,
          timeControl: game.timeControl,
        );
    double ratingChange = kFactor * (actualScore - expectedScore);

    return ratingChange;
  }

  List<GamesTourModel> _toGamesTourModels(List<Games> games) {
    final result = <GamesTourModel>[];
    for (final game in games) {
      try {
        result.add(GamesTourModel.fromGame(game));
      } catch (_) {
        // Skip malformed rows to keep scorecard resilient.
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPlayer = ref.watch(selectedPlayerProvider);

    if (selectedPlayer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final backfilledPlayerAsync = ref.watch(
      backfilledStandingPlayerProvider(selectedPlayer),
    );
    final player = backfilledPlayerAsync.valueOrNull ?? selectedPlayer;

    // FIDE per-time-control rating + K-factor for the selected player.
    // Used to drive correct Elo change calculations: a 2410 standard player
    // can have K=10 standard but K=40 rapid (e.g. U18 with rapid_rating < 2300),
    // so we must match the K to the event's time control, not guess.
    final playerRatingsAsync = ref.watch(
      allRatingsProvider(
        AllRatingsRequest(fideId: player.fideId, playerName: player.name),
      ),
    );
    final playerRatings = playerRatingsAsync.valueOrNull;

    final selectedBroadcast = ref.watch(selectedBroadcastModelProvider);
    final gamesContext = ref.watch(scoreCardGamesContextProvider);
    final explicitEventContext = ref.watch(scoreCardHasEventContextProvider);
    final profileDataSource = ref.watch(
      scoreCardPlayerProfileDataSourceProvider,
    );

    List<GamesTourModel> allGames = [];
    bool isLoadingGames = false;

    // Determine event context from explicit flag or selectedBroadcast
    // - selectedBroadcast != null: definitely has event context (tournament view)
    // - explicitEventContext: set by navigation source (ChessBoard player tap with filtered games)
    final bool hasEventContext =
        selectedBroadcast != null || explicitEventContext;
    final String? contextTourId =
        gamesContext != null && gamesContext.isNotEmpty
            ? gamesContext.first.tourId
            : null;
    final contextEvent = contextTourId?.trim();
    final playerGamebaseId = player.gamebasePlayerId?.trim();
    // Always prefer explicit game context tourId when present.
    // This avoids stale selectedBroadcast races causing false empty state.
    final bool hasExplicitContextEvent =
        hasEventContext && contextEvent != null && contextEvent.isNotEmpty;
    final bool shouldFetchFullTwicEventGames =
        hasExplicitContextEvent &&
        profileDataSource == PlayerProfileDataSource.twic &&
        playerGamebaseId != null &&
        playerGamebaseId.isNotEmpty;
    final bool shouldFetchFullEventGames =
        hasExplicitContextEvent &&
        profileDataSource != PlayerProfileDataSource.twic;

    if (shouldFetchFullTwicEventGames) {
      // TWIC event context: fetch full player event history from backend.
      final request = TwicScorecardEventGamesRequest(
        playerId: playerGamebaseId,
        event: contextEvent,
      );
      final twicEventGamesAsync = ref.watch(
        twicScorecardEventGamesProvider(request),
      );
      allGames = twicEventGamesAsync.when(
        data: (games) => games.isNotEmpty ? games : (gamesContext ?? []),
        loading: () {
          isLoadingGames = true;
          return gamesContext ?? [];
        },
        error: (_, __) => gamesContext ?? [],
      );
    } else if (selectedBroadcast != null) {
      // Tournament broadcast context — always prefer the merged provider so
      // games across pagination-purposed sub-tours (e.g. EICC "Boards 1-66" +
      // "Boards 67-126") are unified. This must win over shouldFetchFullEventGames:
      // a caller may populate gamesContext with a single sub-tour's game, which
      // would otherwise cause gamesTourProvider(subTourId) to miss the player's
      // games in sibling sub-tours.
      final mergedGames = ref.watch(mergedTournamentGamesProvider);

      // If the merged provider is empty, we still want to check if the
      // underlying data is loading to show the skeleton loader
      final gamesTourAsync = ref.watch(gamesTourScreenProvider);

      allGames = gamesTourAsync.when(
        data: (_) => mergedGames,
        loading: () {
          isLoadingGames = true;
          return [];
        },
        error: (_, __) => [],
      );
    } else if (shouldFetchFullEventGames) {
      // Non-broadcast event context (e.g. For You, Countryman) — these flows
      // clear selectedBroadcastModelProvider so we can't rely on the merged
      // tournament provider. Fetch full event games by tourId to include all
      // rounds for the player.
      final fullGamesAsync = ref.watch(gamesTourProvider(contextEvent));
      allGames = fullGamesAsync.when(
        data: (games) {
          final converted = _toGamesTourModels(games);
          return converted.isNotEmpty ? converted : (gamesContext ?? []);
        },
        loading: () {
          isLoadingGames = true;
          return gamesContext ?? [];
        },
        error: (_, __) => gamesContext ?? [],
      );
    } else if (gamesContext != null && gamesContext.isNotEmpty) {
      // Games context provided (from favorites, countrymen, player profile, etc.)
      // Use the provided games list directly
      allGames = gamesContext;
    } else {
      // No context available: fall back to fetching all player games
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

    final playerUtils = ref.read(playerUtilsProvider);

    // Filter games for the selected player
    final filteredGames =
        allGames.where((game) {
          // Use fideId matching when available (more reliable), fall back to name matching
          return playerUtils.isSamePlayerWithFideId(
                game.whitePlayer.name,
                player.name,
                fideId1: game.whitePlayer.fideId,
                fideId2: player.fideId,
              ) ||
              playerUtils.isSamePlayerWithFideId(
                game.blackPlayer.name,
                player.name,
                fideId1: game.blackPlayer.fideId,
                fideId2: player.fideId,
              );
        }).toList();

    // Deduplicate games by gameId, preferring entries with more complete data
    // This handles cases where the same game appears multiple times with different
    // data quality (e.g., one with rating=0 and one with actual rating)
    final gameById = <String, GamesTourModel>{};
    for (final game in filteredGames) {
      final existing = gameById[game.gameId];
      if (existing == null) {
        gameById[game.gameId] = game;
      } else {
        // Prefer the game with more complete opponent data
        final isWhite =
            game.whitePlayer.name == player.name ||
            playerUtils.isSamePlayerWithFideId(
              game.whitePlayer.name,
              player.name,
              fideId1: game.whitePlayer.fideId,
              fideId2: player.fideId,
            );
        final opponent = isWhite ? game.blackPlayer : game.whitePlayer;
        final existingIsWhite =
            existing.whitePlayer.name == player.name ||
            playerUtils.isSamePlayerWithFideId(
              existing.whitePlayer.name,
              player.name,
              fideId1: existing.whitePlayer.fideId,
              fideId2: player.fideId,
            );
        final existingOpponent =
            existingIsWhite ? existing.blackPlayer : existing.whitePlayer;

        // Calculate data quality score: rating > 0, federation not empty, title not empty
        int newScore = 0;
        int existingScore = 0;

        if (opponent.rating > 0) newScore += 2;
        if (opponent.countryCode.isNotEmpty) newScore += 1;
        if (opponent.title.isNotEmpty) newScore += 1;

        if (existingOpponent.rating > 0) existingScore += 2;
        if (existingOpponent.countryCode.isNotEmpty) existingScore += 1;
        if (existingOpponent.title.isNotEmpty) existingScore += 1;

        // Keep the entry with higher quality data
        if (newScore > existingScore) {
          gameById[game.gameId] = game;
        }
      }
    }
    final playerGames = gameById.values.toList();
    // Sort games based on context:
    // - With event context: by round number ascending (Round 1, 2, 3...)
    // - Without event context: by date descending (most recent first)
    if (hasEventContext) {
      // Sort by round number ascending - Round 1 first, then Round 2, etc.
      final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
      playerGames.sort((a, b) {
        final aRound =
            _extractRoundNumber(a.roundSlug) ??
            _extractRoundNumber(a.roundId) ??
            9999;
        final bRound =
            _extractRoundNumber(b.roundSlug) ??
            _extractRoundNumber(b.roundId) ??
            9999;
        if (aRound != bRound) {
          return aRound.compareTo(bRound);
        }
        // If same round, sort by board number (lower board = higher importance)
        final aBoard = a.boardNr ?? 9999;
        final bBoard = b.boardNr ?? 9999;
        if (aBoard != bBoard) {
          return aBoard.compareTo(bBoard);
        }

        final aTime = a.lastMoveTime ?? epochFallback;
        final bTime = b.lastMoveTime ?? epochFallback;
        return aTime.compareTo(bTime);
      });
    } else {
      // Sort by date descending - most recent games first
      final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
      playerGames.sort((a, b) {
        final aTime = a.lastMoveTime ?? epochFallback;
        final bTime = b.lastMoveTime ?? epochFallback;
        return bTime.compareTo(aTime); // Descending order
      });
    }

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

    // Calculate performance rating and total rating diff only when we have event context
    // Without event context (e.g., from Favorites tab), we can't calculate meaningful performance
    int? performanceRating;
    double? eventScore;
    int? eventTotalGames;
    double totalRatingDiff = 0.0; // Sum of rating changes from all games

    if (hasEventContext) {
      // Calculate performance rating using standard chess formula:
      // Performance = Average Opponent Rating + DP (delta points based on score percentage)
      double totalOpponentRating = 0.0;
      double playerScore = 0.0;
      int validGamesCount = 0;

      for (final game in playerGames) {
        // Skip ongoing/unknown games for performance calculation
        if (game.gameStatus == GameStatus.ongoing ||
            game.gameStatus == GameStatus.unknown) {
          continue;
        }

        // Use fuzzy/fide-aware matching: some broadcasts emit the same
        // player with different name spellings across rounds
        // (e.g. "IM Sargsyan, Anna" on one board, "Sargsyan, Anna" on
        // another). Exact equality would mis-classify such rows.
        final isWhite = playerUtils.isSamePlayerWithFideId(
          game.whitePlayer.name,
          player.name,
          fideId1: game.whitePlayer.fideId,
          fideId2: player.fideId,
        );
        final opponent = isWhite ? game.blackPlayer : game.whitePlayer;
        final playerRating = _getPlayerRatingForSide(game, isWhite);
        final opponentRating = _getPlayerRatingForSide(game, !isWhite);

        if (opponentRating > 0) {
          totalOpponentRating += opponentRating;
          validGamesCount++;

          // Calculate player score for this game
          switch (game.gameStatus) {
            case GameStatus.whiteWins:
              playerScore += isWhite ? 1.0 : 0.0;
              break;
            case GameStatus.blackWins:
              playerScore += isWhite ? 0.0 : 1.0;
              break;
            case GameStatus.draw:
              playerScore += 0.5;
              break;
            default:
              break;
          }

          // Calculate rating change for this game and add to total.
          // Prefer FIDE per-time-control rating + K from chess_players over
          // the per-game PGN rating; PGN values often reflect a different
          // time control than the event (e.g. standard rating in a blitz PGN).
          if (playerRating > 0) {
            final tc = game.timeControl;
            final fideK = tc != null ? playerRatings?.getK(tc) : null;
            final fidePlayerRating = tc != null
                ? playerRatings?.getRating(tc)?.toDouble()
                : null;
            final ratingChange = _calculateFideRatingChange(
              playerRating,
              opponentRating,
              game.gameStatus,
              isWhite,
              game,
              fideK: fideK,
              playerRatingOverride: fidePlayerRating,
            );
            totalRatingDiff += ratingChange;
          }
        }
      }

      // Calculate performance rating
      if (validGamesCount > 0) {
        final avgOpponentRating = totalOpponentRating / validGamesCount;
        final scorePercentage = playerScore / validGamesCount;
        double dp;
        if (scorePercentage >= 1.0) {
          dp = 800; // Perfect score cap
        } else if (scorePercentage <= 0.0) {
          dp = -800; // Zero score cap
        } else {
          dp = 400 * (2 * scorePercentage - 1);
        }
        performanceRating = (avgOpponentRating + dp).round();
        eventScore = playerScore;
        eventTotalGames = validGamesCount;
      } else {
        // No valid games in event - use player's current rating
        performanceRating = player.score.round();
        final displayScore = player.matchScore ?? "0 / 0";
        final parsedScore = _parseScoreValues(displayScore);
        eventScore = parsedScore.$1;
        eventTotalGames = parsedScore.$2;
      }
    }
    // When !hasEventContext: performanceRating, eventScore, eventTotalGames remain null
    final photoFuture = FidePhotoService.getPhotoUrlOrNull(
      player.fideId?.toString(),
    );

    // Consistent horizontal padding - matches chessboard screen patterns
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 24.sp,
    );
    // Gap between avatar and rating boxes
    final avatarRatingGap = ResponsiveHelper.adaptive(
      phone: 10.w,
      tablet: 16.sp,
    );
    // Gap between rating boxes
    final ratingBoxGap = ResponsiveHelper.adaptive(phone: 6.w, tablet: 10.sp);

    return Scaffold(
      key: e2eKey(E2eIds.scorecardRoot),
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: CustomScrollView(
              slivers: [
                const _SliverScoreboardAppBar(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 10.h),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PlayerAvatarTile(
                              photoFuture: photoFuture,
                              initials: initials,
                              title: player.title,
                              fideId: player.fideId?.toString(),
                            ),
                            SizedBox(width: avatarRatingGap),
                            Expanded(
                              child: IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _RatingDisplay(
                                        label: 'Classical',
                                        playerName: player.name,
                                        fideId: player.fideId,
                                        timeControlType: "standard",
                                        assetPath: PngAsset.classicalIcon,
                                        onTap:
                                            () => _navigateToPlayerProfile(
                                              context,
                                              ref,
                                              player,
                                            ),
                                      ),
                                    ),
                                    SizedBox(width: ratingBoxGap),
                                    Expanded(
                                      child: _RatingDisplay(
                                        label: 'Rapid',
                                        playerName: player.name,
                                        fideId: player.fideId,
                                        timeControlType: "rapid",
                                        assetPath: PngAsset.rapidIcon,
                                        onTap:
                                            () => _navigateToPlayerProfile(
                                              context,
                                              ref,
                                              player,
                                            ),
                                      ),
                                    ),
                                    SizedBox(width: ratingBoxGap),
                                    Expanded(
                                      child: _RatingDisplay(
                                        label: 'Blitz',
                                        playerName: player.name,
                                        fideId: player.fideId,
                                        timeControlType: "blitz",
                                        assetPath: PngAsset.blitzIcon,
                                        onTap:
                                            () => _navigateToPlayerProfile(
                                              context,
                                              ref,
                                              player,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),
                        GestureDetector(
                          onTap:
                              () => _navigateToPlayerProfile(
                                context,
                                ref,
                                player,
                              ),
                          child: PerformanceStatsRow(
                            performanceRating: performanceRating,
                            score: eventScore,
                            totalGames: eventTotalGames,
                            // Prefer server-provided ratingDiff (accounts for FIDE K-factor history);
                            // fall back to locally calculated sum when server value is unavailable.
                            ratingDiff:
                                hasEventContext
                                    ? (player.scoreChange != 0
                                        ? player.scoreChange
                                        : (totalRatingDiff != 0.0
                                            ? totalRatingDiff.round()
                                            : null))
                                    : null,
                          ),
                        ),
                        SizedBox(height: 10.h),
                        _ProfileNavigationButton(
                          onTap:
                              () => _navigateToPlayerProfile(
                                context,
                                ref,
                                player,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: SizedBox(height: 12.h)),
                if (isLoadingGames)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (playerGames.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 40.ic,
                            color: context.colors.textPrimary.withValues(alpha: 0.5),
                          ),
                          SizedBox(height: 12.h),
                          Text(
                            hasEventContext
                                ? 'No games in this tournament'
                                : 'No games available',
                            style: AppTypography.textSmMedium.copyWith(
                              color: context.colors.textPrimary.withValues(alpha: 0.7),
                            ),
                          ),
                          SizedBox(height: 6.h),
                          Text(
                            hasEventContext
                                ? 'This player has not played in this tournament yet'
                                : 'Games will appear once they are played',
                            textAlign: TextAlign.center,
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textPrimary.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final game = playerGames[index];
                      // Fide-first, fuzzy-name-fallback match — see note in
                      // the performance loop above.
                      final isWhite = playerUtils.isSamePlayerWithFideId(
                        game.whitePlayer.name,
                        player.name,
                        fideId1: game.whitePlayer.fideId,
                        fideId2: player.fideId,
                      );
                      final opponent =
                          isWhite ? game.blackPlayer : game.whitePlayer;
                      final result = _getPlayerResult(game, isWhite);

                      final playerRating = _getPlayerRatingForSide(
                        game,
                        isWhite,
                      );
                      final opponentRating = _getPlayerRatingForSide(
                        game,
                        !isWhite,
                      );

                      double ratingChange = 0.0;
                      if (playerRating > 0 && opponentRating > 0) {
                        final tc = game.timeControl;
                        final fideK =
                            tc != null ? playerRatings?.getK(tc) : null;
                        final fidePlayerRating = tc != null
                            ? playerRatings?.getRating(tc)?.toDouble()
                            : null;
                        ratingChange = _calculateFideRatingChange(
                          playerRating,
                          opponentRating,
                          game.gameStatus,
                          isWhite,
                          game,
                          fideK: fideK,
                          playerRatingOverride: fidePlayerRating,
                        );
                      }

                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: ScoreboardCardWidget(
                          roundLabel:
                              hasEventContext ? _buildRoundLabel(game) : null,
                          countryCode: opponent.countryCode,
                          title: opponent.title,
                          name: opponent.name,
                          score: opponent.rating,
                          scoreChange:
                              ratingChange != 0.0 ? ratingChange : null,
                          matchScore: result,
                          isWhite: isWhite,
                          index: index,
                          isFirst: index == 0,
                          isLast: index == playerGames.length - 1,
                          onTap: () {
                            if (ref.read(selectedBroadcastModelProvider) ==
                                null) {
                              ref
                                  .read(chessboardViewFromProviderNew.notifier)
                                  .state = ChessboardView.favScorecard;
                            } else {
                              ref
                                  .read(chessboardViewFromProviderNew.notifier)
                                  .state = ChessboardView.tour;
                            }

                            // Pass playerGames (filtered for this player) instead of allGames
                            // so swiping in chessboard only shows this player's games
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => ChessBoardScreenNew(
                                      games: playerGames,
                                      currentIndex: index,
                                      playerProfileDataSource:
                                          profileDataSource,
                                    ),
                              ),
                            );
                          },
                        ),
                      );
                    }, childCount: playerGames.length),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (double?, int?) _parseScoreValues(String scoreText) {
    final match = RegExp(
      r'([0-9]+(?:\.[0-9]+)?)\s*/\s*([0-9]+)',
    ).firstMatch(scoreText);
    if (match != null) {
      final score = double.tryParse(match.group(1) ?? '');
      final totalGames = int.tryParse(match.group(2) ?? '');
      return (score, totalGames);
    }
    return (null, null);
  }

  String _getPlayerResult(GamesTourModel game, bool isWhite) {
    switch (game.gameStatus) {
      case GameStatus.whiteWins:
        return isWhite ? '1' : '0';
      case GameStatus.blackWins:
        return isWhite ? '0' : '1';
      case GameStatus.draw:
        return '½';
      case GameStatus.ongoing:
        return '–';
      case GameStatus.unknown:
        return '-';
    }
  }

  String? _buildRoundLabel(GamesTourModel game) {
    final slugLabel = _parseRoundLabel(game.roundSlug);
    if (slugLabel != null) return slugLabel;

    final roundIdLabel = _parseRoundLabel(game.roundId);
    return roundIdLabel;
  }

  String? _parseRoundLabel(String? source) {
    if (source == null || source.isEmpty) return null;

    final patterns = [
      RegExp(r'round[-\s]?(\d+)', caseSensitive: false),
      RegExp(r'rapid[-\s]?(\d+)', caseSensitive: false),
      RegExp(r'blitz[-\s]?(\d+)', caseSensitive: false),
      RegExp(r'^(\d+)$'),
      RegExp(r'r(\d+)', caseSensitive: false),
      RegExp(r'game[-\s]?(\d+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(source);
      if (match != null && match.groupCount >= 1) {
        final number = match.group(1);
        if (number != null && number.isNotEmpty) {
          return '$number.';
        }
      }
    }

    return null;
  }

  void _navigateToPlayerProfile(
    BuildContext context,
    WidgetRef ref,
    PlayerStandingModel player,
  ) {
    final source = ref.read(scoreCardPlayerProfileDataSourceProvider);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => PlayerProfileScreen(
              fideId: player.fideId,
              playerName: player.name,
              title: player.title,
              federation: player.countryCode,
              rating: player.score.round(),
              dataSource: source,
              gamebasePlayerId: player.gamebasePlayerId,
            ),
      ),
    );
  }

  /// Extract round number from a round slug or round id string
  /// e.g., "round-2" -> 2, "round7" -> 7, "r3" -> 3
  int? _extractRoundNumber(String? source) {
    if (source == null || source.isEmpty) return null;

    final patterns = [
      RegExp(r'round[-\s]?(\d+)', caseSensitive: false),
      RegExp(r'rapid[-\s]?(\d+)', caseSensitive: false),
      RegExp(r'blitz[-\s]?(\d+)', caseSensitive: false),
      RegExp(r'^(\d+)$'),
      RegExp(r'r(\d+)', caseSensitive: false),
      RegExp(r'game[-\s]?(\d+)', caseSensitive: false),
      // Handle tiebreak, losers rounds with game numbers
      RegExp(r'tiebreak[-\s]?(\d+)', caseSensitive: false),
      RegExp(r'losers[-\s]?r?(\d+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(source);
      if (match != null && match.groupCount >= 1) {
        final number = match.group(1);
        if (number != null && number.isNotEmpty) {
          return int.tryParse(number);
        }
      }
    }

    return null;
  }
}

/// A refined, Motor-animated button for navigating to the player profile screen.
/// Uses spring-physics press feedback for a tactile, premium feel.
class _ProfileNavigationButton extends StatefulWidget {
  const _ProfileNavigationButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ProfileNavigationButton> createState() =>
      _ProfileNavigationButtonState();
}

class _ProfileNavigationButtonState extends State<_ProfileNavigationButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _pressed ? 1.0 : 0.0,
        builder: (context, pressProgress, _) {
          return Transform.scale(
            scale: 1.0 - 0.03 * pressProgress,
            child: Container(
              height: 40.h,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(
                  alpha: 0.05 + 0.04 * pressProgress,
                ),
                borderRadius: BorderRadius.circular(10.br),
                border: Border.all(
                  color: context.colors.textPrimary.withValues(
                    alpha: 0.10 + 0.06 * pressProgress,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 16.ic,
                    color: context.colors.textPrimary.withValues(alpha: 0.75),
                  ),
                  SizedBox(width: 7.w),
                  Text(
                    'Open Player Profile',
                    style: AppTypography.textSmBold.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlayerHeaderRow extends StatelessWidget {
  final String countryCode;
  final String rawCountryCode;
  final String? title;
  final String name;
  final bool hasTournamentContext;

  const _PlayerHeaderRow({
    required this.countryCode,
    required this.rawCountryCode,
    required this.title,
    required this.name,
    required this.hasTournamentContext,
  });

  @override
  Widget build(BuildContext context) {
    final hasFederation =
        rawCountryCode.trim().isNotEmpty || countryCode.trim().isNotEmpty;
    final titleText = (title ?? '').trim();

    return Row(
      children: [
        if (hasFederation)
          FederationFlag(
            federation:
                rawCountryCode.trim().isNotEmpty ? rawCountryCode : countryCode,
            height: 16.h,
            width: 22.w,
            borderRadius: BorderRadius.circular(2.br),
          )
        else
          SizedBox(width: 22.w, height: 16.h),
        SizedBox(width: 8.w),
        Expanded(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                if (titleText.isNotEmpty)
                  TextSpan(
                    text: '$titleText ',
                    style: AppTypography.textMdBold.copyWith(
                      color: kLightYellowColor,
                    ),
                  ),
                TextSpan(
                  text: name,
                  style: AppTypography.textMdBold.copyWith(color: context.colors.textPrimary),
                ),
              ],
            ),
          ),
        ),
        if (hasTournamentContext)
          Icon(Icons.keyboard_arrow_down, color: context.colors.textPrimaryMuted, size: 20.ic),
      ],
    );
  }
}

class _PlayerAvatarTile extends StatelessWidget {
  final Future<String?>? photoFuture;
  final String initials;
  final String? title;
  final String? fideId;

  const _PlayerAvatarTile({
    required this.photoFuture,
    required this.initials,
    required this.title,
    this.fideId,
  });

  @override
  Widget build(BuildContext context) {
    // Bigger avatar for tablets
    final avatarSize = ResponsiveHelper.isTablet ? 120.sp : 90.w;
    final heroTag = 'player_avatar_scorecard_${fideId ?? initials}';

    return FutureBuilder<String?>(
      future: photoFuture,
      builder: (context, snapshot) {
        final photoUrl = snapshot.data;

        return GestureDetector(
          onTap: () {
            showPlayerAvatarFullscreen(
              context: context,
              photoUrl: photoUrl,
              initials: initials,
              heroTag: heroTag,
              title: title,
            );
          },
          child: Heroine(
            tag: heroTag,
            motion: const CupertinoMotion.smooth(),
            flightShuttleBuilder: const FadeShuttleBuilder(),
            child: PlayerInitialsAvatar(
              photoUrl: photoUrl,
              initials: initials,
              size: avatarSize,
              borderRadius: 12.br,
              title: title,
            ),
          ),
        );
      },
    );
  }
}

class _SliverScoreboardAppBar extends ConsumerStatefulWidget {
  const _SliverScoreboardAppBar();

  @override
  ConsumerState<_SliverScoreboardAppBar> createState() =>
      _SliverScoreboardAppBarState();
}

class _SliverScoreboardAppBarState
    extends ConsumerState<_SliverScoreboardAppBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _toggleFavorite() async {
    if (ref.read(chessboardViewFromProviderNew) != ChessboardView.forYou) {
      return;
    }

    final allowed = await requireFullAuthGuard(context);
    if (!allowed) return;

    final selectedPlayer = ref.read(selectedPlayerProvider);

    if (selectedPlayer != null) {
      try {
        final player = await ref.read(
          backfilledStandingPlayerProvider(selectedPlayer).future,
        );

        // Check if adding (not removing) and enforce limit
        final currentlyFavorited = ref
            .read(favoritePlayersProviderNew)
            .maybeWhen(
              data:
                  (players) =>
                      players.any((p) => p.fideId == player.fideId?.toString()),
              orElse: () => false,
            );
        if (!currentlyFavorited) {
          if (!mounted) return;
          final canAdd = await canAddMoreFavorites(context, ref);
          if (!canAdd) return;
        }

        final isNowFavorite = await ref
            .read(favoritePlayersProviderNew.notifier)
            .toggleFavorite(
              fideId: player.fideId?.toString(),
              playerName: player.name,
              countryCode: player.countryCode,
              rating: player.score,
              title: player.title,
            );
        if (isNowFavorite) {
          _animationController.forward().then(
            (_) => _animationController.reverse(),
          );
        }
      } on FavoriteLimitExceededException {
        if (mounted) {
          await showPremiumPaywallSheet(context: context);
        }
      } catch (e) {
        debugPrint('Error toggling favorite: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update favorite. Please try again.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _showPlayerSelectionSheet(BuildContext context) {
    final playerTourAsync = ref.read(playerTourScreenProvider);
    final players = playerTourAsync.valueOrNull ?? [];

    if (players.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
        maxWidth: ResponsiveHelper.bottomSheetMaxWidth,
      ),
      builder: (context) => _PlayerSelectionSheet(players: players),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlayer = ref.watch(selectedPlayerProvider);
    if (selectedPlayer == null) return const SliverAppBar();
    final backfilledPlayerAsync = ref.watch(
      backfilledStandingPlayerProvider(selectedPlayer),
    );
    final player = backfilledPlayerAsync.valueOrNull ?? selectedPlayer;

    final selectedBroadcast = ref.watch(selectedBroadcastModelProvider);
    final hasTournamentContext = selectedBroadcast != null;
    final isForYouView =
        ref.watch(chessboardViewFromProviderNew) == ChessboardView.forYou;

    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(player.countryCode);

    bool isFavorite = false;
    if (isForYouView) {
      final favoritesAsync = ref.watch(favoritePlayersProviderNew);
      isFavorite = favoritesAsync.maybeWhen(
        data:
            (players) =>
                players.any((p) => p.fideId == player.fideId?.toString()),
        orElse: () => false,
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
      );
    }

    final headerRow = _PlayerHeaderRow(
      countryCode: validCountryCode,
      rawCountryCode: player.countryCode,
      title: player.title,
      name: player.name,
      hasTournamentContext: hasTournamentContext,
    );

    return SliverAppBar(
      pinned: true,
      backgroundColor: context.colors.background,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_outlined,
          color: context.colors.textPrimary,
          size: 22.ic,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title:
          hasTournamentContext
              ? GestureDetector(
                onTap: () => _showPlayerSelectionSheet(context),
                behavior: HitTestBehavior.opaque,
                child: headerRow,
              )
              : headerRow,
      actions: [
        if (isForYouView)
          InkWell(
            onTap: _toggleFavorite,
            child: Container(
              width: 48.w,
              padding: EdgeInsets.all(8.sp),
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: SvgWidget(
                  isFavorite
                      ? SvgAsset.favouriteRedIcon
                      : SvgAsset.favouriteIcon2,
                  semanticsLabel: 'Favorite Icon',
                  height: 20.h,
                  width: 20.w,
                ),
              ),
            ),
          ),
        SizedBox(width: 8.w),
      ],
    );
  }
}

/// Simplified rating display that uses a cached provider to fetch all ratings
/// at once, avoiding 3 separate API calls for the same player.
class _RatingDisplay extends ConsumerWidget {
  final String label;
  final String playerName;
  final int? fideId;
  final String timeControlType;
  final String assetPath;
  final VoidCallback? onTap;

  const _RatingDisplay({
    required this.label,
    required this.playerName,
    this.fideId,
    required this.timeControlType,
    required this.assetPath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use allRatingsProvider which fetches all ratings at once and caches them.
    // This is efficient because the same request key (fideId + playerName) is
    // shared by all 3 rating widgets, so only ONE API call is made.
    final ratingsRequest = AllRatingsRequest(
      fideId: fideId,
      playerName: playerName,
    );
    final ratingsAsync = ref.watch(allRatingsProvider(ratingsRequest));

    // Tablet needs to match avatar height (120.sp), mobile stays at 90.w
    final containerHeight = ResponsiveHelper.isTablet ? 120.sp : 90.w;
    // Tablet-specific sizing for visual balance
    final iconSize = ResponsiveHelper.isTablet ? 22.sp : 18.w;
    final labelFontSize = ResponsiveHelper.isTablet ? 12.sp : 10.sp;
    final elementSpacing = ResponsiveHelper.isTablet ? 6.h : 4.h;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.isTablet ? 6.sp : 3.sp,
          vertical: ResponsiveHelper.isTablet ? 12.sp : 8.sp,
        ),
        width: double.infinity,
        height: containerHeight,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(assetPath, width: iconSize, height: iconSize),
            SizedBox(height: elementSpacing),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.textPrimaryMuted,
                fontSize: labelFontSize,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: elementSpacing),
            ratingsAsync.when(
              data: (ratings) {
                final rating = ratings.getRating(timeControlType);
                return Text(
                  rating?.toString() ?? '-',
                  style:
                      ResponsiveHelper.isTablet
                          ? AppTypography.textLgBold.copyWith(
                            color: context.colors.textPrimary,
                          )
                          : AppTypography.textMdBold.copyWith(
                            color: context.colors.textPrimary,
                          ),
                );
              },
              loading:
                  () => Skeletonizer(
                    enabled: true,
                    ignoreContainers: true,
                    effect: const ShimmerEffect(
                      baseColor: Color(0xFF2A2A2A),
                      highlightColor: Color(0xFF3A3A3A),
                    ),
                    child: Text(
                      '2400',
                      style:
                          ResponsiveHelper.isTablet
                              ? AppTypography.textLgBold.copyWith(
                                color: context.colors.textPrimary,
                              )
                              : AppTypography.textMdBold.copyWith(
                                color: context.colors.textPrimary,
                              ),
                    ),
                  ),
              error:
                  (_, __) => Text(
                    '-',
                    style:
                        ResponsiveHelper.isTablet
                            ? AppTypography.textLgBold.copyWith(
                              color: context.colors.textPrimary,
                            )
                            : AppTypography.textMdBold.copyWith(
                              color: context.colors.textPrimary,
                            ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for selecting a player from the tournament
class _PlayerSelectionSheet extends ConsumerWidget {
  final List<PlayerStandingModel> players;

  const _PlayerSelectionSheet({required this.players});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPlayer = ref.watch(selectedPlayerProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle bar
        Container(
          margin: EdgeInsets.only(top: 10.h, bottom: 6.h),
          width: 36.w,
          height: 3.h,
          decoration: BoxDecoration(
            color: context.colors.textPrimary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2.br),
          ),
        ),
        // Title
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 10.h),
          child: Row(
            children: [
              Text(
                'Select Player',
                style: AppTypography.textMdBold.copyWith(color: context.colors.textPrimary),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, color: context.colors.textPrimaryMuted, size: 20.ic),
              ),
            ],
          ),
        ),
        Divider(color: kDarkGreyColor, height: 1.h),
        // Player list
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.symmetric(vertical: 6.h),
            itemCount: players.length,
            separatorBuilder:
                (_, __) => Divider(
                  color: kDarkGreyColor,
                  height: 1.h,
                  indent: 16.w,
                  endIndent: 16.w,
                ),
            itemBuilder: (context, index) {
              final player = players[index];
              final isSelected = selectedPlayer?.name == player.name;
              final validCountryCode = ref
                  .read(locationServiceProvider)
                  .getValidCountryCode(player.countryCode);

              return InkWell(
                onTap: () {
                  ref.read(selectedPlayerProvider.notifier).state = player;
                  Navigator.pop(context);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.sp,
                    vertical: 10.h,
                  ),
                  color: isSelected ? context.colors.surface : Colors.transparent,
                  child: Row(
                    children: [
                      // Country flag
                      if (player.countryCode.trim().isNotEmpty ||
                          validCountryCode.isNotEmpty)
                        FederationFlag(
                          federation:
                              player.countryCode.trim().isNotEmpty
                                  ? player.countryCode
                                  : validCountryCode,
                          height: 14.h,
                          width: 20.w,
                          borderRadius: BorderRadius.circular(2.br),
                        )
                      else
                        SizedBox(width: 20.w),
                      SizedBox(width: 10.w),
                      // Title and name
                      Expanded(
                        child: Text(
                          '${player.title != null && player.title!.isNotEmpty ? '${player.title} ' : ''}${player.name}',
                          style: AppTypography.textSmMedium.copyWith(
                            color: isSelected ? kGreenColor : context.colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Rating
                      Text(
                        player.score.toStringAsFixed(0),
                        style: AppTypography.textXsMedium.copyWith(
                          color: context.colors.textPrimaryMuted,
                        ),
                      ),
                      // Selected indicator
                      if (isSelected) ...[
                        SizedBox(width: 6.w),
                        Icon(Icons.check, color: kGreenColor, size: 18.ic),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
