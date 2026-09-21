import 'package:chessever2/repository/supabase/tour/tour.dart';
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
  Map<String, DateTime?> roundStartTimesById = const <String, DateTime?>{},
  Map<String, List<TournamentPlayer>> sourceStandingsByTourId = const {},
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
            ? _orderMatchesByRecencyDesc(
              KnockoutMatchDetector.groupByMatches(roundGames),
              roundStartTimesById,
            )
            : const <String, List<GamesTourModel>>{};
    // Boards inside a matchup render latest-first (live on top). The
    // chronological grouping in `matches` is kept for the match headers,
    // whose player naming and score orientation key off game 1.
    final displayMatches =
        isKnockoutRound
            ? <String, List<GamesTourModel>>{
              for (final entry in matches.entries)
                entry.key: KnockoutMatchDetector.orderMatchGamesLatestFirst(
                  entry.value,
                ),
            }
            : const <String, List<GamesTourModel>>{};
    if (isKnockoutRound) {
      matchGroupsByRound[round.id] = displayMatches;
    }

    final orderedRoundGames =
        isKnockoutRound
            ? <GamesTourModel>[
              for (final matchGames in displayMatches.values) ...matchGames,
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
      final chronologicalGames = matchEntry.value;
      final matchGames = displayMatches[matchKey]!;
      entries.add(
        GamesTourMatchHeaderEntry(
          roundId: round.id,
          matchHeader: KnockoutMatchDetector.createMatchHeader(
            matchKey,
            chronologicalGames,
            playedAt: matchupRecency(chronologicalGames, roundStartTimesById),
            sourceStandingsByTourId: sourceStandingsByTourId,
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

/// Orders the collapsed matchups of a knockout stage so the most recently
/// played matchup card sits on top (descending datetime), matching how a live
/// bracket reads. Matchups with a board still being played outrank everything:
/// in a fast bracket some board finishes every few minutes, and a matchup
/// whose player is mid-think must not keep sinking below just-finished
/// matchups. Below the live tier, each matchup's recency is the LATEST of
/// every signal we hold, because no single one survives all ingestion shapes:
///
/// - source round `starts_at` — the only time-precise signal on bulk-imported
///   finished rounds (their `lastMoveTime` is null and play dates are
///   date-granular, so two matchups on the same day would otherwise tie);
/// - game `lastMoveTime` — actual play time on live-streamed rounds, which
///   outranks a stale scheduled start when a matchup is postponed and the
///   broadcast's `starts_at` is never corrected;
/// - game [GamesTourModel.bucketDate] — date-granular last resort.
///
/// Taking the max is safe: date-only fallbacks sit at midnight and can never
/// beat a same-day scheduled start, while a genuinely later actual-play date
/// always wins. Genuinely undated matchups sink to the bottom. Returns an
/// insertion-ordered map so every downstream consumer (ordered games, match
/// headers, index arithmetic) shares one order.
Map<String, List<GamesTourModel>> _orderMatchesByRecencyDesc(
  Map<String, List<GamesTourModel>> matches,
  Map<String, DateTime?> roundStartTimesById,
) {
  if (matches.length <= 1) return matches;

  final hasLiveBoardByKey = <String, bool>{
    for (final entry in matches.entries)
      entry.key: entry.value.any(
        (game) => !game.effectiveGameStatus.isFinished,
      ),
  };
  final entries =
      matches.entries.toList()..sort((a, b) {
        final aLive = hasLiveBoardByKey[a.key]!;
        final bLive = hasLiveBoardByKey[b.key]!;
        if (aLive != bLive) return aLive ? -1 : 1;
        final aDate = matchupRecency(a.value, roundStartTimesById);
        final bDate = matchupRecency(b.value, roundStartTimesById);
        if (aDate == null && bDate == null) return a.key.compareTo(b.key);
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        final byDate = bDate.compareTo(aDate);
        return byDate != 0 ? byDate : a.key.compareTo(b.key);
      });

  return <String, List<GamesTourModel>>{
    for (final entry in entries) entry.key: entry.value,
  };
}

/// The single recency signal for one matchup: the latest of the source round
/// `starts_at`, actual per-game `lastMoveTime`, and date-granular
/// [GamesTourModel.bucketDate]. Both the collapsed-stage sort and the
/// matchup card's played-at label read from here so what the card shows is
/// exactly what the ordering used.
DateTime? matchupRecency(
  List<GamesTourModel> games,
  Map<String, DateTime?> roundStartTimesById,
) {
  DateTime? latest;
  void consider(DateTime? candidate) {
    if (candidate == null) return;
    final current = latest;
    if (current == null || candidate.isAfter(current)) latest = candidate;
  }

  for (final game in games) {
    consider(roundStartTimesById[game.roundId]);
    consider(game.lastMoveTime);
    consider(game.bucketDate);
  }
  return latest;
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
    // Focus-on-live is sort-only; finished boards stay visible. Ordering is
    // applied upstream from each board's current effective status.
    case GameDisplayMode.hideFinishedGames:
      return true;
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
