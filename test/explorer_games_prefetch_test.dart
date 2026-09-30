import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_games_prefetch.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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

  /// When set, every request without a gate of its own waits in [held]
  /// until the test releases it: a server slow on everything.
  bool holdAll = false;
  final List<Completer<void>> held = <Completer<void>>[];

  void releaseAll() {
    holdAll = false;
    for (final gate in held) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  /// `fen|uci` of every request, in the order they were sent.
  final List<String> requested = <String>[];

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
    requested.add('$fen|$uci');
    if (gates.isNotEmpty) {
      final gate = gates.removeAt(0);
      await gate.future;
    } else if (holdAll) {
      final gate = Completer<void>();
      held.add(gate);
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
      final row = queries.firstWhere((query) => query.uci == 'd7d6');
      final response = await container.read(positionGamesProvider(row).future);
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

  group('warm-up queue', () {
    // Ten distinct real positions: the start position after ten first moves.
    const firstMoves = [
      'e2e4', 'd2d4', 'c2c4', 'g1f3', 'b1c3', //
      'f2f4', 'g2g3', 'b2b3', 'e2e3', 'd2d3',
    ];
    final positions = [
      for (final uci in firstMoves)
        (fen: Chess.initial.play(NormalMove.fromUci(uci)).fen, uci: uci),
    ];
    const replies = ['e7e5', 'd7d5', 'c7c5', 'g8f6', 'b8c6', 'e7e6'];

    List<GamebasePositionGamesQuery> positionQueries(int index) =>
        buildExplorerGamesPrefetchQueries(
          fen: positions[index].fen,
          moves: [positions[index].uci],
          aggregates: [for (final reply in replies) _aggregate(reply, 10)],
          filters: const GamebaseFilters(),
        );

    test(
      'stepping through positions keeps only the newest one queued, ∑ first',
      () async {
        // A server slow on everything: nothing lands while the reader steps.
        final repository = _CountingRepository()..holdAll = true;
        final container = ProviderContainer(
          overrides: [gamebaseRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        addTearDown(repository.releaseAll);
        final prefetcher = container.read(explorerGamesPrefetchProvider);

        for (var i = 0; i < 10; i++) {
          prefetcher.warm(positionQueries(i));
          await Future<void>.delayed(Duration.zero);
          expect(
            prefetcher.queued.length,
            lessThanOrEqualTo(kExplorerGamesPrefetchQueueLimit),
          );
          // Nothing queued for a position the reader has already left.
          expect(
            prefetcher.queued.map((query) => query.fen).toSet(),
            {positions[i].fen},
          );
        }
        // The first two positions filled the overall ceiling between them;
        // nothing more went out while everything was still running.
        expect(repository.calls, kExplorerGamesPrefetchInFlightCeiling);
        expect(repository.requested[0], '${positions[0].fen}|null');
        expect(
          repository.requested[kExplorerGamesPrefetchConcurrency],
          '${positions[1].fen}|null',
        );
        expect(prefetcher.queued.first.uci, isNull);

        // A request lands: the position being read goes next, '∑' first.
        repository.held.first.complete();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(
          repository.requested[kExplorerGamesPrefetchInFlightCeiling],
          '${positions[9].fen}|null',
        );
      },
    );

    test(
      'a slow position the reader left does not hold the next one\'s slots',
      () async {
        final repository = _CountingRepository()..holdAll = true;
        final container = ProviderContainer(
          overrides: [gamebaseRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        addTearDown(repository.releaseAll);
        final prefetcher = container.read(explorerGamesPrefetchProvider);

        // Position A: its three warm-ups are stuck on a cold server.
        prefetcher.warm(positionQueries(0));
        await Future<void>.delayed(Duration.zero);
        expect(repository.calls, kExplorerGamesPrefetchConcurrency);

        // One step on: B gets its own three at once, '∑' first, without
        // waiting for any of A's to land.
        prefetcher.warm(positionQueries(1));
        await Future<void>.delayed(Duration.zero);
        final forB = [
          for (final request in repository.requested)
            if (request.startsWith('${positions[1].fen}|')) request,
        ];
        expect(forB, hasLength(kExplorerGamesPrefetchConcurrency));
        expect(forB.first, '${positions[1].fen}|null');
        expect(
          repository.calls,
          lessThanOrEqualTo(kExplorerGamesPrefetchInFlightCeiling),
        );
      },
    );

    test('the queue never grows past its limit', () async {
      final repository = _CountingRepository();
      final gates = List.generate(3, (_) => Completer<void>());
      repository.gates.addAll(gates);
      final container = ProviderContainer(
        overrides: [gamebaseRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final prefetcher = container.read(explorerGamesPrefetchProvider);

      // One position with far more rows than the queue holds.
      final fen = positions.first.fen;
      final many = [
        for (var i = 0; i < 40; i++)
          GamebasePositionGamesQuery.sheetPage(
            fen: fen,
            filters: const GamebaseFilters(),
            uci: 'a2a${i % 8 + 1}$i',
          ),
      ];
      prefetcher.warm(many);
      await Future<void>.delayed(Duration.zero);
      // Sixteen kept (three already sent), the other twenty-four dropped: the
      // tail of the request falls off, never the front.
      expect(
        repository.calls + prefetcher.queued.length,
        kExplorerGamesPrefetchQueueLimit,
      );
      expect(prefetcher.queued.first, many[3]);
      expect(prefetcher.queued.last, many[kExplorerGamesPrefetchQueueLimit - 1]);

      for (final gate in gates) {
        gate.complete();
      }
    });

    test('warming the same queries twice queues them once', () async {
      final repository = _CountingRepository();
      final gates = List.generate(3, (_) => Completer<void>());
      repository.gates.addAll(gates);
      final container = ProviderContainer(
        overrides: [gamebaseRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final prefetcher = container.read(explorerGamesPrefetchProvider);

      prefetcher.warm(positionQueries(0));
      prefetcher.warm(positionQueries(0));
      await Future<void>.delayed(Duration.zero);
      expect(prefetcher.queued.toSet().length, prefetcher.queued.length);
      expect(prefetcher.queued.length, 7 - kExplorerGamesPrefetchConcurrency);

      for (final gate in gates) {
        gate.complete();
      }
    });

    test('rows that leave the screen take their waiting warm-ups with them',
        () async {
      final repository = _CountingRepository()..holdAll = true;
      final container = ProviderContainer(
        overrides: [gamebaseRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      addTearDown(repository.releaseAll);
      final prefetcher = container.read(explorerGamesPrefetchProvider);

      // Position A on a slow server: three on the wire, four waiting.
      final a = positionQueries(0);
      prefetcher.warm(a);
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, kExplorerGamesPrefetchConcurrency);
      expect(prefetcher.queued, hasLength(a.length - repository.calls));

      // The reader moves on and nothing new settles.
      prefetcher.cancel(a);
      expect(prefetcher.queued, isEmpty);

      // A's requests on the wire finish; none of A's dropped rows follows.
      repository.releaseAll();
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repository.calls, kExplorerGamesPrefetchConcurrency);
      // The answers that did land still serve a tap.
      expect(prefetcher.isWarm(a.first), isTrue);
    });

    test('cancelling other rows leaves the rest of the queue alone', () async {
      final repository = _CountingRepository()..holdAll = true;
      final container = ProviderContainer(
        overrides: [gamebaseRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      addTearDown(repository.releaseAll);
      final prefetcher = container.read(explorerGamesPrefetchProvider);

      final a = positionQueries(0);
      prefetcher.warm(a);
      await Future<void>.delayed(Duration.zero);
      final waiting = prefetcher.queued;
      prefetcher.cancel([waiting.first, ...positionQueries(1)]);
      expect(prefetcher.queued, waiting.skip(1).toList());
    });

    test('a tap-down head start does not wait for a free slot', () async {
      final repository = _CountingRepository();
      final gates = List.generate(3, (_) => Completer<void>());
      repository.gates.addAll(gates);
      final container = ProviderContainer(
        overrides: [gamebaseRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final prefetcher = container.read(explorerGamesPrefetchProvider);

      final queries = positionQueries(0);
      prefetcher.warm(queries);
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, kExplorerGamesPrefetchConcurrency);

      final tapped = queries.last;
      prefetcher.warmNow(tapped);
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, kExplorerGamesPrefetchConcurrency + 1);
      expect(repository.requested.last, '${tapped.fen}|${tapped.uci}');
      expect(prefetcher.queued, isNot(contains(tapped)));

      for (final gate in gates) {
        gate.complete();
      }
    });
  });

  group('explorerGamesPrefetchSignature', () {
    test('changes when a transposition reaches the same FEN by another line',
        () {
      final aggregates = [_aggregate('d7d6', 23), _aggregate('a7a6', 16)];
      final viaItalian = explorerGamesPrefetchSignature(
        fen: _fen,
        moves: _moves,
        filters: _filters,
        aggregates: aggregates,
      );
      final viaTransposition = explorerGamesPrefetchSignature(
        fen: _fen,
        moves: const [
          'e2e4', 'e7e5', 'f1c4', 'g8f6', 'd2d3', 'b8c6', 'g1f3', 'f8c5',
          'b1c3',
        ],
        filters: _filters,
        aggregates: aggregates,
      );
      expect(viaTransposition, isNot(viaItalian));
      expect(
        explorerGamesPrefetchSignature(
          fen: _fen,
          moves: List.of(_moves),
          filters: _filters,
          aggregates: aggregates,
        ),
        viaItalian,
      );
    });

    test('changes with the rows and the filters', () {
      final base = explorerGamesPrefetchSignature(
        fen: _fen,
        moves: _moves,
        filters: _filters,
        aggregates: [_aggregate('d7d6', 23)],
      );
      expect(
        explorerGamesPrefetchSignature(
          fen: _fen,
          moves: _moves,
          filters: _filters,
          aggregates: [_aggregate('a7a6', 23)],
        ),
        isNot(base),
      );
      expect(
        explorerGamesPrefetchSignature(
          fen: _fen,
          moves: _moves,
          filters: _filters.copyWith(minRating: 2500),
          aggregates: [_aggregate('d7d6', 23)],
        ),
        isNot(base),
      );
    });
  });

  group('buildExplorerGamesPrefetchQueries', () {
    test('warms exactly the query the games sheet asks for', () {
      final queries = buildExplorerGamesPrefetchQueries(
        fen: _fen,
        moves: _moves,
        aggregates: [_aggregate('d7d6', 23), _aggregate('a7a6', 16)],
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

      final row = queries.firstWhere((query) => query.uci == 'd7d6');
      expect(row, asTheSheetBuildsIt);
      expect(row.hashCode, asTheSheetBuildsIt.hashCode);

      // The '∑' sheet: no uci, same everything else.
      final totals = queries.firstWhere((query) => query.uci == null);
      expect(
        totals,
        GamebasePositionGamesQuery.fromFilters(
          fen: _fen,
          filters: _filters,
          moves: _moves,
          sortBy: _filters.sortBy,
          sortDirection: _filters.sortDirection,
          pageNumber: 0,
          pageSize: 20,
        ),
      );
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

    test('warms the totals row first, then the visible rows in order', () {
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

      // The '∑' totals entry (no uci) answers for the whole position and is
      // warmed first, then two rows in the order they are displayed.
      expect(queries.map((q) => q.uci).toList(), [null, 'h7h6', 'd7d6']);
    });

    test("warms '∑' only when the table builds its row", () {
      // One move: the table has no '∑' row, so nothing on screen opens it,
      // and deep in a game it is one of the server's slowest queries.
      expect(
        buildExplorerGamesPrefetchQueries(
          fen: _fen,
          moves: _moves,
          aggregates: [_aggregate('d7d6', 23)],
          filters: _filters,
        ).map((query) => query.uci),
        ['d7d6'],
      );
      expect(explorerShowsTotalsRow([_aggregate('d7d6', 23)]), isFalse);
      // Two moves: '∑' is built, and warmed first.
      final aggregates = [_aggregate('d7d6', 23), _aggregate('a7a6', 16)];
      expect(explorerShowsTotalsRow(aggregates), isTrue);
      expect(
        buildExplorerGamesPrefetchQueries(
          fen: _fen,
          moves: _moves,
          aggregates: aggregates,
          filters: _filters,
        ).map((query) => query.uci),
        [null, 'd7d6', 'a7a6'],
      );
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
