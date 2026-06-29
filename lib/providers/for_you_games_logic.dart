import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_ordering.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:collection/collection.dart';

const Duration _kActualLiveGameActivityWindow = Duration(minutes: 120);

class ForYouEventGamesSnapshot {
  ForYouEventGamesSnapshot({
    required this.eventId,
    required this.tourId,
    required List<GamesTourModel> visibleGames,
    required List<String> pinnedIds,
    List<String> manualPinnedIds = const [],
    List<String> autoPinnedIds = const [],
    List<String> unpinnedOverrideIds = const [],
  }) : visibleGames = List<GamesTourModel>.unmodifiable(visibleGames),
       pinnedIds = List<String>.unmodifiable(pinnedIds),
       manualPinnedIds = List<String>.unmodifiable(manualPinnedIds),
       autoPinnedIds = List<String>.unmodifiable(autoPinnedIds),
       unpinnedOverrideIds = List<String>.unmodifiable(unpinnedOverrideIds);

  final String eventId;
  final String tourId;
  final List<GamesTourModel> visibleGames;
  final List<String> pinnedIds;
  final List<String> manualPinnedIds;
  final List<String> autoPinnedIds;
  final List<String> unpinnedOverrideIds;

  bool get hasGames => visibleGames.isNotEmpty;
}

bool areEquivalentForYouSnapshots(
  ForYouEventGamesSnapshot a,
  ForYouEventGamesSnapshot b,
) {
  return a.eventId == b.eventId &&
      a.tourId == b.tourId &&
      _stringListsEqual(a.pinnedIds, b.pinnedIds) &&
      _stringListsEqual(a.manualPinnedIds, b.manualPinnedIds) &&
      _stringListsEqual(a.autoPinnedIds, b.autoPinnedIds) &&
      _stringListsEqual(a.unpinnedOverrideIds, b.unpinnedOverrideIds) &&
      _gamesListsEqual(a.visibleGames, b.visibleGames);
}

bool _stringListsEqual(List<String> a, List<String> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _gamesListsEqual(List<GamesTourModel> a, List<GamesTourModel> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (!_gamesEqual(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

bool _gamesEqual(GamesTourModel a, GamesTourModel b) {
  return a.gameId == b.gameId &&
      _playerCardsEqual(a.whitePlayer, b.whitePlayer) &&
      _playerCardsEqual(a.blackPlayer, b.blackPlayer) &&
      a.whiteTimeDisplay == b.whiteTimeDisplay &&
      a.blackTimeDisplay == b.blackTimeDisplay &&
      a.whiteClockCentiseconds == b.whiteClockCentiseconds &&
      a.blackClockCentiseconds == b.blackClockCentiseconds &&
      a.whiteClockSeconds == b.whiteClockSeconds &&
      a.blackClockSeconds == b.blackClockSeconds &&
      a.gameStatus == b.gameStatus &&
      a.fen == b.fen &&
      a.pgn == b.pgn &&
      a.lastMove == b.lastMove &&
      a.boardNr == b.boardNr &&
      a.roundId == b.roundId &&
      a.roundSlug == b.roundSlug &&
      a.tourId == b.tourId &&
      a.tourSlug == b.tourSlug &&
      a.lastMoveTime == b.lastMoveTime &&
      a.eco == b.eco &&
      a.openingName == b.openingName &&
      a.timeControl == b.timeControl &&
      a.isOnline == b.isOnline;
}

bool _playerCardsEqual(PlayerCard a, PlayerCard b) {
  return a.name == b.name &&
      a.federation == b.federation &&
      a.title == b.title &&
      a.rating == b.rating &&
      a.countryCode == b.countryCode &&
      a.fideId == b.fideId &&
      a.team == b.team &&
      a.gamebasePlayerId == b.gamebasePlayerId;
}

ForYouEventGamesSnapshot buildForYouEventGamesSnapshot({
  required String eventId,
  required Tour selectedTour,
  required List<Tour> eventTours,
  required List<Round> selectedTourRounds,
  required Map<String, List<Round>> roundsByTourId,
  required List<Games> selectedTourGames,
  required Map<String, List<Games>> gamesByTourId,
  required List<String> liveRoundIds,
  required List<String> pinnedIds,
  List<String> manualPinnedIds = const [],
  List<String> autoPinnedIds = const [],
  List<String> unpinnedOverrideIds = const [],
}) {
  final primaryGames = _mapGames(selectedTourGames);
  final actualLiveRoundIds = _actualLiveRoundIdsFromGameRows(selectedTourGames);
  final effectiveLiveRoundIds =
      actualLiveRoundIds.isNotEmpty ? actualLiveRoundIds : liveRoundIds;
  final isKnockoutTournament =
      _formatSuggestsKnockout(selectedTour.info.format) ||
      KnockoutMatchDetector.isKnockoutMatchFormat(primaryGames);
  final isGroupEvent =
      !isKnockoutTournament &&
      selectedTour.players.isNotEmpty &&
      selectedTour.players.every((player) => player.team != null);

  final sortedPrimaryGames = sortGameModelsForGamesTab(
    games: primaryGames,
    pinnedIds: pinnedIds,
  );

  final roundSortMeta = <String, _RoundSortMeta>{
    for (final round in selectedTourRounds)
      round.id: _RoundSortMeta.fromRound(round),
  };

  final baseRounds =
      selectedTourRounds
          .map(
            (round) => GamesAppBarModel.fromRound(round, effectiveLiveRoundIds),
          )
          .toList();

  final processedRounds = _buildProcessedRounds(
    selectedTour: selectedTour,
    eventTours: eventTours,
    baseRounds: baseRounds,
    roundsByTourId: roundsByTourId,
    gamesByTourId: gamesByTourId,
    liveRoundIds: effectiveLiveRoundIds,
    roundSortMeta: roundSortMeta,
    primaryGames: primaryGames,
    isKnockoutTournament: isKnockoutTournament,
  );

  _sortRounds(processedRounds, roundSortMeta);

  final gamesByRound = _buildGamesByRound(
    selectedTour: selectedTour,
    processedRounds: processedRounds,
    selectedTourGames: selectedTourGames,
    selectedTourSortedGames: sortedPrimaryGames,
    gamesByTourId: gamesByTourId,
    isKnockoutTournament: isKnockoutTournament,
    pinnedIds: pinnedIds,
  );

  final visibleRounds = _visibleRounds(
    rounds: processedRounds,
    gamesByRound: gamesByRound,
    roundSortMeta: roundSortMeta,
  );

  final orderedVisibleGames =
      isGroupEvent
          ? _flattenGroupEventGames(
            visibleRounds: visibleRounds,
            orderedTourGames: sortedPrimaryGames,
          )
          : _flattenVisibleGames(
            visibleRounds: visibleRounds,
            gamesByRound: gamesByRound,
            isKnockoutTournament: isKnockoutTournament,
          );

  return ForYouEventGamesSnapshot(
    eventId: eventId,
    tourId: selectedTour.id,
    visibleGames: orderedVisibleGames,
    pinnedIds: pinnedIds,
    manualPinnedIds: manualPinnedIds,
    autoPinnedIds: autoPinnedIds,
    unpinnedOverrideIds: unpinnedOverrideIds,
  );
}

bool isKnockoutTour({required Tour tour, required List<Games> games}) {
  if (_formatSuggestsKnockout(tour.info.format)) {
    return true;
  }
  return KnockoutMatchDetector.isKnockoutMatchFormat(_mapGames(games));
}

List<GamesTourModel> sortGamesForGamesTab({
  required List<Games> games,
  required List<String> pinnedIds,
}) {
  if (games.isEmpty) {
    return const [];
  }

  final parsedGames = <GamesTourModel>[];
  for (final game in games) {
    try {
      parsedGames.add(GamesTourModel.fromGame(game));
    } catch (_) {
      // Ignore malformed game rows to match tournament detail resiliency.
    }
  }

  return sortGameModelsForGamesTab(games: parsedGames, pinnedIds: pinnedIds);
}

List<GamesTourModel> sortGameModelsForGamesTab({
  required List<GamesTourModel> games,
  required List<String> pinnedIds,
}) {
  if (games.isEmpty) {
    return const [];
  }

  final sortedGames = List<GamesTourModel>.from(games);
  sortedGames.sort((a, b) {
    final aPinned = pinnedIds.contains(a.gameId);
    final bPinned = pinnedIds.contains(b.gameId);
    if (aPinned && !bPinned) return -1;
    if (!aPinned && bPinned) return 1;

    return _compareGameModelsByDisplayOrder(a, b);
  });

  return sortedGames;
}

int _compareGameModelsByDisplayOrder(GamesTourModel a, GamesTourModel b) {
  final aLive = a.gameStatus.isOngoing;
  final bLive = b.gameStatus.isOngoing;
  if (aLive && !bLive) return -1;
  if (!aLive && bLive) return 1;

  final roundA = _extractRoundNumber(a.roundSlug);
  final roundB = _extractRoundNumber(b.roundSlug);
  if (roundA != roundB) {
    return roundB.compareTo(roundA);
  }

  final gameA = _extractGameNumber(a.roundSlug);
  final gameB = _extractGameNumber(b.roundSlug);
  if (gameA != gameB) {
    return gameB.compareTo(gameA);
  }

  final aBoard = a.boardNr;
  final bBoard = b.boardNr;
  if (aBoard != null && bBoard != null) {
    return aBoard.compareTo(bBoard);
  }
  if (aBoard != null) return -1;
  if (bBoard != null) return 1;
  return 0;
}

List<String> mergePinnedIds({
  required List<String> manualPins,
  required List<String> autoPins,
}) {
  final seen = <String>{};
  final merged = <String>[];

  for (final pin in manualPins) {
    if (seen.add(pin)) {
      merged.add(pin);
    }
  }

  for (final pin in autoPins) {
    if (seen.add(pin)) {
      merged.add(pin);
    }
  }

  return merged;
}

List<GamesTourModel> _mapGames(List<Games> games) {
  final models = <GamesTourModel>[];
  for (final game in games) {
    try {
      models.add(GamesTourModel.fromGame(game));
    } catch (_) {
      // Ignore invalid display rows.
    }
  }
  return models;
}

List<String> _actualLiveRoundIdsFromGameRows(List<Games> games) {
  final now = DateTime.now();
  final activityByRound = <String, DateTime?>{};

  for (final game in games) {
    if (!GameStatus.fromString(game.status).isOngoing) {
      continue;
    }

    if (game.lastMove == null || game.lastMove!.trim().isEmpty) {
      continue;
    }

    final activity = game.lastMoveTime;
    if (activity == null ||
        activity.isAfter(now.add(const Duration(minutes: 2))) ||
        now.difference(activity) > _kActualLiveGameActivityWindow) {
      continue;
    }

    final current = activityByRound[game.roundId];
    if (!activityByRound.containsKey(game.roundId) ||
        current == null ||
        activity.isAfter(current)) {
      activityByRound[game.roundId] = activity;
    }
  }

  final entries =
      activityByRound.entries.toList()..sort((a, b) {
        final aTime = a.value;
        final bTime = b.value;
        if (aTime == null && bTime == null) {
          return a.key.compareTo(b.key);
        }
        if (aTime == null) {
          return 1;
        }
        if (bTime == null) {
          return -1;
        }
        final timeCompare = bTime.compareTo(aTime);
        if (timeCompare != 0) {
          return timeCompare;
        }
        return a.key.compareTo(b.key);
      });

  return entries.map((entry) => entry.key).toList(growable: false);
}

bool _formatSuggestsKnockout(String? format) {
  if (format == null || format.isEmpty) return false;
  final lower = format.toLowerCase();
  return lower.contains('knockout') ||
      lower.contains('single-elimination') ||
      lower.contains('elimination');
}

List<GamesAppBarModel> _buildProcessedRounds({
  required Tour selectedTour,
  required List<Tour> eventTours,
  required List<GamesAppBarModel> baseRounds,
  required Map<String, List<Round>> roundsByTourId,
  required Map<String, List<Games>> gamesByTourId,
  required List<String> liveRoundIds,
  required Map<String, _RoundSortMeta> roundSortMeta,
  required List<GamesTourModel> primaryGames,
  required bool isKnockoutTournament,
}) {
  if (!isKnockoutTournament) {
    return baseRounds;
  }

  final relatedTours =
      eventTours
          .where(
            (tour) => tour.groupBroadcastId == selectedTour.groupBroadcastId,
          )
          .toList()
        ..sort((a, b) {
          final aDate = a.dates.isNotEmpty ? a.dates.first : DateTime(1970);
          final bDate = b.dates.isNotEmpty ? b.dates.first : DateTime(1970);
          return bDate.compareTo(aDate);
        });

  if (relatedTours.length > 1) {
    final stageModels = <GamesAppBarModel>[];

    for (final tour in relatedTours) {
      final tourRounds = roundsByTourId[tour.id] ?? const <Round>[];
      if (tourRounds.isEmpty) {
        continue;
      }

      final stageRoundModels =
          tourRounds
              .map((round) => GamesAppBarModel.fromRound(round, liveRoundIds))
              .toList();
      final tourGames = gamesByTourId[tour.id] ?? const <Games>[];
      final tourModels = _mapGames(tourGames);
      final stageIsKnockout =
          _formatSuggestsKnockout(tour.info.format) ||
          KnockoutMatchDetector.isKnockoutMatchFormat(tourModels);
      if (!stageIsKnockout) {
        continue;
      }

      final stageStartsAt = _resolveStageStartDate(
        tour: tour,
        stageRoundModels: stageRoundModels,
      );
      final stageName =
          tour.name.contains('|')
              ? tour.name.split('|').last.trim()
              : tour.name;
      final stageId = '$kKnockoutStagePrefix-${tour.id}';

      roundSortMeta[stageId] = _RoundSortMeta(
        slug: tour.slug,
        createdAt: tour.createdAt,
        startsAt: stageStartsAt,
        roundNumber: _parseRoundNumber(stageName),
        gameNumber: null,
      );

      stageModels.add(
        GamesAppBarModel(
          id: stageId,
          name: stageName,
          startsAt: stageStartsAt,
          roundStatus: _aggregateStageStatus(stageRoundModels),
        ),
      );
    }

    if (stageModels.isNotEmpty) {
      return stageModels;
    }
  }

  final stageGamesMap = <String, List<GamesAppBarModel>>{};
  for (final game in primaryGames) {
    final slug = game.roundSlug?.trim();
    if (slug == null || slug.isEmpty) {
      continue;
    }

    final stagePart = slug.contains('--') ? slug.split('--').first : slug;
    final stageName = _formatStageName(stagePart);
    final matchingRound =
        baseRounds.where((round) => round.id == game.roundId).firstOrNull;
    if (matchingRound == null) {
      continue;
    }
    stageGamesMap.putIfAbsent(stageName, () => []).add(matchingRound);
  }

  if (stageGamesMap.length > 1) {
    final stageModels = <GamesAppBarModel>[];

    for (final entry in stageGamesMap.entries) {
      final stageRounds = entry.value.toSet().toList();
      final stageStartsAt = stageRounds
          .map((round) => round.startsAt)
          .whereType<DateTime>()
          .fold<DateTime?>(null, (latest, value) {
            if (latest == null || value.isAfter(latest)) {
              return value;
            }
            return latest;
          });
      final stageCreatedAt =
          stageRounds
              .map((round) => roundSortMeta[round.id]?.createdAt)
              .whereType<DateTime>()
              .fold<DateTime?>(null, (latest, value) {
                if (latest == null || value.isAfter(latest)) {
                  return value;
                }
                return latest;
              }) ??
          selectedTour.createdAt;
      final stageId =
          '$kKnockoutStagePrefix-${selectedTour.id}-${entry.key.toLowerCase().replaceAll(' ', '-')}';

      roundSortMeta[stageId] = _RoundSortMeta(
        slug: entry.key.toLowerCase().replaceAll(' ', '-'),
        createdAt: stageCreatedAt,
        startsAt: stageStartsAt,
        roundNumber: _parseRoundNumber(entry.key),
        gameNumber: null,
      );

      stageModels.add(
        GamesAppBarModel(
          id: stageId,
          name: entry.key,
          startsAt: stageStartsAt,
          roundStatus: _aggregateStageStatus(stageRounds),
        ),
      );
    }

    return stageModels;
  }

  final logicalRoundId = '$kKnockoutStagePrefix-${selectedTour.id}';
  final logicalRoundName =
      selectedTour.name.contains('|')
          ? selectedTour.name.split('|').last.trim()
          : selectedTour.name;
  final logicalStartsAt = _resolveStageStartDate(
    tour: selectedTour,
    stageRoundModels: baseRounds,
  );

  roundSortMeta[logicalRoundId] = _RoundSortMeta(
    slug: baseRounds.firstOrNull?.name.toLowerCase().replaceAll(' ', '-') ?? '',
    createdAt: selectedTour.createdAt,
    startsAt: logicalStartsAt,
    roundNumber: _parseRoundNumber(logicalRoundName),
    gameNumber: null,
  );

  return [
    GamesAppBarModel(
      id: logicalRoundId,
      name: logicalRoundName,
      startsAt: logicalStartsAt,
      roundStatus: _aggregateStageStatus(baseRounds),
    ),
  ];
}

Map<String, List<GamesTourModel>> _buildGamesByRound({
  required Tour selectedTour,
  required List<GamesAppBarModel> processedRounds,
  required List<Games> selectedTourGames,
  required List<GamesTourModel> selectedTourSortedGames,
  required Map<String, List<Games>> gamesByTourId,
  required bool isKnockoutTournament,
  required List<String> pinnedIds,
}) {
  if (!isKnockoutTournament) {
    final result = <String, List<GamesTourModel>>{};
    for (final round in processedRounds) {
      result[round.id] = selectedTourSortedGames
          .where((game) => game.roundId == round.id)
          .toList(growable: false);
    }
    return result;
  }

  final result = <String, List<GamesTourModel>>{
    for (final round in processedRounds) round.id: <GamesTourModel>[],
  };
  final hasSyntheticStages = processedRounds.any(
    (round) => round.id.startsWith('$kKnockoutStagePrefix-'),
  );
  final isRoundSlugDerivedStages =
      hasSyntheticStages &&
      processedRounds.any(
        (round) =>
            round.id.startsWith('$kKnockoutStagePrefix-${selectedTour.id}-'),
      );

  if (hasSyntheticStages && !isRoundSlugDerivedStages) {
    for (final round in processedRounds) {
      final stageTourId = round.id.replaceFirst('$kKnockoutStagePrefix-', '');
      final stageGames = _mapGames(
        gamesByTourId[stageTourId] ?? const <Games>[],
      );
      result[round.id] = _pinOnlySort(stageGames, pinnedIds);
    }
    return result;
  }

  if (isRoundSlugDerivedStages) {
    for (final game in selectedTourSortedGames) {
      final gameSlug = (game.roundSlug ?? '').trim().toLowerCase();
      if (gameSlug.isEmpty) {
        continue;
      }

      final stagePart = (gameSlug.contains('--')
              ? gameSlug.split('--').first
              : gameSlug)
          .replaceAll(' ', '-');

      for (final round in processedRounds) {
        if (!round.id.startsWith('$kKnockoutStagePrefix-')) {
          continue;
        }

        final roundStagePart = round.id.split('-').skip(3).join('-');
        if (roundStagePart == stagePart) {
          result[round.id]!.add(game);
          break;
        }
      }
    }
    return result;
  }

  final selectedStageId = '$kKnockoutStagePrefix-${selectedTour.id}';
  result[selectedStageId] = _pinOnlySort(selectedTourSortedGames, pinnedIds);
  return result;
}

List<GamesAppBarModel> _visibleRounds({
  required List<GamesAppBarModel> rounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  required Map<String, _RoundSortMeta> roundSortMeta,
}) {
  final isMultiStageKnockout = rounds.any(
    (round) => round.id.startsWith('$kKnockoutStagePrefix-'),
  );

  final isPreConfigured = rounds.every(
    (round) => _hasConfiguredStartTime(round, roundSortMeta),
  );
  final hasLiveOrOngoing = rounds.any(
    (candidate) =>
        candidate.roundStatus == RoundStatus.live ||
        candidate.roundStatus == RoundStatus.ongoing,
  );
  final hasCompleted = rounds.any(
    (candidate) => candidate.roundStatus == RoundStatus.completed,
  );
  final allAreUpcoming = rounds.every(
    (candidate) =>
        candidate.roundStatus == RoundStatus.upcoming ||
        (gamesByRound[candidate.id]?.isEmpty ?? true),
  );

  final visibleRounds = <GamesAppBarModel>[];
  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) {
      continue;
    }

    if (isMultiStageKnockout) {
      visibleRounds.add(round);
      continue;
    }

    if (isPreConfigured) {
      visibleRounds.add(round);
      continue;
    }

    if (allAreUpcoming) {
      visibleRounds.add(round);
      continue;
    }

    if (hasLiveOrOngoing) {
      if (round.roundStatus != RoundStatus.upcoming) {
        visibleRounds.add(round);
      }
      continue;
    }

    if (hasCompleted && round.roundStatus == RoundStatus.upcoming) {
      final upcomingRounds =
          rounds
              .where(
                (candidate) =>
                    candidate.roundStatus == RoundStatus.upcoming &&
                    (gamesByRound[candidate.id]?.isNotEmpty ?? false),
              )
              .toList()
            ..sort((a, b) => _compareByStart(a, b, true, roundSortMeta));

      if (upcomingRounds.isNotEmpty && upcomingRounds.first.id == round.id) {
        visibleRounds.add(round);
      }
      continue;
    }

    if (round.roundStatus != RoundStatus.upcoming) {
      visibleRounds.add(round);
    }
  }

  return visibleRounds;
}

List<GamesTourModel> _flattenVisibleGames({
  required List<GamesAppBarModel> visibleRounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  required bool isKnockoutTournament,
}) {
  final orderedGames = <GamesTourModel>[];

  for (final round in visibleRounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) {
      continue;
    }

    final isKnockoutRound =
        isKnockoutTournament &&
        (round.id.startsWith('$kKnockoutStagePrefix-') ||
            round.id.toLowerCase().startsWith('knockout-round-'));

    if (!isKnockoutRound) {
      orderedGames.addAll(roundGames);
      continue;
    }

    final matches = KnockoutMatchDetector.groupByMatches(roundGames);
    for (final matchGames in matches.values) {
      orderedGames.addAll(matchGames);
    }
  }

  return orderedGames;
}

List<GamesTourModel> _flattenGroupEventGames({
  required List<GamesAppBarModel> visibleRounds,
  required List<GamesTourModel> orderedTourGames,
}) {
  final flattened = <GamesTourModel>[];

  for (final round in visibleRounds) {
    final grouped = _groupEventGames(round.id, orderedTourGames);
    for (final games in grouped.values) {
      flattened.addAll(games);
    }
  }

  return flattened;
}

Map<String, List<GamesTourModel>> _groupEventGames(
  String roundId,
  List<GamesTourModel> games,
) {
  final grouped = <String, List<GamesTourModel>>{};
  final roundGames = games
      .where((game) => game.roundId == roundId)
      .toList(growable: false);

  for (final game in roundGames) {
    final whiteTeam =
        (game.whitePlayer.team?.isNotEmpty ?? false)
            ? game.whitePlayer.team!
            : game.whitePlayer.countryCode;
    final blackTeam =
        (game.blackPlayer.team?.isNotEmpty ?? false)
            ? game.blackPlayer.team!
            : game.blackPlayer.countryCode;
    final matchupKey = _canonicalMatchupKey(whiteTeam, blackTeam);
    grouped.putIfAbsent(matchupKey, () => <GamesTourModel>[]).add(game);
  }

  return grouped;
}

String _canonicalMatchupKey(String firstTeam, String secondTeam) {
  final normalizedFirst = firstTeam.trim().toLowerCase();
  final normalizedSecond = secondTeam.trim().toLowerCase();

  if (normalizedFirst.compareTo(normalizedSecond) <= 0) {
    return '$normalizedFirst\u0000$normalizedSecond';
  }

  return '$normalizedSecond\u0000$normalizedFirst';
}

List<GamesTourModel> _pinOnlySort(
  List<GamesTourModel> games,
  List<String> pinnedIds,
) {
  if (games.isEmpty || pinnedIds.isEmpty) {
    return games;
  }

  final sorted = List<GamesTourModel>.from(games);
  sorted.sort((a, b) {
    final aPinned = pinnedIds.contains(a.gameId);
    final bPinned = pinnedIds.contains(b.gameId);
    if (aPinned && !bPinned) return -1;
    if (!aPinned && bPinned) return 1;
    return _compareGameModelsByDisplayOrder(a, b);
  });
  return sorted;
}

RoundStatus _aggregateStageStatus(List<GamesAppBarModel> rounds) {
  if (rounds.any((round) => round.roundStatus == RoundStatus.live)) {
    return RoundStatus.live;
  }
  if (rounds.any((round) => round.roundStatus == RoundStatus.ongoing)) {
    return RoundStatus.ongoing;
  }
  if (rounds.every((round) => round.roundStatus == RoundStatus.completed)) {
    return RoundStatus.completed;
  }
  if (rounds.every((round) => round.roundStatus == RoundStatus.upcoming)) {
    return RoundStatus.upcoming;
  }
  return RoundStatus.ongoing;
}

DateTime? _resolveStageStartDate({
  required Tour tour,
  required List<GamesAppBarModel> stageRoundModels,
}) {
  final candidates = <DateTime>[...tour.dates, tour.createdAt];
  for (final round in stageRoundModels) {
    if (round.startsAt != null) {
      candidates.add(round.startsAt!);
    }
  }

  if (candidates.isEmpty) {
    return null;
  }

  return candidates.reduce(
    (latest, date) => date.isAfter(latest) ? date : latest,
  );
}

void _sortRounds(
  List<GamesAppBarModel> rounds,
  Map<String, _RoundSortMeta> roundSortMeta,
) {
  final ordered = sortRoundsForDisplay(
    rounds,
    resolveDate: (round) => _roundEventDateTime(round, roundSortMeta),
  );
  rounds
    ..clear()
    ..addAll(ordered);
}

bool _hasConfiguredStartTime(
  GamesAppBarModel round,
  Map<String, _RoundSortMeta> roundSortMeta,
) {
  final meta = roundSortMeta[round.id];
  return meta?.startsAt != null || round.startsAt != null;
}

int _compareByStart(
  GamesAppBarModel a,
  GamesAppBarModel b,
  bool ascending,
  Map<String, _RoundSortMeta> roundSortMeta,
) {
  final aStart = _roundEventDateTime(a, roundSortMeta);
  final bStart = _roundEventDateTime(b, roundSortMeta);

  int compare;
  if (aStart == null && bStart == null) {
    compare = a.name.compareTo(b.name);
  } else if (aStart == null) {
    compare = 1;
  } else if (bStart == null) {
    compare = -1;
  } else {
    compare = aStart.compareTo(bStart);
    if (compare == 0) {
      compare = a.name.compareTo(b.name);
    }
  }

  return ascending ? compare : -compare;
}

DateTime? _roundEventDateTime(
  GamesAppBarModel round,
  Map<String, _RoundSortMeta> roundSortMeta,
) {
  final meta = roundSortMeta[round.id];
  return meta?.startsAt ?? round.startsAt ?? meta?.createdAt;
}

String _formatStageName(String stagePart) {
  final lower = stagePart.toLowerCase().trim();

  if (lower.startsWith('round-')) {
    return 'Round ${lower.replaceAll('round-', '')}';
  }
  if (lower == 'quarterfinals' || lower == 'quarterfinal') {
    return 'Quarterfinals';
  }
  if (lower == 'semifinals' || lower == 'semifinal') {
    return 'Semifinals';
  }
  if (lower == 'finals' || lower == 'final') {
    return 'Finals';
  }

  return stagePart
      .split(RegExp(r'[-_\s]'))
      .where((value) => value.isNotEmpty)
      .map((value) => value[0].toUpperCase() + value.substring(1))
      .join(' ');
}

int _extractRoundNumber(String? roundSlug) {
  return _parseRoundNumber(roundSlug) ?? 0;
}

int _extractGameNumber(String? roundSlug) {
  return _parseGameNumber(roundSlug) ?? 0;
}

int? _parseRoundNumber(String? value) {
  if (value == null || value.isEmpty) return null;

  final lower = value.toLowerCase();
  if (lower.contains('final') &&
      !lower.contains('semifinal') &&
      !lower.contains('quarterfinal')) {
    return 300;
  }
  if (lower.contains('semifinal')) {
    return 200;
  }
  if (lower.contains('quarterfinal')) {
    return 100;
  }

  final match =
      RegExp(r'round[\s_\-:]*?(\d+)', caseSensitive: false).firstMatch(value) ??
      RegExp(r'\b(\d{1,3})\b').firstMatch(value);
  return match == null ? null : int.tryParse(match.group(1)!);
}

int? _parseGameNumber(String? value) {
  if (value == null || value.isEmpty) return null;
  final match = RegExp(
    r'(?:game|board|match)[\s_\-:]*?(\d+)',
    caseSensitive: false,
  ).firstMatch(value);
  return match == null ? null : int.tryParse(match.group(1)!);
}

class _RoundSortMeta {
  const _RoundSortMeta({
    required this.slug,
    required this.createdAt,
    required this.startsAt,
    required this.roundNumber,
    required this.gameNumber,
  });

  final String slug;
  final DateTime createdAt;
  final DateTime? startsAt;
  final int? roundNumber;
  final int? gameNumber;

  factory _RoundSortMeta.fromRound(Round round) {
    return _RoundSortMeta(
      slug: round.slug,
      createdAt: round.createdAt,
      startsAt: round.startsAt,
      roundNumber:
          _parseRoundNumber(round.name) ?? _parseRoundNumber(round.slug),
      gameNumber: _parseGameNumber(round.name) ?? _parseGameNumber(round.slug),
    );
  }
}
