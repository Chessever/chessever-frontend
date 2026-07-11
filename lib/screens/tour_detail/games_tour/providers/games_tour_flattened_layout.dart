import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// The exact, flattened structure painted by the regular tournament Games
/// list. Dropdown jumps, visible-round tracking, and game anchoring all consume
/// this same model so headers and collapsed knockout matches cannot make their
/// index arithmetic drift apart.
@immutable
class GamesTourFlattenedLayout {
  const GamesTourFlattenedLayout({
    required this.entries,
    required this.orderedGames,
    required this.matchGroupsByRound,
    required this.roundHeaderIndices,
    required this.gameItemIndices,
  });

  static const empty = GamesTourFlattenedLayout(
    entries: <GamesTourLayoutEntry>[],
    orderedGames: <GamesTourModel>[],
    matchGroupsByRound: <String, Map<String, List<GamesTourModel>>>{},
    roundHeaderIndices: <String, int>{},
    gameItemIndices: <String, int>{},
  );

  final List<GamesTourLayoutEntry> entries;
  final List<GamesTourModel> orderedGames;
  final Map<String, Map<String, List<GamesTourModel>>> matchGroupsByRound;
  final Map<String, int> roundHeaderIndices;
  final Map<String, int> gameItemIndices;

  int get itemCount => entries.length;

  GamesTourLayoutEntry? entryAt(int index) {
    if (index < 0 || index >= entries.length) return null;
    return entries[index];
  }

  int? roundHeaderIndex(String roundId) => roundHeaderIndices[roundId];

  int? itemIndexForGameId(String gameId) => gameItemIndices[gameId];

  String? firstGameIdAt(int itemIndex) {
    final entry = entryAt(itemIndex);
    return entry is GamesTourGameRowEntry ? entry.game1.gameId : null;
  }

  String? roundIdAt(int itemIndex) => entryAt(itemIndex)?.roundId;

  int? itemIndexForOrderedGameIndex(int gameIndex) {
    if (gameIndex < 0 || gameIndex >= orderedGames.length) return null;
    return itemIndexForGameId(orderedGames[gameIndex].gameId);
  }
}

sealed class GamesTourLayoutEntry {
  const GamesTourLayoutEntry({required this.roundId});

  final String? roundId;
}

final class GamesTourMatchFormatHeaderEntry extends GamesTourLayoutEntry {
  const GamesTourMatchFormatHeaderEntry(this.matchHeader)
    : super(roundId: null);

  final MatchHeaderModel matchHeader;
}

final class GamesTourRoundHeaderEntry extends GamesTourLayoutEntry {
  GamesTourRoundHeaderEntry({required this.round, required this.roundGames})
    : super(roundId: round.id);

  final GamesAppBarModel round;
  final List<GamesTourModel> roundGames;
}

final class GamesTourMatchHeaderEntry extends GamesTourLayoutEntry {
  const GamesTourMatchHeaderEntry({
    required String roundId,
    required this.matchHeader,
  }) : super(roundId: roundId);

  final MatchHeaderModel matchHeader;
}

final class GamesTourGameRowEntry extends GamesTourLayoutEntry {
  const GamesTourGameRowEntry({
    required String roundId,
    required this.game1,
    required this.globalIndex1,
    this.game2,
    this.globalIndex2,
    this.fixedBottomSide1,
    this.fixedBottomSide2,
    required this.isLastInSection,
  }) : super(roundId: roundId);

  final GamesTourModel game1;
  final int globalIndex1;
  final GamesTourModel? game2;
  final int? globalIndex2;
  final Side? fixedBottomSide1;
  final Side? fixedBottomSide2;
  final bool isLastInSection;
}

GamesTourFlattenedLayout buildGamesTourFlattenedLayout({
  required List<GamesAppBarModel> rounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  required GamesListViewMode mode,
  required Map<String, bool> matchExpansionState,
  required Map<String, bool> roundExpansionState,
  required bool isKnockoutTournament,
  required GameDisplayMode displayMode,
  bool isSearchMode = false,
  MatchHeaderModel? matchFormatHeader,
}) {
  final entries = <GamesTourLayoutEntry>[];
  final orderedGames = <GamesTourModel>[];
  final matchGroupsByRound = <String, Map<String, List<GamesTourModel>>>{};
  final roundHeaderIndices = <String, int>{};
  final gameItemIndices = <String, int>{};
  final isGrid = mode == GamesListViewMode.chessBoardGrid;

  if (matchFormatHeader != null) {
    entries.add(GamesTourMatchFormatHeaderEntry(matchFormatHeader));
  }

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;

    final isKnockoutRound = _isKnockoutRound(isKnockoutTournament, round);
    final matches =
        isKnockoutRound
            ? KnockoutMatchDetector.groupByMatches(roundGames)
            : const <String, List<GamesTourModel>>{};
    if (isKnockoutRound) {
      matchGroupsByRound[round.id] = matches;
    }

    final orderedRoundGames =
        isKnockoutRound
            ? <GamesTourModel>[
              for (final matchGames in matches.values) ...matchGames,
            ]
            : roundGames;
    final roundStartIndex = orderedGames.length;
    orderedGames.addAll(orderedRoundGames);

    roundHeaderIndices[round.id] = entries.length;
    entries.add(
      GamesTourRoundHeaderEntry(round: round, roundGames: roundGames),
    );

    final isRoundExpanded =
        isSearchMode ? true : (roundExpansionState[round.id] ?? true);
    if (!isRoundExpanded) continue;

    if (!isKnockoutRound) {
      _appendGameRows(
        entries: entries,
        gameItemIndices: gameItemIndices,
        roundId: round.id,
        games: roundGames,
        globalIndices: List<int>.generate(
          roundGames.length,
          (index) => roundStartIndex + index,
          growable: false,
        ),
        isGrid: isGrid,
      );
      continue;
    }

    var matchOffset = 0;
    for (final matchEntry in matches.entries) {
      final matchKey = matchEntry.key;
      final matchGames = matchEntry.value;
      entries.add(
        GamesTourMatchHeaderEntry(
          roundId: round.id,
          matchHeader: KnockoutMatchDetector.createMatchHeader(
            matchKey,
            matchGames,
          ),
        ),
      );

      final isMatchExpanded =
          isSearchMode
              ? true
              : resolveMatchExpansionState(matchExpansionState, matchKey);
      if (isMatchExpanded) {
        final visibleGames = <GamesTourModel>[];
        final globalIndices = <int>[];
        for (var index = 0; index < matchGames.length; index++) {
          final game = matchGames[index];
          if (!_shouldShowGame(displayMode, game)) continue;
          visibleGames.add(game);
          globalIndices.add(roundStartIndex + matchOffset + index);
        }

        _appendGameRows(
          entries: entries,
          gameItemIndices: gameItemIndices,
          roundId: round.id,
          games: visibleGames,
          globalIndices: globalIndices,
          isGrid: isGrid,
          fixedBottomPlayerName: _highestRatedPlayerName(matchGames),
        );
      }

      matchOffset += matchGames.length;
    }
  }

  return GamesTourFlattenedLayout(
    entries: List<GamesTourLayoutEntry>.unmodifiable(entries),
    orderedGames: List<GamesTourModel>.unmodifiable(orderedGames),
    matchGroupsByRound:
        Map<String, Map<String, List<GamesTourModel>>>.unmodifiable(
          matchGroupsByRound,
        ),
    roundHeaderIndices: Map<String, int>.unmodifiable(roundHeaderIndices),
    gameItemIndices: Map<String, int>.unmodifiable(gameItemIndices),
  );
}

void _appendGameRows({
  required List<GamesTourLayoutEntry> entries,
  required Map<String, int> gameItemIndices,
  required String roundId,
  required List<GamesTourModel> games,
  required List<int> globalIndices,
  required bool isGrid,
  String? fixedBottomPlayerName,
}) {
  assert(games.length == globalIndices.length);
  final step = isGrid ? 2 : 1;
  for (var index = 0; index < games.length; index += step) {
    final secondIndex = index + 1;
    final itemIndex = entries.length;
    final game1 = games[index];
    final game2 =
        isGrid && secondIndex < games.length ? games[secondIndex] : null;
    entries.add(
      GamesTourGameRowEntry(
        roundId: roundId,
        game1: game1,
        globalIndex1: globalIndices[index],
        fixedBottomSide1: _sideForPlayer(game1, fixedBottomPlayerName),
        game2: game2,
        globalIndex2: game2 == null ? null : globalIndices[secondIndex],
        fixedBottomSide2:
            game2 == null ? null : _sideForPlayer(game2, fixedBottomPlayerName),
        isLastInSection: index + step >= games.length,
      ),
    );
    gameItemIndices[game1.gameId] = itemIndex;
    if (game2 != null) gameItemIndices[game2.gameId] = itemIndex;
  }
}

bool _isKnockoutRound(bool isKnockoutTournament, GamesAppBarModel round) {
  if (!isKnockoutTournament) return false;
  final id = round.id.toLowerCase();
  return id.startsWith('knockout-stage-') || id.startsWith('knockout-round-');
}

bool _shouldShowGame(GameDisplayMode mode, GamesTourModel game) {
  switch (mode) {
    case GameDisplayMode.hideFinishedGames:
      return !game.gameStatus.isFinished;
    case GameDisplayMode.showfinishedGame:
      return game.gameStatus.isFinished;
    case GameDisplayMode.all:
      return true;
  }
}

String? _highestRatedPlayerName(List<GamesTourModel> matchGames) {
  if (matchGames.isEmpty) return null;

  final playersByName = <String, ({String name, int rating, int order})>{};
  var order = 0;

  void addPlayer(PlayerCard player) {
    final key = _normalizePlayerName(player.name);
    if (key.isEmpty) return;

    final current = playersByName[key];
    if (current == null) {
      playersByName[key] = (
        name: player.name,
        rating: player.rating,
        order: order++,
      );
      return;
    }

    if (player.rating > current.rating) {
      playersByName[key] = (
        name: player.name,
        rating: player.rating,
        order: current.order,
      );
    }
  }

  for (final game in matchGames) {
    addPlayer(game.whitePlayer);
    addPlayer(game.blackPlayer);
  }
  if (playersByName.isEmpty) return null;

  final players =
      playersByName.values.toList()..sort((left, right) {
        final rating = right.rating.compareTo(left.rating);
        return rating != 0 ? rating : left.order.compareTo(right.order);
      });
  return players.first.name;
}

Side? _sideForPlayer(GamesTourModel game, String? playerName) {
  final normalized = _normalizePlayerName(playerName);
  if (normalized.isEmpty) return null;
  if (_normalizePlayerName(game.whitePlayer.name) == normalized) {
    return Side.white;
  }
  if (_normalizePlayerName(game.blackPlayer.name) == normalized) {
    return Side.black;
  }
  return null;
}

String _normalizePlayerName(String? name) => (name ?? '').trim().toLowerCase();
