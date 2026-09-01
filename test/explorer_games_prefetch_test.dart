import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_games_prefetch.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Warming the explorer's games rows only pays off if the warmed query is the
/// *same* `positionGamesProvider` family key the sheet later reads. Any drift
/// in a single field — a filter the warm-up forgets, a page size that differs
/// by one — turns the whole prefetch into invisible dead work that still costs
/// the backend a request. These tests hold that identity.

const _fen = 'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R b KQkq - 3 5';
const _moves = <String>[
  'e2e4',
  'e7e5',
  'g1f3',
  'b8c6',
  'f1c4',
  'g8f6',
  'd2d3',
  'f8c5',
  'b1c3',
];

MoveAggregate _aggregate(String uci, int total) =>
    MoveAggregate(uci: uci, white: total, black: 0, draws: 0, total: total);

/// The "prepare against Sindarov's white games" filter set from the bug report,
/// with every optional axis populated so a dropped field cannot hide.
const _filters = GamebaseFilters(
  timeControls: [TimeControl.classical, TimeControl.rapid],
  minRating: 2400,
  maxRating: 2900,
  playerIds: ['b1062433-ce11-45e5-84e5-a331d5f4ea34'],
  playerColor: GamebasePlayerColor.white,
  gameResult: GamebaseGameResult.whiteWins,
  isOnline: false,
  yearFrom: 2019,
  yearTo: 2026,
  sortBy: GamebaseSortField.avgElo,
  sortDirection: GamebaseSortDirection.asc,
);

/// Counts backend calls and answers with one row carrying the requested uci,
/// so a test can tell a warmed answer from a re-fetched one.
class _CountingRepository extends GamebaseRepository {
  _CountingRepository() : super(Dio(), apiKey: 'test');

  int calls = 0;
  final List<Completer<void>> gates = <Completer<void>>[];
  bool failNext = false;

  @override
  Future<GamebaseSearchQueryResponse> getPositionGames({
    required String fen,
    List<String> moves = const [],
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    calls += 1;
    if (gates.isNotEmpty) {
      final gate = gates.removeAt(0);
      await gate.future;
    }
    if (failNext) {
      failNext = false;
      throw Exception('backend down');
    }
    return GamebaseSearchQueryResponse(
      status: 'success',
      data: [
        {'id': 'game-$uci', 'uci': uci},
      ],
      metadata: GamebasePaginationMetadata(
        pageNumber: pageNumber,
        pageSize: pageSize,
      ),
    );
  }
}

void main() {
  group('ExplorerGamesPrefetcher', () {
    test('a warmed row answers the tap without a second request', () async {
      final repository = _CountingRepository();
      final container = ProviderContainer(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final queries = buildExplorerGamesPrefetchQueries(
        fen: _fen,
        moves: _moves,
        aggregates: [_aggregate('d7d6', 23)],
        filters: _filters,
        rows: 1,
      );
      container.read(explorerGamesPrefetchProvider).warm(queries);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(repository.calls, queries.length);

      // What the sheet does on open. `positionGamesProvider` is autoDispose, so
      // this only stays at one call if the warm-up is still holding the entry.
      final response =
          await container.read(positionGamesProvider(queries.first).future);
      expect(response.data.single['id'], 'game-d7d6');
      expect(repository.calls, queries.length);
    });

    test('respects the concurrency cap', () async {
      final repository = _CountingRepository();
      final gates = List.generate(3, (_) => Completer<void>());
      repository.gates.addAll(gates);
      final container = ProviderContainer(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      container.read(explorerGamesPrefetchProvider).warm(
            buildExplorerGamesPrefetchQueries(
              fen: _fen,
              moves: _moves,
              aggregates: [
                _aggregate('h7h6', 28),
                _aggregate('d7d6', 23),
                _aggregate('a7a6', 16),
              ],
              filters: _filters,
            ),
          );
      await Future<void>.delayed(Duration.zero);

      expect(repository.calls, kExplorerGamesPrefetchConcurrency);

      for (final gate in gates) {
        gate.complete();
      }
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, greaterThan(kExplorerGamesPrefetchConcurrency));
    });

    test('a failed warm is dropped so the tap can retry', () async {
      final repository = _CountingRepository()..failNext = true;
      final container = ProviderContainer(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final query = buildExplorerGamesPrefetchQueries(
        fen: _fen,
        moves: _moves,
        aggregates: [_aggregate('d7d6', 23)],
        filters: _filters,
        rows: 1,
      ).first;
      final prefetcher = container.read(explorerGamesPrefetchProvider);
      prefetcher.warm([query]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(prefetcher.isWarm(query), isFalse);
    });
  });

  group('buildExplorerGamesPrefetchQueries', () {
    test('warms exactly the query the games sheet asks for', () {
      final queries = buildExplorerGamesPrefetchQueries(
        fen: _fen,
        moves: _moves,
        aggregates: [_aggregate('d7d6', 23)],
        filters: _filters,
      );

      // The sheet seeds its own sort from the filters and pages by 20.
      final asTheSheetBuildsIt = GamebasePositionGamesQuery.fromFilters(
        fen: _fen,
        filters: _filters,
        moves: _moves,
        uci: 'd7d6',
        sortBy: _filters.sortBy,
        sortDirection: _filters.sortDirection,
        pageNumber: 0,
        pageSize: 20,
      );

      expect(queries.first, asTheSheetBuildsIt);
      expect(queries.first.hashCode, asTheSheetBuildsIt.hashCode);
    });

    test('carries every filter axis into the request body', () {
      final query = buildExplorerGamesPrefetchQueries(
        fen: _fen,
        moves: _moves,
        aggregates: [_aggregate('d7d6', 23)],
        filters: _filters,
      ).first;

      final body = GamebaseRepository.buildPositionGamesQueryBody(
        fen: query.fen,
        moves: query.moves,
        uci: query.uci,
        timeControl: query.timeControl,
        playerId: query.playerId,
        color: query.color,
        result: query.result,
        minRating: query.minRating,
        maxRating: query.maxRating,
        yearFrom: query.yearFrom,
        yearTo: query.yearTo,
        sortBy: query.sortBy,
        sortDirection: query.sortDirection,
        isOnline: query.isOnline,
        pageNumber: query.pageNumber,
        pageSize: query.pageSize,
      );

      expect(body['playerId'], 'b1062433-ce11-45e5-84e5-a331d5f4ea34');
      expect(body['color'], 'white');
      expect(body['minRating'], 2400);
      expect(body['maxRating'], 2900);
      expect(body['yearFrom'], 2019);
      expect(body['yearTo'], 2026);
      expect(body['isOnline'], false);
      expect(body['pageSize'], 20);
    });

    test('warms the visible rows in order, then the totals row', () {
      final queries = buildExplorerGamesPrefetchQueries(
        fen: _fen,
        moves: _moves,
        aggregates: [
          _aggregate('h7h6', 28),
          _aggregate('d7d6', 23),
          _aggregate('a7a6', 16),
        ],
        filters: _filters,
        rows: 2,
      );

      // Two rows plus the '∑' totals entry, which carries no uci.
      expect(queries.map((q) => q.uci).toList(), ['h7h6', 'd7d6', null]);
    });

    test('is a no-op before the move table has anything to warm', () {
      expect(
        buildExplorerGamesPrefetchQueries(
          fen: _fen,
          moves: _moves,
          aggregates: const [],
          filters: const GamebaseFilters(),
        ),
        isEmpty,
      );
      expect(
        buildExplorerGamesPrefetchQueries(
          fen: '   ',
          moves: const [],
          aggregates: [_aggregate('d7d6', 23)],
          filters: const GamebaseFilters(),
        ),
        isEmpty,
      );
    });

    test('distinguishes rows that differ only by the filtered colour', () {
      GamebasePositionGamesQuery first(GamebasePlayerColor color) =>
          buildExplorerGamesPrefetchQueries(
            fen: _fen,
            moves: _moves,
            aggregates: [_aggregate('d7d6', 23)],
            filters: _filters.copyWith(playerColor: color),
          ).first;

      expect(first(GamebasePlayerColor.white), isNot(first(GamebasePlayerColor.black)));
    });
  });
}
