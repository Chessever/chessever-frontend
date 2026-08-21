import 'dart:io' as io;
import 'dart:math' as math;
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/player_backfill_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:chessever2/widgets/fullscreen_image_viewer.dart';
import 'package:chessever2/screens/standings/providers/player_ratings_provider.dart'
    show AllRatingsRequest, allRatingsProvider;
import 'package:chessever2/screens/standings/providers/twic_scorecard_event_games_provider.dart';
import 'package:chessever2/screens/standings/providers/player_utils_provider.dart';
import 'package:chessever2/screens/standings/utils/fide_rating_change.dart';
import 'package:chessever2/screens/standings/utils/player_event_share_utils.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/screens/standings/widgets/player_event_share_image_card.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart'
    show tourDetailScreenProvider;
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/player_profile/widgets/performance_stats_row.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:heroine/heroine.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/favorite_limit_guard.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/widgets/screenshot_share_nudge.dart';
import 'package:chessever2/widgets/player_name_share_target.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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

enum ScoreCardSwipeDirection { previous, next }

/// The score card always hands the board an already-filtered player-game list.
/// Event context still controls player-detail behavior, while the independent
/// list policy prevents background hydration from replacing that player list
/// with every board from the tapped tournament.
({ChessboardView viewSource, BoardNavigationListPolicy listPolicy})
scoreCardGameNavigationContext({required bool hasEventContext}) => (
  viewSource:
      hasEventContext ? ChessboardView.tour : ChessboardView.favScorecard,
  listPolicy: BoardNavigationListPolicy.preserve,
);

bool _isSameStandingPlayer(PlayerStandingModel a, PlayerStandingModel b) {
  if (a.fideId != null && b.fideId != null) {
    return a.fideId == b.fideId;
  }
  if (a.gamebasePlayerId != null &&
      a.gamebasePlayerId!.isNotEmpty &&
      b.gamebasePlayerId != null &&
      b.gamebasePlayerId!.isNotEmpty) {
    return a.gamebasePlayerId == b.gamebasePlayerId;
  }
  return a.name == b.name;
}

int findScoreCardPlayerIndex(
  List<PlayerStandingModel> players,
  PlayerStandingModel selectedPlayer,
) {
  return players.indexWhere(
    (player) => _isSameStandingPlayer(player, selectedPlayer),
  );
}

/// Resolves the standings entry for a tapped opponent so the opened card
/// carries the event's score, rating change and rank instead of only the row's
/// PGN data. Falls back to a model built from the game row when the opponent is
/// not part of the current standings (TWIC events, partially hydrated lists).
PlayerStandingModel scoreCardOpponentTarget({
  required List<PlayerStandingModel> players,
  required String name,
  required String countryCode,
  required String? title,
  required int rating,
  int? fideId,
  String? gamebasePlayerId,
  String? team,
}) {
  final fallback = PlayerStandingModel(
    countryCode: countryCode,
    title: title == null || title.isEmpty ? null : title,
    name: name,
    score: rating,
    scoreChange: 0,
    matchScore: null,
    fideId: fideId,
    gamebasePlayerId: gamebasePlayerId,
    team: team,
  );
  final matchingIndex = findScoreCardPlayerIndex(players, fallback);
  if (matchingIndex >= 0) return players[matchingIndex];

  final normalizedName = name.trim().toLowerCase();
  for (final player in players) {
    if (player.name.trim().toLowerCase() == normalizedName) return player;
  }
  return fallback;
}

PlayerStandingModel? adjacentScoreCardPlayerForSwipe({
  required List<PlayerStandingModel> players,
  required PlayerStandingModel selectedPlayer,
  required ScoreCardSwipeDirection direction,
}) {
  if (players.length < 2) return null;
  final currentIndex = findScoreCardPlayerIndex(players, selectedPlayer);
  if (currentIndex < 0) return null;

  final targetIndex = switch (direction) {
    ScoreCardSwipeDirection.previous => currentIndex - 1,
    ScoreCardSwipeDirection.next => currentIndex + 1,
  };
  if (targetIndex < 0 || targetIndex >= players.length) return null;
  return players[targetIndex];
}

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
  } catch (e) {
    debugPrint('Error: $e');
    return [];
  }
});

/// Turns a Lichess-style event slug (e.g. `45th-chess-olympiad-2024--open`)
/// into a readable title (`45th Chess Olympiad 2024 Open`). Used as the last
/// fallback for the shared event name when no broadcast/tour name is in hand,
/// so the share card shows the real event instead of a generic placeholder.
String? _humanizeEventSlug(String? slug) {
  if (slug == null) return null;
  final words =
      slug
          .split(RegExp(r'[-_]+'))
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1))
          .toList();
  final title = words.join(' ').trim();
  return title.isEmpty ? null : title;
}

/// PageView host for the scorecard. Renders one [_ScoreCardPage] per player in
/// the current tournament standings so horizontal swipes feel continuous —
/// finger-tracked, rubber-banded and snapping — exactly like the chessboard's
/// game PageView, instead of the old discrete "flip to next player" gesture.
///
/// Falls back to a single static page when there is no player list or fewer
/// than two players (nothing to page through).
class ScoreCardScreen extends ConsumerStatefulWidget {
  const ScoreCardScreen({super.key});

  @override
  ConsumerState<ScoreCardScreen> createState() => _ScoreCardScreenState();
}

class _ScoreCardScreenState extends ConsumerState<ScoreCardScreen> {
  PageController? _pageController;
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlayer = ref.watch(selectedPlayerProvider);

    if (selectedPlayer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final players = ref.watch(playerTourScreenProvider).valueOrNull;

    // No pageable list (e.g. favorites/countrymen single-player context) or a
    // player that isn't part of the current standings → static single card.
    final selectedIndex =
        players == null
            ? -1
            : findScoreCardPlayerIndex(players, selectedPlayer);
    if (players == null || players.length < 2 || selectedIndex < 0) {
      return _ScoreCardPage(player: selectedPlayer);
    }

    // Lazily create the controller once the pageable list is known.
    _pageController ??= PageController(initialPage: selectedIndex);
    if (_currentPage >= players.length) {
      _currentPage = selectedIndex;
    }

    // External selection changes (player-picker sheet, favorite flows) update
    // selectedPlayerProvider directly — animate the page to match so the two
    // stay in sync. Our own onPageChanged sets the same index, so the guard
    // below makes that a no-op (no animation fight).
    ref.listen<PlayerStandingModel?>(selectedPlayerProvider, (_, next) {
      if (next == null) return;
      final idx = findScoreCardPlayerIndex(players, next);
      if (idx < 0 || idx == _currentPage) return;
      final controller = _pageController;
      if (controller == null || !controller.hasClients) return;
      _currentPage = idx;
      controller.animateToPage(
        idx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });

    return PageView.builder(
      controller: _pageController,
      itemCount: players.length,
      onPageChanged: (page) {
        _currentPage = page;
        // Sync the shared selection so the app bar, sheet and share flows all
        // reflect the swiped-to player.
        ref.read(selectedPlayerProvider.notifier).state = players[page];
      },
      itemBuilder: (context, index) {
        return _ScoreCardPage(
          player: players[index],
          isActive: index == _currentPage,
        );
      },
    );
  }
}

/// A single player's scorecard page. Rendered directly (single-player contexts)
/// or as one page inside [ScoreCardScreen]'s PageView.
class _ScoreCardPage extends ConsumerWidget {
  const _ScoreCardPage({
    required this.player,
    this.isActive = true,
    this.isSheet = false,
    this.onOpponentSelected,
    this.scrollController,
  });

  /// The standings player this page renders. In the PageView this is the
  /// per-index player; swipe navigation is driven by the parent PageView, not
  /// by this widget.
  final PlayerStandingModel player;

  /// Whether this is the currently-visible page. Off-screen neighbour pages
  /// (which the PageView pre-builds) must not arm the screenshot-share nudge,
  /// or a single screenshot would trigger multiple nudges.
  final bool isActive;

  /// Whether this page is rendered inside [showOpponentScoreCardSheet]. The
  /// sheet owns its own dismissal affordance, so the app bar closes instead of
  /// popping back.
  final bool isSheet;

  /// Called when an opponent's name is tapped. Null on the root screen, where
  /// the tap opens the opponent's card in a bottom sheet; the sheet passes a
  /// handler so a nested tap swaps its card in place instead of stacking.
  final ValueChanged<PlayerStandingModel>? onOpponentSelected;

  /// Controller for this page's vertical scroll view. The opponent sheet
  /// passes the controller [DraggableScrollableSheet] hands out so sheet and
  /// list share one gesture chain: with the list at the top a downward drag
  /// pulls the sheet down (and dismisses it), anywhere else it scrolls.
  final ScrollController? scrollController;

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
    final playerTitle =
        isWhite ? game.whitePlayer.title : game.blackPlayer.title;
    final fallbackKFactor = scoreCardFallbackKFactorForSelectedRating(
      effectivePlayerRating,
      title: playerTitle,
      timeControl: game.timeControl,
    );

    return calculateFideRatingChange(
      playerRating: effectivePlayerRating,
      opponentRating: opponentRating,
      actualScore: actualScore,
      kFactor: fideK ?? fallbackKFactor,
    );
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
    final selectedPlayer = this.player;

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
            final fidePlayerRating =
                tc != null ? playerRatings?.getRating(tc)?.toDouble() : null;
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
    // contextEvent is a Lichess tour ID (e.g. "GtTXd69H"), not a human name.
    // Prefer the broadcast name, then the tour's aboutTourModel name, then a
    // readable title derived from the player's games' tour slug — so the share
    // card shows the real event name instead of a generic placeholder.
    final aboutModel =
        ref.read(tourDetailScreenProvider).valueOrNull?.aboutTourModel;
    final eventName =
        selectedBroadcast?.name ??
        aboutModel?.name ??
        _humanizeEventSlug(
          playerGames.isNotEmpty ? playerGames.first.tourSlug : null,
        );
    // Scorecard share link encodes this player so opening it pushes the event
    // and then this player's scorecard (and renders the player card on the web).
    final eventShareId =
        aboutModel?.groupBroadcastId?.isNotEmpty == true
            ? aboutModel!.groupBroadcastId!
            : (aboutModel?.id ?? selectedBroadcast?.id);
    final playerShareUrl = buildPlayerEventShareUrl(
      hasEventContext: hasEventContext,
      canonicalEventId: eventShareId,
      eventName: eventName ?? selectedBroadcast?.name,
      tourId: aboutModel?.id,
      tourSlug: aboutModel?.slug,
      contextTourId: contextEvent,
      contextTourSlug:
          playerGames.isNotEmpty ? playerGames.first.tourSlug : null,
      playerFideId: player.fideId,
    );
    final shareRows = _buildPlayerEventShareRows(
      playerGames: playerGames,
      player: player,
      playerUtils: playerUtils,
      playerRatings: playerRatings,
      hasEventContext: hasEventContext,
    );
    Future<void> sharePlayerProfile() => _sharePlayerEventProfile(
      context: context,
      player: player,
      photoFuture: photoFuture,
      initials: initials,
      eventName: eventName,
      performanceRating: performanceRating,
      eventScore: eventScore,
      eventTotalGames: eventTotalGames,
      ratingDiff:
          hasEventContext
              ? (player.scoreChange != 0
                  ? player.scoreChange
                  : (totalRatingDiff != 0.0 ? totalRatingDiff.round() : null))
              : null,
      standardRating:
          playerRatings?.getRating('standard') ?? player.score.round(),
      rapidRating: playerRatings?.getRating('rapid'),
      blitzRating: playerRatings?.getRating('blitz'),
      rows: shareRows,
      shareUrl: playerShareUrl,
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

    final scoreCardScaffold = Scaffold(
      key: e2eKey(E2eIds.scorecardRoot),
      backgroundColor: context.colors.background,
      body: SafeArea(
        // No bottom inset — bottom safe area shrinks the scroll viewport and
        // cuts off the last games during scroll. Clearance is restored via a
        // trailing padding sliver below instead.
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            // Horizontal swipe between players is owned by the parent PageView
            // (see [ScoreCardScreen]); this page only scrolls vertically.
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                _SliverScoreboardAppBar(
                  player: player,
                  coachmarkEnabled: isActive,
                  isSheet: isSheet,
                  onSharePerformance: sharePlayerProfile,
                ),
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
                if (isLoadingGames ||
                    // On a deep-linked cold-start the games-tour provider
                    // can briefly emit AsyncData([]) before tourDetail
                    // resolves; treat that window as still loading so we
                    // don't flash "No games in this tournament" between the
                    // push and the real data arriving.
                    (hasEventContext &&
                        playerGames.isEmpty &&
                        ref
                                .watch(tourDetailScreenProvider)
                                .valueOrNull
                                ?.aboutTourModel
                                .id
                                .isNotEmpty !=
                            true))
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
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          SizedBox(height: 12.h),
                          Text(
                            hasEventContext
                                ? 'No games in this tournament'
                                : 'No games available',
                            style: AppTypography.textSmMedium.copyWith(
                              color: context.colors.textPrimary.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          SizedBox(height: 6.h),
                          Text(
                            hasEventContext
                                ? 'This player has not played in this tournament yet'
                                : 'Games will appear once they are played',
                            textAlign: TextAlign.center,
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textPrimary.withValues(
                                alpha: 0.5,
                              ),
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
                        final fidePlayerRating =
                            tc != null
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
                          onPlayerTap:
                              () => _openOpponentCard(
                                context: context,
                                ref: ref,
                                opponent: opponent,
                              ),
                          onTap: () {
                            final navigation = scoreCardGameNavigationContext(
                              hasEventContext: hasEventContext,
                            );

                            // Pass playerGames (filtered for this player) instead of allGames
                            // so swiping in chessboard only shows this player's games
                            ref
                                .read(gameCardWrapperProvider)
                                .navigateToChessBoard(
                                  context: context,
                                  orderedGames: playerGames,
                                  gameIndex: index,
                                  onReturnFromChessboard: (_) {},
                                  viewSource: navigation.viewSource,
                                  listPolicy: navigation.listPolicy,
                                  playerProfileDataSource: profileDataSource,
                                );
                          },
                        ),
                      );
                    }, childCount: playerGames.length),
                  ),
                // Bottom breathing room + restored home-indicator clearance
                // (SafeArea bottom was disabled to stop scroll cutoffs).
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 24.h + MediaQuery.of(context).padding.bottom,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Detect a screenshot of the scorecard and nudge sharing the branded card.
    return ScreenshotShareNudge(
      // `isActive` keeps the PageView's pre-built neighbour pages out of this:
      // the nudge's guards are per-instance, so without it one screenshot
      // opens a share preview for two or three players at once.
      enabled: isActive && hasEventContext && playerGames.isNotEmpty,
      onShare: sharePlayerProfile,
      child: scoreCardScaffold,
    );
  }

  /// Opens the tapped opponent's performance card. On the root screen that is
  /// a bottom sheet stacked over the current player (whose selection stays
  /// untouched); inside the sheet it swaps the sheet's card in place.
  void _openOpponentCard({
    required BuildContext context,
    required WidgetRef ref,
    required PlayerCard opponent,
  }) {
    final standings =
        ref.read(playerTourScreenProvider).valueOrNull ??
        const <PlayerStandingModel>[];
    final target = scoreCardOpponentTarget(
      players: standings,
      name: opponent.name,
      countryCode: opponent.countryCode,
      title: opponent.title,
      rating: opponent.rating,
      fideId: opponent.fideId,
      gamebasePlayerId: opponent.gamebasePlayerId,
      team: opponent.team,
    );

    final swapInPlace = onOpponentSelected;
    if (swapInPlace != null) {
      swapInPlace(target);
      return;
    }
    showOpponentScoreCardSheet(context: context, player: target);
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
    if (isArmageddonGame(game)) {
      return customAwareResultLabelForSide(
            game.gameStatus,
            isWhite: isWhite,
            customPoints:
                isWhite
                    ? game.whitePlayer.customPoints
                    : game.blackPlayer.customPoints,
          ) ??
          '-';
    }

    return boardResultLabelForSide(game, isWhite: isWhite) ?? '-';
  }

  String? _buildRoundLabel(GamesTourModel game) {
    final slugLabel = _parseRoundLabel(game.roundSlug);
    if (slugLabel != null) return slugLabel;

    final roundIdLabel = _parseRoundLabel(game.roundId);
    return roundIdLabel;
  }

  String? _parseRoundLabel(String? source) {
    if (source == null || source.isEmpty) return null;

    final knockoutLabel = _knockoutRoundLabel(source);
    if (knockoutLabel != null) return knockoutLabel;

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

  List<PlayerEventShareGameRow> _buildPlayerEventShareRows({
    required List<GamesTourModel> playerGames,
    required PlayerStandingModel player,
    required dynamic playerUtils,
    required dynamic playerRatings,
    required bool hasEventContext,
  }) {
    return [
      for (final game in playerGames)
        _playerEventShareRowFor(
          game: game,
          player: player,
          playerUtils: playerUtils,
          playerRatings: playerRatings,
          hasEventContext: hasEventContext,
        ),
    ];
  }

  PlayerEventShareGameRow _playerEventShareRowFor({
    required GamesTourModel game,
    required PlayerStandingModel player,
    required dynamic playerUtils,
    required dynamic playerRatings,
    required bool hasEventContext,
  }) {
    final isWhite = playerUtils.isSamePlayerWithFideId(
      game.whitePlayer.name,
      player.name,
      fideId1: game.whitePlayer.fideId,
      fideId2: player.fideId,
    );
    final opponent = isWhite ? game.blackPlayer : game.whitePlayer;
    final playerRating = _getPlayerRatingForSide(game, isWhite);
    final opponentRating = _getPlayerRatingForSide(game, !isWhite);
    double ratingChange = 0.0;
    if (playerRating > 0 && opponentRating > 0) {
      final tc = game.timeControl;
      final fideK = tc != null ? playerRatings?.getK(tc) : null;
      final fidePlayerRating =
          tc != null ? playerRatings?.getRating(tc)?.toDouble() : null;
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

    return PlayerEventShareGameRow(
      roundLabel: hasEventContext ? _buildRoundLabel(game) : null,
      countryCode: opponent.countryCode,
      title: opponent.title,
      name: opponent.name,
      rating: opponent.rating,
      ratingChange: ratingChange != 0.0 ? ratingChange : null,
      result: _getPlayerResult(game, isWhite),
      outcome: _shareOutcomeFor(game.gameStatus, isWhite),
      isWhite: isWhite,
    );
  }

  PlayerEventGameOutcome _shareOutcomeFor(GameStatus status, bool isWhite) {
    switch (status) {
      case GameStatus.whiteWins:
        return isWhite
            ? PlayerEventGameOutcome.win
            : PlayerEventGameOutcome.loss;
      case GameStatus.blackWins:
        return isWhite
            ? PlayerEventGameOutcome.loss
            : PlayerEventGameOutcome.win;
      case GameStatus.draw:
        return PlayerEventGameOutcome.draw;
      default:
        return PlayerEventGameOutcome.other;
    }
  }

  Future<void> _sharePlayerEventProfile({
    required BuildContext context,
    required PlayerStandingModel player,
    required Future<String?>? photoFuture,
    required String initials,
    required String? eventName,
    required int? performanceRating,
    required double? eventScore,
    required int? eventTotalGames,
    required int? ratingDiff,
    required int? standardRating,
    required int? rapidRating,
    required int? blitzRating,
    required List<PlayerEventShareGameRow> rows,
    required String? shareUrl,
  }) async {
    try {
      final logicalWidth = math.min(MediaQuery.of(context).size.width, 430.0);

      // Warm the player photo into the global image cache before the snapshot so
      // the avatar paints on the first captured frame instead of falling back to
      // initials. A missing/failed photo must never block the share.
      try {
        final photoUrl = await photoFuture;
        if (photoUrl != null && photoUrl.isNotEmpty && context.mounted) {
          await precacheImage(CachedNetworkImageProvider(photoUrl), context);
        }
      } catch (_) {}
      if (!context.mounted) return;

      // Render the card from the real (but off-screen) widget tree rather than
      // ScreenshotController.captureFromLongWidget. That helper builds a detached
      // pipeline and does a single synchronous paint flush; any async image
      // (network photo, country flags, bundle icons) that settles mid-capture
      // dirties a repaint boundary with no layer and throws
      // 'node._layerHandle.layer != null'. A boundary mounted in the live tree is
      // driven by the engine's frame loop, so every image loads and paints before
      // we snapshot. Height stays intrinsic (no row dropped on long event runs).
      final imageBytes = await captureCardPng(
        context,
        width: logicalWidth,
        pixelRatio: 3.0,
        child: PlayerEventShareImageCard(
          width: logicalWidth,
          player: player,
          photoFuture: photoFuture,
          initials: initials,
          eventName: eventName,
          performanceRating: performanceRating,
          eventScore: eventScore,
          eventTotalGames: eventTotalGames,
          ratingDiff: ratingDiff,
          standardRating: standardRating,
          rapidRating: rapidRating,
          blitzRating: blitzRating,
          rows: rows,
        ),
      );
      if (imageBytes == null) {
        throw StateError('Share card render produced no image');
      }
      if (!context.mounted) return;

      final tempDir = await getTemporaryDirectory();
      final file = io.File('${tempDir.path}/chessever_player_profile.png');
      await file.writeAsBytes(imageBytes);
      if (!context.mounted) return;

      // shareUrl already encodes /player/<fideId> when a FIDE id is available
      // (built via buildEventShareUrl). Opening it pushes the event then this
      // player's scorecard in-app, and renders the player OG card on the web.
      final playerShareUrl = shareUrl;
      final subject =
          eventName?.trim().isNotEmpty == true ? eventName! : 'ChessEver';

      await showShareImagePreview(
        context,
        imageBytes: imageBytes,
        onShareImage: () async {
          await shareFilesWithText(
            [XFile(file.path, mimeType: 'image/png')],
            text: playerShareUrl,
            subject: subject,
            sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
          );
        },
        onShareLink:
            playerShareUrl == null || playerShareUrl.isEmpty
                ? null
                : () async {
                  await Share.share(
                    playerShareUrl,
                    subject: subject,
                    sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
                  );
                },
      );
    } catch (error) {
      debugPrint('Failed to share player profile: $error');
      if (!context.mounted) return;
      showAppSnack(
        context,
        'Failed to share player profile',
        tone: AppSnackTone.danger,
      );
    }
  }

  void _navigateToPlayerProfile(
    BuildContext context,
    WidgetRef ref,
    PlayerStandingModel player,
  ) {
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
              gamebasePlayerId: player.gamebasePlayerId,
            ),
      ),
    );
  }

  /// Knockout stage rank from a round slug: number of players remaining in
  /// that stage, so larger = earlier (round-of-16 -> 16, quarterfinals -> 8,
  /// semifinals -> 4, third place -> 3, finals -> 2). Null for non-KO slugs.
  /// "quarterfinals"/"semifinals" contain "final", so those tokens are
  /// checked first.
  int? _knockoutStageRank(String source) {
    final s = source.toLowerCase();
    final roundOf = RegExp(r'round[-\s_]?of[-\s_]?(\d+)').firstMatch(s);
    if (roundOf != null) return int.tryParse(roundOf.group(1)!);
    if (s.contains('quarter')) return 8;
    if (s.contains('semi')) return 4;
    if (s.contains('third') || s.contains('3rd')) return 3;
    if (s.contains('final')) return 2;
    return null;
  }

  /// Order key for knockout round slugs like "quarterfinals-game-2" or
  /// "finals-tiebreaks": progresses by stage first, then game number within
  /// the stage, tiebreaks after regular games. Keys are negative so they
  /// never mix with plain "round-N" numbers (an event's slugs are homogeneous
  /// anyway). Null when the slug carries no knockout stage token.
  int? _knockoutRoundOrderKey(String source) {
    final stage = _knockoutStageRank(source);
    if (stage == null) return null;
    final s = source.toLowerCase();
    var gameNr =
        int.tryParse(
          RegExp(r'game[-\s_]?(\d+)').firstMatch(s)?.group(1) ?? '',
        ) ??
        0;
    if (s.contains('tiebreak')) gameNr += 900;
    return -stage * 1000 + gameNr;
  }

  /// Compact label for knockout rounds, e.g. "QF1.", "SF2.", "F1.", "F·TB.".
  String? _knockoutRoundLabel(String source) {
    final stage = _knockoutStageRank(source);
    if (stage == null) return null;
    final String prefix;
    switch (stage) {
      case 2:
        prefix = 'F';
      case 3:
        prefix = '3P';
      case 4:
        prefix = 'SF';
      case 8:
        prefix = 'QF';
      default:
        prefix = 'R$stage';
    }
    final s = source.toLowerCase();
    if (s.contains('tiebreak')) return '$prefix·TB.';
    final gameNr = RegExp(r'game[-\s_]?(\d+)').firstMatch(s)?.group(1);
    return gameNr == null ? '$prefix.' : '$prefix$gameNr.';
  }

  /// Extract round number from a round slug or round id string
  /// e.g., "round-2" -> 2, "round7" -> 7, "r3" -> 3
  int? _extractRoundNumber(String? source) {
    if (source == null || source.isEmpty) return null;

    final knockoutKey = _knockoutRoundOrderKey(source);
    if (knockoutKey != null) return knockoutKey;

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
  const _PlayerHeaderRow({
    required this.countryCode,
    required this.rawCountryCode,
    required this.title,
    required this.name,
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
                      color: context.colors.titleAccent,
                    ),
                  ),
                TextSpan(
                  text: formatPlayerDisplayName(name),
                  style: AppTypography.textMdBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
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
  const _SliverScoreboardAppBar({
    required this.player,
    required this.coachmarkEnabled,
    required this.onSharePerformance,
    this.isSheet = false,
  });

  /// The player this app bar belongs to. Passed explicitly rather than read
  /// from [selectedPlayerProvider] so an opponent card opened in a sheet keeps
  /// its own header while the underlying screen stays on the selected player.
  final PlayerStandingModel player;
  final bool coachmarkEnabled;
  final bool isSheet;
  final Future<void> Function() onSharePerformance;

  @override
  ConsumerState<_SliverScoreboardAppBar> createState() =>
      _SliverScoreboardAppBarState();
}

class _SliverScoreboardAppBarState
    extends ConsumerState<_SliverScoreboardAppBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  /// Optimistic heart. Following a player is a Supabase round trip wrapped in
  /// a RevenueCat check and a full list refresh, so a heart painted straight
  /// from [favoritePlayersProviderNew] stays dead under the finger for the
  /// better part of a second. The tap sets this at once; it is dropped as
  /// soon as the provider agrees (see [build]) and reverted if the write is
  /// refused or fails.
  bool? _optimisticFavorite;

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

  /// The favourite state the provider currently knows about, read the same
  /// way [build] paints it so a tap always toggles away from what is on
  /// screen.
  bool _storedFavorite() {
    final selectedPlayer = widget.player;
    final player =
        ref.read(backfilledStandingPlayerProvider(selectedPlayer)).valueOrNull ??
        selectedPlayer;
    return ref
            .read(favoritePlayersProviderNew)
            .maybeWhen(
              data:
                  (players) => storedFavoriteFor(
                    players,
                    fideId: player.fideId?.toString(),
                    name: player.name,
                    countryCode: player.countryCode,
                  ),
              orElse: () => null,
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
            ) !=
        null;
  }

  /// Hands the heart back to the provider after a refused or failed write.
  void _revertOptimisticFavorite() {
    _optimisticFavorite = null;
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavorite() async {
    final selectedPlayer = widget.player;
    final wasFavorite = _optimisticFavorite ?? _storedFavorite();
    final nowFavorite = !wasFavorite;

    // Paint and buzz first, write after: everything below this point is
    // network work, and none of it should hold the heart hostage.
    setState(() => _optimisticFavorite = nowFavorite);
    HapticFeedback.lightImpact();
    if (nowFavorite) {
      _animationController.forward().then(
        (_) => _animationController.reverse(),
      );
    }

    final allowed = await requireFullAuthGuard(context);
    if (!allowed) {
      _revertOptimisticFavorite();
      return;
    }

    try {
      final player = await ref.read(
        backfilledStandingPlayerProvider(selectedPlayer).future,
      );

      // Check if adding (not removing) and enforce limit
      final stored = ref
          .read(favoritePlayersProviderNew)
          .maybeWhen(
            data:
                (players) => storedFavoriteFor(
                  players,
                  fideId: player.fideId?.toString(),
                  name: player.name,
                  countryCode: player.countryCode,
                ),
            orElse: () => null,
          );
      if (stored == null) {
        if (!mounted) return;
        final canAdd = await canAddMoreFavorites(context, ref);
        if (!canAdd) {
          _revertOptimisticFavorite();
          return;
        }
      }

      final isNowFavorite = await ref
          .read(favoritePlayersProviderNew.notifier)
          .toggleFavorite(
            fideId: player.fideId?.toString(),
            // Removal matches on the stored `player_name`, so unfollowing
            // has to name the row that actually exists: the profile screen
            // writes the raw profile name and this screen writes the
            // backfilled standings name.
            playerName: stored?.playerName ?? player.name,
            countryCode: player.countryCode,
            rating: player.score,
            title: player.title,
          );
      if (!mounted) return;
      // The write is authoritative; hold the heart on what it reports until
      // the provider echoes the same value.
      setState(() => _optimisticFavorite = isNowFavorite);
    } on FavoriteLimitExceededException {
      _revertOptimisticFavorite();
      if (mounted) {
        await showPremiumPaywallSheet(context: context);
      }
    } catch (e) {
      _revertOptimisticFavorite();
      debugPrint('Error toggling favorite: $e');
      if (mounted) {
        showAppSnack(
          context,
          'Failed to update favorite. Please try again.',
          tone: AppSnackTone.danger,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlayer = widget.player;
    final backfilledPlayerAsync = ref.watch(
      backfilledStandingPlayerProvider(selectedPlayer),
    );
    final player = backfilledPlayerAsync.valueOrNull ?? selectedPlayer;

    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(player.countryCode);

    final favoritesAsync = ref.watch(favoritePlayersProviderNew);
    final storedFavorite = favoritesAsync.maybeWhen(
      data:
          (players) =>
              storedFavoriteFor(
                players,
                fideId: player.fideId?.toString(),
                name: player.name,
                countryCode: player.countryCode,
              ) !=
              null,
      orElse: () => false,
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
    );
    // Once the provider agrees with the optimistic flip, drop the override so
    // a change made elsewhere (favourites tab, player profile) shows up here.
    // Clearing it during build paints nothing new — both values are equal —
    // so this needs no extra frame.
    if (_optimisticFavorite == storedFavorite) _optimisticFavorite = null;
    final isFavorite = _optimisticFavorite ?? storedFavorite;

    final headerRow = _PlayerHeaderRow(
      countryCode: validCountryCode,
      rawCountryCode: player.countryCode,
      title: player.title,
      name: player.name,
    );

    return SliverAppBar(
      pinned: true,
      backgroundColor: context.colors.background,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: Icon(
          widget.isSheet
              ? Icons.close_rounded
              : Icons.arrow_back_ios_new_outlined,
          color: context.colors.textPrimary,
          size: 22.ic,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: PlayerNameShareTarget(
        playerName: player.name,
        onShare: widget.onSharePerformance,
        coachmarkEnabled: widget.coachmarkEnabled,
        coachmarkMessage: 'Tap the player’s name to share this performance.',
        child: headerRow,
      ),
      actions: [
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
                // Red heart keeps its fill; outline heart is auto-tinted
                // by SvgWidget so it stays visible on light surfaces.
                preserveOriginalColors: isFavorite,
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
                    effect: ShimmerEffect(
                      baseColor: context.colors.surfaceRecessed,
                      highlightColor: context.colors.divider,
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

/// Opens [player]'s performance card as a bottom sheet over the card that is
/// already on screen. Used when an opponent's name is tapped in a scorecard
/// row: [selectedPlayerProvider] is deliberately left alone so dismissing the
/// sheet returns to the original player with its swipe position intact.
Future<void> showOpponentScoreCardSheet({
  required BuildContext context,
  required PlayerStandingModel player,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _OpponentScoreCardSheet(player: player),
  );
}

class _OpponentScoreCardSheet extends StatefulWidget {
  const _OpponentScoreCardSheet({required this.player});

  final PlayerStandingModel player;

  @override
  State<_OpponentScoreCardSheet> createState() =>
      _OpponentScoreCardSheetState();
}

class _OpponentScoreCardSheetState extends State<_OpponentScoreCardSheet> {
  late PlayerStandingModel _player = widget.player;

  /// Resting height of the sheet, as a fraction of the (already safe-area
  /// reduced) space the route gives it. Keeps it clear of the top edge on
  /// every inset instead of overflowing on devices whose bars eat more.
  static const double _restingSize = 0.94;

  /// How far a drag can pull the sheet down before it is treated as a
  /// dismissal. `BottomSheet` closes the route as soon as a
  /// [DraggableScrollableNotification] reports the minimum extent (that is
  /// what `shouldCloseOnMinExtent` is for), so this doubles as the travel the
  /// sheet follows the finger through.
  static const double _dismissSize = 0.45;

  /// The controller [DraggableScrollableSheet] hands to the card's scroll
  /// view. Held so a nested opponent swap can reset the list to the top.
  ScrollController? _scrollController;

  @override
  Widget build(BuildContext context) {
    // The card scrolls internally, and a plain fixed-height sheet loses every
    // downward drag to it: the inner Scrollable is deeper in the hit-test
    // path, so it wins the gesture arena and the sheet never moves.
    // DraggableScrollableSheet owns that scroll position instead, which is
    // what makes the two gestures share one drag the way iOS does — the list
    // scrolls while it has somewhere to go, and once it is parked at the top
    // the same, uninterrupted drag pulls the sheet down. On release `snap`
    // leaves exactly two outcomes: settle back to [_restingSize], or carry on
    // to [_dismissSize] and close. A flick down always closes; a slow drag
    // closes past the halfway point between the two.
    return DraggableScrollableSheet(
      initialChildSize: _restingSize,
      minChildSize: _dismissSize,
      maxChildSize: _restingSize,
      snap: true,
      // The route positions this by its desired size, so the sheet must stay
      // as tall as the current extent rather than filling the screen. Filling
      // it would park an invisible sheet over the strip of barrier above the
      // card, where a tap is meant to dismiss.
      expand: false,
      builder: (context, scrollController) {
        _scrollController = scrollController;
        return _buildSheetBody(context, scrollController);
      },
    );
  }

  /// Swaps the card in place when an opponent is tapped inside the sheet,
  /// instead of stacking a second sheet on top. The new card starts at its
  /// own top; keeping the previous offset would drop the reader into the
  /// middle of a stranger's game list.
  void _showOpponent(PlayerStandingModel next) {
    setState(() => _player = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _scrollController;
      if (!mounted || controller == null || !controller.hasClients) return;
      if (controller.offset != 0) controller.jumpTo(0);
    });
  }

  Widget _buildSheetBody(
    BuildContext context,
    ScrollController scrollController,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.br)),
      child: ColoredBox(
        color: context.colors.background,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: context.colors.textPrimary.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(2.br),
                ),
              ),
            ),
            Expanded(
              child: _ScoreCardPage(
                player: _player,
                // Neighbour-page guards: the sheet never arms the screenshot
                // nudge or the share coachmark, both of which belong to the
                // card underneath it.
                isActive: false,
                isSheet: true,
                scrollController: scrollController,
                onOpponentSelected: _showOpponent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
