import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourStableOrderProvider = Provider.autoDispose
    .family<GamesTourStableOrder, String>(
      (ref, tourId) => GamesTourStableOrder(),
    );

/// Keeps the first placement key observed for each game id.
///
/// Live model replacements are remapped through the retained id order in O(n).
/// Sorting only happens when a board first appears or an actual priority input
/// changes, never for clocks, moves, results, or rebuilt model instances.
class GamesTourStableOrder {
  final Map<String, _StableRoundOrder> _rounds = <String, _StableRoundOrder>{};
  Set<String> _favoriteGameIds = const <String>{};
  Set<String> _countrymanGameIds = const <String>{};
  bool _hasPrioritySnapshot = false;
  int _sortPassCount = 0;

  @visibleForTesting
  int get sortPassCount => _sortPassCount;

  /// Replaces model instances without admitting newly arrived boards. Used
  /// while their favorite/country snapshot is being refreshed so a board is
  /// inserted exactly once, directly into its final tier.
  List<GamesTourModel> remapExistingRound({
    required String roundId,
    required Iterable<GamesTourModel> games,
  }) {
    final round = _rounds[roundId];
    if (round == null) return const <GamesTourModel>[];
    final currentById = _gamesById(games);
    return <GamesTourModel>[
      for (final gameId in round.orderedGameIds)
        if (currentById[gameId] case final game?) game,
    ];
  }

  List<GamesTourModel> resolveRound({
    required String roundId,
    required Iterable<GamesTourModel> games,
    required Set<String> favoriteGameIds,
    required Set<String> countrymanGameIds,
    bool newestBoardsFirst = false,
  }) {
    final currentById = _gamesById(games);
    if (currentById.isEmpty) return const <GamesTourModel>[];

    final round = _rounds.putIfAbsent(roundId, _StableRoundOrder.new);
    final boardDirectionChanged = round.newestBoardsFirst != newestBoardsFirst;
    round.newestBoardsFirst = newestBoardsFirst;
    var addedBoard = false;
    for (final game in currentById.values) {
      if (round.boardNumberByGameId.containsKey(game.gameId)) continue;
      round.boardNumberByGameId[game.gameId] = game.boardNr;
      round.orderedGameIds.add(game.gameId);
      addedBoard = true;
    }

    final priorityChange = _replacePrioritySnapshot(
      favoriteGameIds: favoriteGameIds,
      countrymanGameIds: countrymanGameIds,
    );
    if (priorityChange.isInitial) {
      _sortAllRounds();
    } else if (priorityChange.changedGameIds.isNotEmpty) {
      final currentRoundContainsPriorityChange = round.orderedGameIds.any(
        priorityChange.changedGameIds.contains,
      );
      _sortRoundsContaining(priorityChange.changedGameIds);
      if ((addedBoard || boardDirectionChanged) &&
          !currentRoundContainsPriorityChange) {
        _sortRound(round);
      }
    } else if (addedBoard || boardDirectionChanged) {
      _sortRound(round);
    }

    return <GamesTourModel>[
      for (final gameId in round.orderedGameIds)
        if (currentById[gameId] case final game?) game,
    ];
  }

  ({bool isInitial, Set<String> changedGameIds}) _replacePrioritySnapshot({
    required Set<String> favoriteGameIds,
    required Set<String> countrymanGameIds,
  }) {
    if (_hasPrioritySnapshot &&
        setEquals(_favoriteGameIds, favoriteGameIds) &&
        setEquals(_countrymanGameIds, countrymanGameIds)) {
      return (isInitial: false, changedGameIds: const <String>{});
    }

    final isInitial = !_hasPrioritySnapshot;
    final changedGameIds = <String>{
      ..._favoriteGameIds.difference(favoriteGameIds),
      ...favoriteGameIds.difference(_favoriteGameIds),
      ..._countrymanGameIds.difference(countrymanGameIds),
      ...countrymanGameIds.difference(_countrymanGameIds),
    };
    _hasPrioritySnapshot = true;
    _favoriteGameIds = Set<String>.unmodifiable(favoriteGameIds);
    _countrymanGameIds = Set<String>.unmodifiable(countrymanGameIds);
    return (isInitial: isInitial, changedGameIds: changedGameIds);
  }

  void _sortAllRounds() {
    for (final round in _rounds.values) {
      _sortRound(round);
    }
  }

  void _sortRoundsContaining(Set<String> changedGameIds) {
    for (final round in _rounds.values) {
      if (round.orderedGameIds.any(changedGameIds.contains)) {
        _sortRound(round);
      }
    }
  }

  void _sortRound(_StableRoundOrder round) {
    if (round.orderedGameIds.length < 2) return;
    round.orderedGameIds.sort(
      (a, b) => compareTournamentGameOrder(
        aGameId: a,
        aBoardNumber: round.boardNumberByGameId[a],
        bGameId: b,
        bBoardNumber: round.boardNumberByGameId[b],
        favoriteGameIds: _favoriteGameIds,
        countrymanGameIds: _countrymanGameIds,
        newestBoardsFirst: round.newestBoardsFirst,
      ),
    );
    _sortPassCount++;
  }
}

List<GamesTourModel> resolveTournamentRoundPresentationOrder({
  required GamesTourStableOrder? stableOrder,
  required String roundId,
  required Iterable<GamesTourModel> games,
  required bool isSearchMode,
  required bool hasResolvedAutoPins,
  required bool isRefreshingAutoPins,
  required Set<String> favoriteGameIds,
  required Set<String> countrymanGameIds,
  bool newestBoardsFirst = false,
}) {
  if (isSearchMode || !hasResolvedAutoPins || stableOrder == null) {
    return sortTournamentRoundGamesByPriority(
      games: games,
      newestBoardsFirst: newestBoardsFirst,
    );
  }
  if (isRefreshingAutoPins) {
    return stableOrder.remapExistingRound(roundId: roundId, games: games);
  }
  return stableOrder.resolveRound(
    roundId: roundId,
    games: games,
    favoriteGameIds: favoriteGameIds,
    countrymanGameIds: countrymanGameIds,
    newestBoardsFirst: newestBoardsFirst,
  );
}

Map<String, GamesTourModel> _gamesById(Iterable<GamesTourModel> games) {
  final gamesById = <String, GamesTourModel>{};
  for (final game in games) {
    gamesById.putIfAbsent(game.gameId, () => game);
  }
  return gamesById;
}

class _StableRoundOrder {
  final Map<String, int?> boardNumberByGameId = <String, int?>{};
  final List<String> orderedGameIds = <String>[];
  bool newestBoardsFirst = false;
}

List<GamesTourModel> sortTournamentRoundGamesByPriority({
  required Iterable<GamesTourModel> games,
  Set<String> favoriteGameIds = const <String>{},
  Set<String> countrymanGameIds = const <String>{},
  bool newestBoardsFirst = false,
}) {
  final sorted = games.toList(growable: false);
  final priorityByGameId = <String, int>{
    for (final game in sorted)
      game.gameId: _priorityForGame(
        game.gameId,
        favoriteGameIds,
        countrymanGameIds,
      ),
  };
  sorted.sort((a, b) {
    final priorityOrder = priorityByGameId[a.gameId]!.compareTo(
      priorityByGameId[b.gameId]!,
    );
    if (priorityOrder != 0) return priorityOrder;
    return compareTournamentBoardAndId(
      aGameId: a.gameId,
      aBoardNumber: a.boardNr,
      bGameId: b.gameId,
      bBoardNumber: b.boardNr,
      newestBoardsFirst: newestBoardsFirst,
    );
  });
  return sorted;
}

int compareTournamentGameOrder({
  required String aGameId,
  required int? aBoardNumber,
  required String bGameId,
  required int? bBoardNumber,
  required Set<String> favoriteGameIds,
  required Set<String> countrymanGameIds,
  bool newestBoardsFirst = false,
}) {
  final priorityOrder = _priorityForGame(
    aGameId,
    favoriteGameIds,
    countrymanGameIds,
  ).compareTo(_priorityForGame(bGameId, favoriteGameIds, countrymanGameIds));
  if (priorityOrder != 0) return priorityOrder;
  return compareTournamentBoardAndId(
    aGameId: aGameId,
    aBoardNumber: aBoardNumber,
    bGameId: bGameId,
    bBoardNumber: bBoardNumber,
    newestBoardsFirst: newestBoardsFirst,
  );
}

int compareTournamentBoardAndId({
  required String aGameId,
  required int? aBoardNumber,
  required String bGameId,
  required int? bBoardNumber,
  bool newestBoardsFirst = false,
}) {
  if (aBoardNumber != null && bBoardNumber != null) {
    final boardOrder =
        newestBoardsFirst
            ? bBoardNumber.compareTo(aBoardNumber)
            : aBoardNumber.compareTo(bBoardNumber);
    if (boardOrder != 0) return boardOrder;
  } else if (aBoardNumber != null) {
    return -1;
  } else if (bBoardNumber != null) {
    return 1;
  }
  return aGameId.compareTo(bGameId);
}

int _priorityForGame(
  String gameId,
  Set<String> favoriteGameIds,
  Set<String> countrymanGameIds,
) {
  if (favoriteGameIds.contains(gameId)) return 0;
  if (countrymanGameIds.contains(gameId)) return 1;
  return 2;
}

/// Snapshot-based "Focus on live games" ordering.
///
/// Boards whose ids were live at activation ([liveGameIdsAtSnapshot]) bubble
/// above the rest while preserving relative order within each group. Callers
/// freeze [liveGameIdsAtSnapshot] for the whole focus session so later status
/// changes do not reshuffle; a new snapshot is only taken on re-activation.
///
/// All boards remain present — this never filters finished games out.
List<GamesTourModel> applyLiveFocusOrder({
  required Iterable<GamesTourModel> games,
  required Set<String> liveGameIdsAtSnapshot,
}) {
  if (liveGameIdsAtSnapshot.isEmpty) {
    return List<GamesTourModel>.of(games, growable: false);
  }

  final live = <GamesTourModel>[];
  final rest = <GamesTourModel>[];
  for (final game in games) {
    if (liveGameIdsAtSnapshot.contains(game.gameId)) {
      live.add(game);
    } else {
      rest.add(game);
    }
  }
  if (live.isEmpty || rest.isEmpty) {
    return List<GamesTourModel>.of(games, growable: false);
  }
  return <GamesTourModel>[...live, ...rest];
}

/// Game ids treated as live for a focus-mode snapshot.
///
/// Uses [GamesTourModel.effectiveGameStatus] so clock-flagged boards that the
/// UI already treats as finished are not snapped as live.
Set<String> liveGameIdsForFocusSnapshot(Iterable<GamesTourModel> games) {
  return <String>{
    for (final game in games)
      if (!game.effectiveGameStatus.isFinished) game.gameId,
  };
}
