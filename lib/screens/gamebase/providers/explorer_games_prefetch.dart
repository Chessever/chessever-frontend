import 'dart:async';

import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'gamebase_explorer_state.dart';
import 'gamebase_providers.dart';

/// Move rows warmed per position, taken from the top of the visible order.
const int kExplorerGamesPrefetchRows = 6;

/// Warm requests allowed in flight at once. The backend serves these from the
/// same connection pool as the aggregates the panel is still drawing, so this
/// stays deliberately small.
const int kExplorerGamesPrefetchConcurrency = 2;

/// Warmed entries retained before the oldest are released.
const int kExplorerGamesPrefetchRetained = 24;

/// Page size the sheet asks for. Must match `_PositionGamesSheetState._pageSize`.
const int kExplorerGamesPrefetchPageSize = 20;

/// Queries to warm for [aggregates], in the order the rows are displayed.
///
/// The trailing entry is the totals ('∑') row, which carries no `uci` and so
/// asks for every game that reached this position.
List<GamebasePositionGamesQuery> buildExplorerGamesPrefetchQueries({
  required String fen,
  required List<String> moves,
  required List<MoveAggregate> aggregates,
  required GamebaseFilters filters,
  int rows = kExplorerGamesPrefetchRows,
}) {
  if (fen.trim().isEmpty || aggregates.isEmpty) {
    return const <GamebasePositionGamesQuery>[];
  }

  GamebasePositionGamesQuery queryFor(String? uci) =>
      GamebasePositionGamesQuery.fromFilters(
        fen: fen,
        filters: filters,
        moves: moves,
        uci: uci,
        pageNumber: 0,
        pageSize: kExplorerGamesPrefetchPageSize,
      );

  final queries = <GamebasePositionGamesQuery>[];
  for (final aggregate in aggregates.take(rows)) {
    final uci = aggregate.uci.trim();
    if (uci.isEmpty) continue;
    queries.add(queryFor(uci));
  }
  queries.add(queryFor(null));
  return queries;
}

/// Warms the games list behind the explorer's "Games" chips.
///
/// Tapping a chip opens [PositionGamesSheet], which reads the very same
/// `positionGamesProvider` family entry this file warms. That request is far
/// from free on the backend: a player-filtered position lookup joins the
/// player's whole game set against a multi-gigabyte position index, so it runs
/// ~1.5s warm and has been measured past 40s cold. Waiting for the tap to
/// start it is what leaves the sheet on a bare spinner.
///
/// Two details matter and both have bitten before:
///
/// * `positionGamesProvider` is `autoDispose`. A fire-and-forget `read` is
///   thrown away the moment the future settles, so the tap re-fetches from
///   scratch and the warm-up bought nothing. Every warmed query therefore
///   holds a real [ProviderSubscription] until it is evicted.
/// * The warmed query must be **identical** to the one the sheet builds —
///   same fen, move line, uci, filters, sort and page size — or it hashes to a
///   different family entry and, again, buys nothing.
///
/// A failed warm is dropped rather than kept, so a transient network error can
/// never be pinned in front of the sheet as an instant error state.
class ExplorerGamesPrefetcher {
  ExplorerGamesPrefetcher(this._ref);

  final Ref _ref;

  /// Insertion-ordered so eviction can drop the least recently warmed entry.
  final Map<
    GamebasePositionGamesQuery,
    ProviderSubscription<AsyncValue<GamebaseSearchQueryResponse>>
  >
  _warm = {};
  final Set<GamebasePositionGamesQuery> _inFlight = {};
  final List<GamebasePositionGamesQuery> _queue = [];

  /// Warm [queries], replacing anything still queued from a previous position.
  ///
  /// Requests already in flight are left alone — they are nearly always the
  /// row the reader just stepped through, and cancelling them mid-navigation
  /// would throw away the work that makes the *next* tap instant.
  void warm(List<GamebasePositionGamesQuery> queries) {
    _queue
      ..clear()
      ..addAll(
        queries.where(
          (query) => !_warm.containsKey(query) && !_inFlight.contains(query),
        ),
      );
    _pump();
  }

  /// Whether [query] has already settled and would answer the sheet instantly.
  bool isWarm(GamebasePositionGamesQuery query) =>
      _warm.containsKey(query) && !_inFlight.contains(query);

  void _pump() {
    while (_inFlight.length < kExplorerGamesPrefetchConcurrency &&
        _queue.isNotEmpty) {
      final query = _queue.removeAt(0);
      if (_warm.containsKey(query) || _inFlight.contains(query)) continue;
      unawaited(_fetch(query));
    }
  }

  Future<void> _fetch(GamebasePositionGamesQuery query) async {
    _inFlight.add(query);
    // The listener is what keeps the autoDispose entry resident; its callback
    // is deliberately empty because the awaited future below is the result.
    _warm[query] = _ref.listen<AsyncValue<GamebaseSearchQueryResponse>>(
      positionGamesProvider(query),
      (_, __) {},
    );
    _evict();
    try {
      await _ref.read(positionGamesProvider(query).future);
    } catch (_) {
      // Let the tap retry rather than serving it a cached failure.
      _warm.remove(query)?.close();
    } finally {
      _inFlight.remove(query);
      _pump();
    }
  }

  void _evict() {
    if (_warm.length <= kExplorerGamesPrefetchRetained) return;
    for (final query in _warm.keys.toList(growable: false)) {
      if (_warm.length <= kExplorerGamesPrefetchRetained) break;
      if (_inFlight.contains(query)) continue;
      _warm.remove(query)?.close();
    }
  }

  void dispose() {
    _queue.clear();
    for (final subscription in _warm.values) {
      subscription.close();
    }
    _warm.clear();
  }
}

/// App-lifetime warmer for the explorer games sheet.
///
/// Deliberately not `autoDispose`: the whole point is to outlive the move-row
/// widget that requested the warm-up and still be holding the result when the
/// sheet asks for it.
final explorerGamesPrefetchProvider = Provider<ExplorerGamesPrefetcher>((ref) {
  final prefetcher = ExplorerGamesPrefetcher(ref);
  ref.onDispose(prefetcher.dispose);
  return prefetcher;
});
