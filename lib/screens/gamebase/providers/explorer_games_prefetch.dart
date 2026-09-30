import 'dart:async';
import 'dart:collection';

import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'explorer_games_cache.dart';
import 'gamebase_explorer_state.dart';
import 'gamebase_providers.dart';

/// Move rows warmed from the network per position, from the top of the
/// visible order. Saved pages for every row are still read from disk.
const int kExplorerGamesPrefetchRows = 6;

/// Warm every row actually built on screen instead of the top
/// [kExplorerGamesPrefetchRows].
///
/// Off until the server's index for rare moves in the first six plies is
/// live: before it, a rare move there can cost the server 8-40 s cold, and
/// fanning those out for every row would starve the requests readers wait on.
const bool kExplorerGamesPrefetchEveryRow = false;

/// Warm requests allowed in flight at once for the position being read. They
/// share the backend pool with the aggregates the panel is still drawing, so
/// this stays small. A tap-down head start ([ExplorerGamesPrefetcher.warmNow])
/// does not wait for a slot.
const int kExplorerGamesPrefetchConcurrency = 3;

/// Warm requests allowed in flight at once across every position, counting
/// ones still running for positions the reader has left. Those are never
/// cancelled (the server finishes the query and caches it either way), so
/// they do not take the position being read's
/// [kExplorerGamesPrefetchConcurrency] slots, only room under this ceiling:
/// one step away from a slow position still leaves the next one all three.
const int kExplorerGamesPrefetchInFlightCeiling = 6;

/// Warmed entries held before the least recently warmed are released.
const int kExplorerGamesPrefetchRetained = 64;

/// Most requests ever waiting for a slot. Newest first; the oldest fall off.
const int kExplorerGamesPrefetchQueueLimit = 16;

/// Page size the sheet asks for.
const int kExplorerGamesPrefetchPageSize = kExplorerGamesSheetPageSize;

/// A held page warmed longer ago than this is fetched again the next time its
/// position is warmed. Younger ones already answer the tap (and the sheet
/// re-checks anything older than [kExplorerGamesFreshFor] itself).
const Duration kExplorerGamesRewarmAfter = Duration(minutes: 10);

/// Whether the move table builds its '∑' totals row for [aggregates]: only
/// when there is more than one move to sum.
bool explorerShowsTotalsRow(List<MoveAggregate> aggregates) =>
    aggregates.length > 1;

/// The '∑' row's query: every game that reached this position, no `uci`.
GamebasePositionGamesQuery explorerGamesTotalsQuery({
  required String fen,
  required List<String> moves,
  required GamebaseFilters filters,
}) => GamebasePositionGamesQuery.sheetPage(
  fen: fen,
  filters: filters,
  moves: moves,
);

/// Queries to warm for [aggregates]: the '∑' totals row first (it answers for
/// the whole position), then up to [rows] move rows in the order they are
/// displayed.
///
/// '∑' only when the table builds its row, which it does for two moves or
/// more. With one move (the usual case deep in a game) nothing on screen
/// opens it, and past the indexed window it is one of the server's slowest
/// queries.
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

  final queries = <GamebasePositionGamesQuery>[
    if (explorerShowsTotalsRow(aggregates))
      explorerGamesTotalsQuery(fen: fen, moves: moves, filters: filters),
  ];
  for (final aggregate in aggregates.take(rows)) {
    final uci = aggregate.uci.trim();
    if (uci.isEmpty) continue;
    queries.add(
      GamebasePositionGamesQuery.sheetPage(
        fen: fen,
        filters: filters,
        moves: moves,
        uci: uci,
      ),
    );
  }
  return queries;
}

/// Identity of the move-row warm-up for a position: it changes whenever the
/// rows would warm different queries. The move line is part of it: a
/// transposition onto the same FEN asks with a different line, so without it
/// the sheet's query would never match what was warmed.
int explorerGamesPrefetchSignature({
  required String fen,
  required List<String> moves,
  required GamebaseFilters filters,
  required List<MoveAggregate> aggregates,
}) => Object.hash(
  fen,
  Object.hashAll(moves),
  filters,
  Object.hashAll(aggregates.map((aggregate) => aggregate.uci)),
);

typedef _WarmSubscription =
    ProviderSubscription<AsyncValue<GamebaseSearchQueryResponse>>;

/// Warms the games list behind the explorer's "Games" chips.
///
/// Tapping a chip opens `PositionGamesSheet`, which reads the very same
/// `positionGamesProvider` family entry this file warms, and the saved first
/// page [ExplorerGamesCache] holds under the same wire request. Starting the
/// request on the tap is what leaves a sheet on a bare spinner, so it starts
/// when the row is on screen instead.
///
/// * Every warmed query holds a [ProviderSubscription] until evicted, so the
///   entry is resident when the tap arrives.
/// * The warmed query must be **identical** to the one the sheet builds, so
///   every caller builds it with [GamebasePositionGamesQuery.sheetPage].
/// * The queue only ever serves the position being read: warming a position
///   drops everything still waiting for another one, puts the new work in
///   front, and is capped at [kExplorerGamesPrefetchQueueLimit]. Rows that
///   leave the screen take their waiting work with them ([cancel]).
/// * Slots are counted per position: up to [kExplorerGamesPrefetchConcurrency]
///   for the position being read, within [kExplorerGamesPrefetchInFlightCeiling]
///   overall, so slow requests still running for a position already left do
///   not hold the next position's slots.
/// * A failed warm is dropped rather than kept, so a transient error is never
///   pinned in front of the sheet as an instant error state.
class ExplorerGamesPrefetcher {
  ExplorerGamesPrefetcher(this._ref);

  final Ref _ref;

  /// Least recently warmed first.
  final LinkedHashMap<GamebasePositionGamesQuery, _WarmSubscription> _warm =
      LinkedHashMap<GamebasePositionGamesQuery, _WarmSubscription>();
  final Set<GamebasePositionGamesQuery> _inFlight = {};

  /// Next to start first.
  final List<GamebasePositionGamesQuery> _queue = [];

  /// The position(s) of the latest [warm]: the one being read.
  Set<String> _reading = const <String>{};

  bool _disposed = false;

  ExplorerGamesCache get _cache => _ref.read(explorerGamesCacheProvider);

  /// Reads whatever the disk saved for [queries] into memory, with no network
  /// request, so a sheet opened on any of them paints in its first frame.
  void preload(Iterable<GamebasePositionGamesQuery> queries) {
    if (_disposed) return;
    unawaited(_cache.preload(queries));
  }

  /// Warm [queries], in order, ahead of anything already waiting.
  ///
  /// Work still queued for any other position is dropped: the reader has left
  /// it. Requests already in flight are left alone (the server finishes them
  /// either way), but they no longer hold this position's slots.
  void warm(List<GamebasePositionGamesQuery> queries) {
    if (_disposed || queries.isEmpty) return;
    preload(queries);
    final positions = queries.map(_positionOf).toSet();
    _reading = positions;
    _queue.removeWhere(
      (queued) =>
          !positions.contains(_positionOf(queued)) || queries.contains(queued),
    );
    final wanted = <GamebasePositionGamesQuery>[];
    for (final query in queries) {
      if (wanted.contains(query) || !_needsFetch(query)) continue;
      wanted.add(query);
    }
    _queue.insertAll(0, wanted);
    if (_queue.length > kExplorerGamesPrefetchQueueLimit) {
      _queue.removeRange(kExplorerGamesPrefetchQueueLimit, _queue.length);
    }
    _pump();
  }

  /// The rows behind [queries] left the screen (the reader moved on, the
  /// panel closed): whatever of them is still waiting for a slot is dropped.
  /// Requests already on the wire are left to finish.
  void cancel(Iterable<GamebasePositionGamesQuery> queries) {
    if (_disposed || _queue.isEmpty) return;
    final gone = queries.toSet();
    _queue.removeWhere(gone.contains);
  }

  /// Head start for a tap that is about to open [query]'s sheet (tap-down,
  /// a long-press menu): starts now, without waiting for a free slot.
  void warmNow(GamebasePositionGamesQuery query) {
    if (_disposed) return;
    preload(<GamebasePositionGamesQuery>[query]);
    _queue.remove(query);
    if (!_needsFetch(query)) return;
    unawaited(_fetch(query));
  }

  /// Whether [query] has already settled and would answer the sheet instantly.
  bool isWarm(GamebasePositionGamesQuery query) {
    final subscription = _warm[query];
    return subscription != null &&
        !_inFlight.contains(query) &&
        subscription.read().hasValue;
  }

  /// Requests waiting for a slot, next first.
  List<GamebasePositionGamesQuery> get queued =>
      List<GamebasePositionGamesQuery>.unmodifiable(_queue);

  static String _positionOf(GamebasePositionGamesQuery query) =>
      query.fen.trim();

  /// False when [query] is on the wire or held with a recent answer. A held
  /// entry that failed or is too old is released and fetched again.
  bool _needsFetch(GamebasePositionGamesQuery query) {
    if (_inFlight.contains(query)) return false;
    final subscription = _warm[query];
    if (subscription == null) return true;
    final value = subscription.read();
    if (value.isLoading) return false;
    final settledAt = value.hasValue
        ? _cache.fetchedAtOf(value.requireValue)
        : null;
    if (settledAt != null &&
        DateTime.now().difference(settledAt) < kExplorerGamesRewarmAfter) {
      return false;
    }
    _warm.remove(query)?.close();
    if (value.hasValue) {
      // Held long enough to be worth asking again: drop the old answer so the
      // listen below starts a real request.
      _ref.invalidate(positionGamesProvider(query));
    }
    return true;
  }

  /// Whether the next queued request (always for the position being read)
  /// may start now.
  bool _hasFreeSlot() {
    if (_inFlight.length >= kExplorerGamesPrefetchInFlightCeiling) {
      return false;
    }
    var reading = 0;
    for (final query in _inFlight) {
      if (_reading.contains(_positionOf(query))) reading++;
    }
    return reading < kExplorerGamesPrefetchConcurrency;
  }

  void _pump() {
    while (!_disposed && _queue.isNotEmpty && _hasFreeSlot()) {
      final query = _queue.removeAt(0);
      if (!_needsFetch(query)) continue;
      unawaited(_fetch(query));
    }
  }

  Future<void> _fetch(GamebasePositionGamesQuery query) async {
    _inFlight.add(query);
    // The listener is what keeps the autoDispose entry resident; its callback
    // is deliberately empty because the awaited future below is the result.
    final subscription = _ref.listen<AsyncValue<GamebaseSearchQueryResponse>>(
      positionGamesProvider(query),
      (_, __) {},
    );
    _warm.remove(query)?.close();
    _warm[query] = subscription;
    _evict();
    try {
      await _ref.read(positionGamesProvider(query).future);
    } catch (_) {
      // Let the tap retry rather than serving it a cached failure.
      if (identical(_warm[query], subscription)) _warm.remove(query);
      subscription.close();
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
    _disposed = true;
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
