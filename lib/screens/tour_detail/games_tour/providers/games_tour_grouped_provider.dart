import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
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
  });
}

// Optimization: Move heavy grouping, filtering, and sorting off the main UI build path.
// The UI can just watch this provider and paint.
final gamesTourGroupedProvider = Provider.autoDispose<GroupedGamesData>((ref) {
  final gamesAppBar = ref.watch(gamesAppBarProvider);
  if (gamesAppBar.isLoading || !gamesAppBar.hasValue) {
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

  final rounds = gamesAppBar.value?.gamesAppBarModels ?? [];
  final tourId = ref.read(tourDetailScreenProvider).value?.aboutTourModel.id;
  final knockoutState = ref.watch(knockoutTournamentStateProvider(tourId));
  final isKnockoutTournament = knockoutState.isKnockout;

  final screenModelAsync = ref.watch(gamesTourScreenProvider);
  final allGamesScreenModel =
      screenModelAsync.valueOrNull?.gamesTourModels ?? [];
  final isSearchMode = screenModelAsync.valueOrNull?.isSearchMode ?? false;
  final displayMode =
      screenModelAsync.valueOrNull?.gameDisplayMode ?? GameDisplayMode.all;

  final gamesAsync = ref.watch(gamesTourProvider(tourId ?? ''));
  final providerGameCount = gamesAsync.valueOrNull?.length ?? 0;
  final modelGameCount = allGamesScreenModel.length;

  if (gamesAsync.isLoading && allGamesScreenModel.isEmpty) {
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
            rawStageGames.map((g) => GamesTourModel.fromGame(g)).toList();
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
      final match = RegExp(r'(stage-[^/]+)').firstMatch(game.roundSlug ?? '');
      if (match != null) {
        final stageName = match.group(1)!;
        final roundId = 'knockout-stage-$tourId-$stageName';
        if (gamesByRound.containsKey(roundId)) {
          addGameToRound(roundId, game);
        }
      }
    }
  } else {
    for (final game in allGamesScreenModel) {
      if (!isKnockoutTournament && !_shouldIncludeGame(displayMode, game))
        continue;
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

  final filteredRounds =
      rounds
          .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
          .toList();

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
