import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
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
  final virtualFallbackRounds =
      isVirtualGamebaseEvent
          ? buildVirtualGamebaseRoundModels(rawGames)
          : const <GamesAppBarModel>[];

  final gamesAppBar = ref.watch(gamesAppBarProvider);
  if ((gamesAppBar.isLoading || !gamesAppBar.hasValue) &&
      virtualFallbackRounds.isEmpty) {
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

  final appBarRounds = gamesAppBar.valueOrNull?.gamesAppBarModels ?? [];
  final rounds =
      virtualFallbackRounds.isNotEmpty && appBarRounds.isEmpty
          ? virtualFallbackRounds
          : appBarRounds;
  final knockoutState = ref.watch(knockoutTournamentStateProvider(tourId));
  final isKnockoutTournament = knockoutState.isKnockout;

  final screenModelAsync = ref.watch(gamesTourScreenProvider);
  final allGamesScreenModel =
      screenModelAsync.valueOrNull?.gamesTourModels ?? [];
  final isSearchMode = screenModelAsync.valueOrNull?.isSearchMode ?? false;
  final displayMode =
      screenModelAsync.valueOrNull?.gameDisplayMode ?? GameDisplayMode.all;

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
  final isRoundSlugDerivedStages =
      isMultiStageKnockout &&
      tourId != null &&
      rounds.any((r) {
        if (!r.id.startsWith('knockout-stage-')) return false;
        final suffix = r.id.replaceFirst('knockout-stage-', '');
        return suffix.startsWith('$tourId-') &&
            suffix.length > tourId.length + 1;
      });

  if (isMultiStageKnockout && !isRoundSlugDerivedStages) {
    if (!isSearchMode) {
      final stageTourIds =
          rounds
              .where((r) => r.id.startsWith('knockout-stage-'))
              .map((r) => r.id.replaceFirst('knockout-stage-', ''))
              .toList();

      final stageTourGames = <String, List<GamesTourModel>>{};
      for (final stageTourId in stageTourIds) {
        final stageAsync = ref.read(gamesTourProvider(stageTourId));
        final rawStageGames = stageAsync.valueOrNull ?? [];
        stageTourGames[stageTourId] =
            rawStageGames
                .map((g) => GamesTourModel.fromGame(g))
                .where(isEventBoardGameVisible)
                .toList();
      }

      for (final round in rounds) {
        if (round.id.startsWith('knockout-stage-')) {
          final stageTourId = round.id.replaceFirst('knockout-stage-', '');
          final stageGames = stageTourGames[stageTourId] ?? [];
          gamesByRound[round.id] = stageGames;
        }
      }
    } else {
      for (final game in allGamesScreenModel) {
        final stageTourId = game.tourId;
        final roundId = 'knockout-stage-$stageTourId';
        if (gamesByRound.containsKey(roundId)) {
          addGameToRound(roundId, game);
        }
      }
    }
  } else if (isRoundSlugDerivedStages) {
    for (final game in allGamesScreenModel) {
      final roundId = roundSlugStageRoundId(tourId, game.roundSlug);
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

  if (!isSearchMode) {
    final pinnedGameIds = screenModelAsync.valueOrNull?.pinnedGamedIs ?? [];
    if (pinnedGameIds.isNotEmpty) {
      for (final roundId in gamesByRound.keys) {
        final roundGames = gamesByRound[roundId]!;
        roundGames.sort((a, b) {
          final aPinned = pinnedGameIds.contains(a.gameId);
          final bPinned = pinnedGameIds.contains(b.gameId);
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
          return 0;
        });
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
      if (round.roundStatus != RoundStatus.upcoming) continue;

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

  final playedRounds =
      rounds
          .where(
            (round) =>
                !upcomingPairingRoundIds.contains(round.id) &&
                (gamesByRound[round.id]?.isNotEmpty ?? false),
          )
          .toList();
  final upcomingPairingRounds =
      rounds
          .where((round) => upcomingPairingRoundIds.contains(round.id))
          .toList()
        ..sort((a, b) {
          final aStart = a.startsAt;
          final bStart = b.startsAt;
          if (aStart == null && bStart == null) return a.name.compareTo(b.name);
          if (aStart == null) return 1;
          if (bStart == null) return -1;
          final cmp = aStart.compareTo(bStart);
          return cmp != 0 ? cmp : a.name.compareTo(b.name);
        });

  // Pairing-only rounds always come last, soonest first.
  final filteredRounds = [...playedRounds, ...upcomingPairingRounds];

  return GroupedGamesData(
    filteredRounds: filteredRounds,
    gamesByRound: gamesByRound,
    matchFormatHeader: matchFormatHeader,
    isKnockoutTournament: isKnockoutTournament,
    isMultiStageKnockout: isMultiStageKnockout,
    isLoading: false,
    rounds: rounds,
    allGames: allGamesScreenModel,
    providerGameCount: providerGameCount,
    upcomingPairingRoundIds: upcomingPairingRoundIds,
  );
});

bool _shouldIncludeGame(GameDisplayMode mode, GamesTourModel game) {
  switch (mode) {
    case GameDisplayMode.hideFinishedGames:
      return !game.gameStatus.isFinished;
    case GameDisplayMode.showfinishedGame:
      return game.gameStatus.isFinished;
    case GameDisplayMode.all:
      return true;
  }
}

/// Maps a game's round slug to the synthetic stage round id that
/// gamesAppBarProvider builds for round-slug derived knockout stages
/// (`knockout-stage-<tourId>-<stage>`). The stage part is the slug segment
/// before "--" (or the whole slug), normalized the same way the app bar
/// normalizes its stage names.
@visibleForTesting
String? roundSlugStageRoundId(String tourId, String? roundSlug) {
  final slug = roundSlug?.trim().toLowerCase();
  if (slug == null || slug.isEmpty) return null;
  final stagePart = slug.contains('--') ? slug.split('--').first : slug;
  final normalized = stagePart
      .split(RegExp(r'[-_\s]'))
      .where((s) => s.isNotEmpty)
      .join('-');
  if (normalized.isEmpty) return null;
  return '$kKnockoutStagePrefix-$tourId-$normalized';
}

/// Whether a game row is renderable as an event board. Shared by the event
/// Games tab and the For You feed: placeholder rows (unresolved "?" players
/// or an unstarted position) must never surface as boards on either screen.
bool isEventBoardGameVisible(GamesTourModel game) {
  if (!_hasResolvedPlayer(game.whitePlayer) ||
      !_hasResolvedPlayer(game.blackPlayer)) {
    return false;
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
