import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_stable_order_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/lichess_pairings_fallback_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_stage_round_resolver.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_ordering.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_stage_parser.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GroupedGamesData {
  final List<GamesAppBarModel> filteredRounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final MatchHeaderModel? matchFormatHeader;
  final bool isKnockoutTournament;
  final bool isMultiStageKnockout;
  final bool isLoading;
  final List<GamesAppBarModel> rounds;
  final List<GamesTourModel> allGames;
  final int providerGameCount;

  /// Upcoming rounds whose only content is future pairings (resolved player
  /// names, no moves yet). They render as collapsible cards pinned to the
  /// BOTTOM of the Games tab, below every played round.
  final Set<String> upcomingPairingRoundIds;

  GroupedGamesData({
    required this.filteredRounds,
    required this.gamesByRound,
    this.matchFormatHeader,
    required this.isKnockoutTournament,
    required this.isMultiStageKnockout,
    required this.isLoading,
    required this.rounds,
    required this.allGames,
    required this.providerGameCount,
    this.upcomingPairingRoundIds = const {},
  });
}

// Optimization: Move heavy grouping, filtering, and sorting off the main UI build path.
// The UI can just watch this provider and paint.
final gamesTourGroupedProvider = Provider.autoDispose<GroupedGamesData>((ref) {
  final tourId = ref.watch(
    tourDetailScreenProvider.select(
      (tourAsync) => tourAsync.valueOrNull?.aboutTourModel.id,
    ),
  );
  final isVirtualGamebaseEvent = isVirtualGamebaseId(tourId);
  final rawGamesAsync =
      tourId == null
          ? const AsyncValue<List<Games>>.data(<Games>[])
          : ref.watch(gamesTourProvider(tourId));
  final rawGames = rawGamesAsync.valueOrNull ?? const <Games>[];
  final gamesAppBar = ref.watch(gamesAppBarProvider);
  final roundResolution = resolveGamesTourRounds(
    gamesAppBar: gamesAppBar,
    rawGames: rawGames,
  );
  if (roundResolution.isLoading) {
    return GroupedGamesData(
      filteredRounds: [],
      gamesByRound: {},
      isKnockoutTournament: false,
      isMultiStageKnockout: false,
      isLoading: true,
      rounds: [],
      allGames: [],
      providerGameCount: 0,
    );
  }

  final rounds = roundResolution.rounds;
  final knockoutState = ref.watch(knockoutTournamentStateProvider(tourId));
  final isKnockoutTournament = knockoutState.isKnockout;

  final screenModelAsync = ref.watch(gamesTourScreenProvider);
  final allGamesScreenModel =
      screenModelAsync.valueOrNull?.gamesTourModels ?? [];
  final isSearchMode = screenModelAsync.valueOrNull?.isSearchMode ?? false;
  final displayMode =
      screenModelAsync.valueOrNull?.gameDisplayMode ?? GameDisplayMode.all;
  final pinState =
      tourId == null
          ? const GamesPinState(hasResolvedAutoPins: true)
          : ref.watch(gamesPinprovider(tourId));
  final stableOrder =
      tourId == null ? null : ref.watch(gamesTourStableOrderProvider(tourId));

  final providerGameCount = rawGames.length;
  final modelGameCount = allGamesScreenModel.length;

  if (rawGamesAsync.isLoading && allGamesScreenModel.isEmpty) {
    return GroupedGamesData(
      filteredRounds: [],
      gamesByRound: {},
      isKnockoutTournament: isKnockoutTournament,
      isMultiStageKnockout: false,
      isLoading: true,
      rounds: rounds,
      allGames: allGamesScreenModel,
      providerGameCount: providerGameCount,
    );
  }

  if (!isSearchMode && providerGameCount > 0 && modelGameCount == 0) {
    return GroupedGamesData(
      filteredRounds: [],
      gamesByRound: {},
      isKnockoutTournament: isKnockoutTournament,
      isMultiStageKnockout: false,
      isLoading: true,
      rounds: rounds,
      allGames: allGamesScreenModel,
      providerGameCount: providerGameCount,
    );
  }

  MatchHeaderModel? matchFormatHeader;
  if (!isKnockoutTournament) {
    final tourDetail = ref.read(tourDetailScreenProvider).valueOrNull;
    final allTours = tourDetail?.tours ?? [];
    final currentTour =
        allTours.where((t) => t.tour.id == tourId).firstOrNull?.tour;
    final formatString = currentTour?.info.format;

    if (KnockoutMatchDetector.isMatchFormat(
      formatString,
      allGamesScreenModel,
    )) {
      final matches = KnockoutMatchDetector.groupByMatchesAcrossAllRounds(
        allGamesScreenModel,
      );
      if (matches.isNotEmpty) {
        final entry = matches.entries.first;
        matchFormatHeader = KnockoutMatchDetector.createMatchHeader(
          entry.key,
          entry.value,
        );
      }
    }
  }

  final gamesByRound = <String, List<GamesTourModel>>{};
  final seenGameIdsPerRound = <String, Set<String>>{};
  var hasSupplementalPriorityGames = false;

  void ensureRoundEntry(String roundId) {
    gamesByRound.putIfAbsent(roundId, () => <GamesTourModel>[]);
    seenGameIdsPerRound.putIfAbsent(roundId, () => <String>{});
  }

  bool addGameToRound(String roundId, GamesTourModel game) {
    if (!isEventBoardGameVisible(game)) {
      return false;
    }
    ensureRoundEntry(roundId);
    if (seenGameIdsPerRound[roundId]!.add(game.gameId)) {
      gamesByRound[roundId]!.add(game);
      return true;
    }
    return false;
  }

  for (final round in rounds) {
    ensureRoundEntry(round.id);
  }

  final isMultiStageKnockout =
      isKnockoutTournament &&
      rounds.any((r) => r.id.startsWith('knockout-stage-'));
  final knownTourIds =
      ref
          .read(tourDetailScreenProvider)
          .valueOrNull
          ?.tours
          .map((tour) => tour.tour.id) ??
      const <String>[];
  final stageReferences = <String, KnockoutStageRoundReference>{
    if (tourId != null)
      for (final round in rounds)
        if (resolveKnockoutStageRoundReference(
              round: round,
              selectedTourId: tourId,
              knownTourIds: knownTourIds,
            )
            case final reference?)
          round.id: reference,
  };
  final hasSiblingStageTours = stageReferences.values.any(
    (reference) => reference.isSiblingTour,
  );
  var representedSiblingIsLoading = false;

  if (isMultiStageKnockout && hasSiblingStageTours) {
    if (!isSearchMode) {
      final stageTourGames = <String, List<GamesTourModel>>{};
      for (final stageTourId
          in stageReferences.values
              .map((reference) => reference.siblingTourId)
              .whereType<String>()
              .toSet()) {
        final stageAsync = ref.watch(gamesTourProvider(stageTourId));
        representedSiblingIsLoading =
            representedSiblingIsLoading || stageAsync.isLoading;
        final rawStageGames = stageAsync.valueOrNull ?? [];
        final stageModels = <GamesTourModel>[];
        for (final game in rawStageGames) {
          try {
            final model = GamesTourModel.fromGame(game);
            if (isEventBoardGameVisible(model)) stageModels.add(model);
          } catch (_) {
            // One malformed row must not hide every sibling stage game.
          }
        }
        stageTourGames[stageTourId] = stageModels;
      }

      for (final round in rounds) {
        final reference = stageReferences[round.id];
        if (reference == null) continue;
        final stageTourId = reference.siblingTourId;
        gamesByRound[round.id] =
            stageTourId == null
                ? allGamesScreenModel
                    .where((game) => game.tourId == tourId)
                    .toList(growable: false)
                : stageTourGames[stageTourId] ?? [];
      }
    } else {
      for (final game in allGamesScreenModel) {
        for (final entry in stageReferences.entries) {
          final representedTourId = entry.value.siblingTourId ?? tourId;
          if (game.tourId == representedTourId) {
            addGameToRound(entry.key, game);
            break;
          }
        }
      }
    }
  } else if (isMultiStageKnockout) {
    for (final game in allGamesScreenModel) {
      String? roundId;
      for (final stage in rounds) {
        if (stage.sourceRoundIds.contains(game.roundId)) {
          roundId = stage.id;
          break;
        }
      }
      // Compatibility fallback for cached/legacy synthetic models that do not
      // yet carry their source round ids.
      if (roundId == null && tourId != null) {
        roundId = roundSlugStageRoundId(tourId, game.roundSlug);
      }
      if (roundId != null && gamesByRound.containsKey(roundId)) {
        addGameToRound(roundId, game);
      }
    }
  } else {
    for (final game in allGamesScreenModel) {
      if (!isKnockoutTournament && !_shouldIncludeGame(displayMode, game)) {
        continue;
      }
      final isGameInAnyRound = rounds.any((r) => r.id == game.roundId);
      if (isGameInAnyRound) {
        addGameToRound(game.roundId, game);
      } else {
        final defaultRound = rounds.firstOrNull;
        if (defaultRound != null) {
          addGameToRound(defaultRound.id, game);
        }
      }
    }
  }

  // Future rounds: Lichess publishes pairings for upcoming rounds ahead of
  // time. Those games never pass isEventBoardGameVisible (no played position),
  // so their rounds would be dropped entirely. Surface them as pairing-only
  // round cards instead — but only with resolved player names ("?" placeholder
  // pairings stay hidden) and never for multi-stage knockouts, whose rounds
  // are synthetic stage ids.
  final upcomingPairingRoundIds = <String>{};
  if (!isMultiStageKnockout) {
    for (final round in rounds) {
      if (gamesByRound[round.id]?.isNotEmpty ?? false) continue;
      // Keep pairing cards visible past starts_at too: a round flips
      // upcoming -> ongoing/live at its scheduled time, but the broadcast
      // (and its first moves) often lags minutes behind. Only rounds that
      // are conclusively over (completed) are excluded.
      if (round.roundStatus == RoundStatus.completed) continue;

      final pairings =
          allGamesScreenModel
              .where(
                (game) =>
                    game.roundId == round.id &&
                    (isKnockoutTournament ||
                        _shouldIncludeGame(displayMode, game)) &&
                    _hasResolvedPlayer(game.whitePlayer) &&
                    _hasResolvedPlayer(game.blackPlayer),
              )
              .toList()
            ..sort((a, b) {
              final aBoard = a.boardNr;
              final bBoard = b.boardNr;
              if (aBoard != null && bBoard != null) {
                return aBoard.compareTo(bBoard);
              }
              if (aBoard != null) return -1;
              if (bBoard != null) return 1;
              return a.gameId.compareTo(b.gameId);
            });
      if (pairings.isEmpty) continue;

      ensureRoundEntry(round.id);
      for (final game in pairings) {
        if (seenGameIdsPerRound[round.id]!.add(game.gameId)) {
          gamesByRound[round.id]!.add(game);
        }
      }
      upcomingPairingRoundIds.add(round.id);
    }
  }

  // FALLBACK: during a round break the DB may not have the next round's
  // pairings yet (backend pairing sync disabled or lagging) even though
  // Lichess has already published them. Fetch that single round straight
  // from the public Lichess API and surface it exactly like DB-backed
  // pairings; the fetch provider auto-refreshes every 90s and this branch
  // deactivates on its own once real rows exist in the DB.
  if (!isMultiStageKnockout &&
      !isVirtualGamebaseEvent &&
      !isSearchMode &&
      tourId != null) {
    final now = DateTime.now();
    GamesAppBarModel? fallbackRound;
    for (final round in rounds) {
      if (upcomingPairingRoundIds.contains(round.id)) continue;
      if (gamesByRound[round.id]?.isNotEmpty ?? false) continue;
      if (round.roundStatus == RoundStatus.completed) continue;
      final startsAt = round.startsAt;
      if (startsAt == null) continue;
      final untilStart = startsAt.difference(now);
      // Slightly wider than the top-pin display gate, plus grace for
      // late-starting broadcasts (same window the data hub sync uses).
      if (untilStart >
              upcomingRoundPromotionWindow + const Duration(minutes: 5) ||
          untilStart < const Duration(minutes: -30)) {
        continue;
      }
      if (fallbackRound == null ||
          (fallbackRound.startsAt != null &&
              startsAt.isBefore(fallbackRound.startsAt!))) {
        fallbackRound = round;
      }
    }

    if (fallbackRound != null) {
      final fetched =
          ref
              .watch(
                lichessPairingsFallbackProvider(
                  LichessPairingsRequest(
                    roundId: fallbackRound.id,
                    tourId: tourId,
                  ),
                ),
              )
              .valueOrNull ??
          const <Games>[];
      final fallbackModels = <GamesTourModel>[];
      for (final game in fetched) {
        try {
          final model = GamesTourModel.fromGame(game);
          if (_hasResolvedPlayer(model.whitePlayer) &&
              _hasResolvedPlayer(model.blackPlayer)) {
            fallbackModels.add(model);
          }
        } catch (_) {
          // Best-effort fallback: skip malformed boards.
        }
      }
      if (fallbackModels.isNotEmpty) {
        hasSupplementalPriorityGames = true;
        ensureRoundEntry(fallbackRound.id);
        for (final model in fallbackModels) {
          if (seenGameIdsPerRound[fallbackRound.id]!.add(model.gameId)) {
            gamesByRound[fallbackRound.id]!.add(model);
          }
        }
        upcomingPairingRoundIds.add(fallbackRound.id);
      }
    }
  }

  // This is the one final ordering seam for DB games, sibling stages, and
  // Lichess fallback rows. Manual pins intentionally keep their existing
  // icon-only behavior. Effective favorite auto-pins lead, countrymen follow
  // only when enabled, and authoritative board number remains the default.
  final allPriorityGamesById = <String, GamesTourModel>{
    if (hasSupplementalPriorityGames) ...{
      for (final game in allGamesScreenModel) game.gameId: game,
      for (final games in gamesByRound.values)
        for (final game in games) game.gameId: game,
    },
  };
  final favoritePriorityIds =
      hasSupplementalPriorityGames
          ? pinState.effectiveFavoritePriorityIdsForGames(
            allPriorityGamesById.values,
          )
          : pinState.effectiveFavoritePriorityIds;
  final countrymanPriorityIds =
      hasSupplementalPriorityGames
          ? pinState.effectiveCountrymanPriorityIdsForGames(
            allPriorityGamesById.values,
          )
          : pinState.effectiveCountrymanPriorityIds;
  final hadGroupedGamesBeforeOrdering = gamesByRound.values.any(
    (games) => games.isNotEmpty,
  );
  // Frozen live-id snapshot for "Focus on live games". Null when mode is off.
  // Partition is applied after stable priority order so pins/board numbers
  // still decide relative order inside each live / non-live group, and status
  // stream updates never reshuffle while the snapshot is held.
  final liveFocusSnapshot =
      tourId == null ? null : ref.watch(liveFocusSnapshotProvider(tourId));
  for (final roundId in gamesByRound.keys.toList(growable: false)) {
    final roundGames = gamesByRound[roundId]!;
    final ordered = resolveTournamentRoundPresentationOrder(
      stableOrder: stableOrder,
      roundId: roundId,
      games: roundGames,
      isSearchMode: isSearchMode,
      hasResolvedAutoPins: pinState.hasResolvedAutoPins,
      isRefreshingAutoPins: pinState.isRefreshingAutoPins,
      favoriteGameIds: favoritePriorityIds,
      countrymanGameIds: countrymanPriorityIds,
    );
    gamesByRound[roundId] =
        liveFocusSnapshot == null
            ? ordered
            : applyLiveFocusOrder(
              games: ordered,
              liveGameIdsAtSnapshot: liveFocusSnapshot,
            );
  }

  final playedRounds =
      rounds
          .where(
            (round) =>
                !upcomingPairingRoundIds.contains(round.id) &&
                (gamesByRound[round.id]?.isNotEmpty ?? false),
          )
          .toList();
  final upcomingPairingRounds = sortRoundsForDisplay(
    rounds
        .where((round) => upcomingPairingRoundIds.contains(round.id))
        .toList(),
    resolveDate: (round) => round.startsAt,
  );

  // Pairing-only rounds always come last, nearest future round first.
  final filteredRounds = [...playedRounds, ...upcomingPairingRounds];
  final hasGroupedGames = gamesByRound.values.any((games) => games.isNotEmpty);
  final isPrioritySnapshotLoading = shouldKeepPrioritySnapshotLoading(
    isSearchMode: isSearchMode,
    hadGroupedGamesBeforeOrdering: hadGroupedGamesBeforeOrdering,
    hasGroupedGamesAfterOrdering: hasGroupedGames,
    hasResolvedAutoPins: pinState.hasResolvedAutoPins,
    isRefreshingAutoPins: pinState.isRefreshingAutoPins,
  );

  return GroupedGamesData(
    filteredRounds: filteredRounds,
    gamesByRound: gamesByRound,
    matchFormatHeader: matchFormatHeader,
    isKnockoutTournament: isKnockoutTournament,
    isMultiStageKnockout: isMultiStageKnockout,
    isLoading:
        isPrioritySnapshotLoading ||
        shouldKeepGroupedGamesLoading(
          representedSiblingIsLoading: representedSiblingIsLoading,
          hasGroupedGames: hasGroupedGames,
        ),
    rounds: rounds,
    allGames: allGamesScreenModel,
    providerGameCount: providerGameCount,
    upcomingPairingRoundIds: upcomingPairingRoundIds,
  );
});

typedef GamesTourRoundResolution =
    ({List<GamesAppBarModel> rounds, bool isLoading});

/// Resolves the round metadata required to group already-fetched games.
///
/// Kept as a pure seam so the loading transition can be replayed without a
/// running app or backend.
@visibleForTesting
GamesTourRoundResolution resolveGamesTourRounds({
  required AsyncValue<GamesAppBarViewModel> gamesAppBar,
  required List<Games> rawGames,
}) {
  final appBarRounds =
      gamesAppBar.valueOrNull?.gamesAppBarModels ?? const <GamesAppBarModel>[];
  final gameDerivedRounds = buildGameDerivedRoundModels(rawGames);
  if (appBarRounds.isNotEmpty) {
    return (
      rounds: fillMissingRoundStartsFromGames(appBarRounds, rawGames),
      isLoading: false,
    );
  }

  // Games and round metadata are fetched independently. A slow or stalled
  // round request must not cover boards that have already arrived with an
  // endless shimmer. The game rows carry enough round identity for a complete
  // temporary grouping; canonical metadata replaces it on the next rebuild.
  if (gameDerivedRounds.isNotEmpty) {
    return (rounds: gameDerivedRounds, isLoading: false);
  }

  if (gamesAppBar.isLoading || !gamesAppBar.hasValue) {
    return (rounds: const <GamesAppBarModel>[], isLoading: true);
  }

  return (rounds: const <GamesAppBarModel>[], isLoading: false);
}

/// Keep the empty state suppressed while a represented sibling stage is still
/// resolving, but never cover a stage that has already produced games.
bool shouldKeepGroupedGamesLoading({
  required bool representedSiblingIsLoading,
  required bool hasGroupedGames,
}) => representedSiblingIsLoading && !hasGroupedGames;

@visibleForTesting
bool shouldKeepPrioritySnapshotLoading({
  required bool isSearchMode,
  required bool hadGroupedGamesBeforeOrdering,
  required bool hasGroupedGamesAfterOrdering,
  required bool hasResolvedAutoPins,
  required bool isRefreshingAutoPins,
}) {
  if (isSearchMode || !hadGroupedGamesBeforeOrdering) return false;
  if (!hasResolvedAutoPins) return true;
  return isRefreshingAutoPins && !hasGroupedGamesAfterOrdering;
}

@visibleForTesting
List<GamesTourModel> sortTournamentRoundGamesByBoard(
  Iterable<GamesTourModel> games,
) {
  return sortTournamentRoundGamesByPriority(games: games);
}

bool _shouldIncludeGame(GameDisplayMode mode, GamesTourModel game) {
  switch (mode) {
    // Focus-on-live is sort-only (see liveFocusSnapshotProvider); never drop
    // finished boards from the Games list.
    case GameDisplayMode.hideFinishedGames:
      return true;
    case GameDisplayMode.showfinishedGame:
      return game.gameStatus.isFinished;
    case GameDisplayMode.all:
      return true;
  }
}

/// Maps a game's round slug to the synthetic stage round id that
/// gamesAppBarProvider builds for round-slug derived knockout stages
/// (`knockout-stage-<tourId>-<stage>`). Only a stage-bearing slug is accepted;
/// generic legs such as `game-1` and `tiebreak-1-rapid-1` are deliberately not
/// promoted into independent tournament stages. New synthetic models use
/// [GamesAppBarModel.sourceRoundIds] and do not need this legacy fallback.
@visibleForTesting
String? roundSlugStageRoundId(String tourId, String? roundSlug) {
  final slug = roundSlug?.trim();
  if (slug == null || slug.isEmpty) return null;
  final stage = resolveLogicalKnockoutStage('', slug);
  return stage == null ? null : '$kKnockoutStagePrefix-$tourId-${stage.key}';
}

/// Whether a game row is renderable as an event board. Shared by the event
/// Games tab and the For You feed: placeholder rows (unresolved "?" players
/// or an unstarted position) must never surface as boards on either screen.
bool isEventBoardGameVisible(GamesTourModel game) {
  if (!_hasResolvedPlayer(game.whitePlayer) ||
      !_hasResolvedPlayer(game.blackPlayer)) {
    return false;
  }

  // A decided result is enough proof the game is real, even with no moves
  // (no-show / forfeit / defaulted boards) and even for virtual Gamebase
  // header-only PGN rows. Unstarted named pairings stay hidden via ongoing
  // status + start FEN.
  if (game.gameStatus.isFinished) {
    return true;
  }

  if (_hasPlayedPosition(game)) {
    return true;
  }

  // Do not turn unstarted pairings/placeholders into playable event boards.
  // Round start times still live on the round models/schedule; empty rounds are
  // removed from the Games dropdown by filteredRounds.
  return false;
}

bool _hasResolvedPlayer(PlayerCard player) {
  final normalized = player.name.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized != '?' &&
      normalized != '??' &&
      normalized != 'tbd' &&
      normalized != 'tba' &&
      normalized != 'unknown';
}

bool _hasPlayedPosition(GamesTourModel game) {
  if (game.lastMove?.trim().isNotEmpty == true) return true;
  if (_pgnContainsMoves(game.pgn)) return true;
  final fen = game.fen?.trim();
  if (fen == null || fen.isEmpty) return false;
  return !_isInitialFen(fen);
}

bool _pgnContainsMoves(String? pgn) {
  final text = pgn?.trim();
  if (text == null || text.isEmpty) return false;
  final withoutHeaders =
      text
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('['))
          .join(' ')
          .trim();
  return RegExp(r'\b\d+\s*\.').hasMatch(withoutHeaders) ||
      RegExp(
        r'\b[a-h][1-8][a-h][1-8][qrbn]?\b',
        caseSensitive: false,
      ).hasMatch(withoutHeaders);
}

bool _isInitialFen(String fen) {
  final board = fen.split(RegExp(r'\s+')).first;
  return board == 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR';
}
