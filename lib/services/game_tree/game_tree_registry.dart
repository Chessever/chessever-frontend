import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';

/// The opening indexes the explorer may read, by scope id, answering its
/// tree, position-games and game lookups for `prep:<scope>` ids.
///
/// A scope is a My Prep profile (its id) or a built collection tree
/// (`tree-…`). Scope ids never contain a colon, so a game id
/// `prep:<scope>:<row>` splits cleanly.
abstract final class GameTreeRegistry {
  static final Map<String, GameTreeStore> _stores = {};
  static final Map<String, String> _labels = {};

  /// The explorer player id for a scope.
  static String playerIdFor(String scopeId) => 'prep:$scopeId';

  static GameTreeStore? storeFor(String scopeId) {
    final store = _stores[scopeId];
    return store == null || store.isClosed ? null : store;
  }

  /// Makes [store] answer the explorer, replacing (and closing) an older
  /// store for the same scope. [sourceLabels] names each source kind in the
  /// games list (`lichess` → `Lichess`); a game without one shows its event.
  static void register(
    GameTreeStore store, {
    Map<String, String> sourceLabels = const {},
  }) {
    final previous = _stores[store.scopeId];
    if (previous != null && !identical(previous, store)) previous.close();
    _stores[store.scopeId] = store;
    _labels.addAll(sourceLabels);
    LocalPlayerOpeningTrees.resolver = _tree;
    GamebaseLocalGames.gameResolver = _game;
    GamebaseLocalGames.positionResolver = _positionGames;
  }

  static void unregister(String scopeId) {
    _stores.remove(scopeId)?.close();
  }

  static String? _scopeOfPlayer(String playerId) =>
      playerId.startsWith('prep:') ? playerId.substring(5) : null;

  static PlayerOpeningTreeIndex? _tree(String playerId) {
    final scope = _scopeOfPlayer(playerId);
    return scope == null ? null : storeFor(scope)?.tree;
  }

  static GamebaseGameWithPgn? _game(String id) {
    final parts = id.split(':');
    if (parts.length != 3 || parts.first != 'prep') return null;
    final store = storeFor(parts[1]);
    final row = int.tryParse(parts[2]);
    if (store == null || row == null) return null;
    final found = store.game(row);
    if (found == null) return null;
    final (game, pgn) = found;
    return GamebaseGameWithPgn(
      id: id,
      date: treeDateTime(game.date) ?? DateTime.fromMillisecondsSinceEpoch(0),
      result: switch (game.result) {
        0 => GameResult.whiteWins,
        1 => GameResult.blackWins,
        _ => GameResult.draw,
      },
      timeControl: switch (TreeSpeed.explorerClock(game.speed)) {
        2 => TimeControl.rapid,
        3 => TimeControl.classical,
        _ => TimeControl.blitz,
      },
      pgn: pgn,
      eco: game.eco,
      opening: game.opening,
      whiteName: game.white,
      blackName: game.black,
      whiteElo: game.whiteElo,
      blackElo: game.blackElo,
    );
  }

  static Future<GamebaseSearchQueryResponse>? _positionGames(
    GamebaseLocalPositionQuery query,
  ) {
    final scope = _scopeOfPlayer(query.playerId);
    final store = scope == null ? null : storeFor(scope);
    if (store == null) return null;
    return () async {
      final page = await store.positionGames(
        GameTreePositionQuery(
          fen: query.fen,
          uci: query.uci,
          side: switch (query.color?.toLowerCase()) {
            'white' => 1,
            'black' => 2,
            _ => null,
          },
          clock: switch (query.timeControl) {
            TimeControl.blitz => 1,
            TimeControl.rapid => 2,
            TimeControl.classical => 3,
            _ => null,
          },
          sort: switch (query.sortBy) {
            GamebaseSortField.whiteElo => 'whiteElo',
            GamebaseSortField.blackElo => 'blackElo',
            GamebaseSortField.avgElo => 'avgElo',
            GamebaseSortField.date => 'date',
          },
          descending: query.sortDirection != GamebaseSortDirection.asc,
          page: query.pageNumber,
          pageSize: query.pageSize,
        ),
      );
      final start = query.pageNumber * query.pageSize;
      return GamebaseSearchQueryResponse(
        status: 'success',
        data: [
          for (final (game, fen, last) in page.games)
            {
              'id': store.gameId(game.id),
              'date': treeDateTime(game.date)?.toIso8601String(),
              'result': treeResultText(game.result),
              'timeControl': switch (TreeSpeed.explorerClock(game.speed)) {
                1 => 'BLITZ',
                2 => 'RAPID',
                3 => 'CLASSICAL',
                _ => null,
              },
              'eco': game.eco,
              'opening': game.opening,
              'event': _labels[game.source] ?? game.event,
              'white': game.white,
              'black': game.black,
              'whiteElo': game.whiteElo,
              'blackElo': game.blackElo,
              'fen': fen,
              'lastMove': last,
            },
        ],
        metadata: GamebasePaginationMetadata(
          pageNumber: query.pageNumber,
          pageSize: query.pageSize,
          totalCount: page.total,
          hasMoreValue: start + query.pageSize < page.total,
        ),
      );
    }();
  }
}
