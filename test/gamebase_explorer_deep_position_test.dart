// Regressions for the board-screen opening explorer at depth.
//
// Past 20 played plies the backend leaves its fast FEN-indexed path, so every
// navigation costs a real replay-backed round trip. Two things must hold there
// or the panel renders "No games found for this position" on a position that
// actually has games:
//
//   1. A position change must enter the loading state immediately, so the
//      table is never both settled and empty while a fetch is pending.
//   2. Prefetch must not fan out into the expensive replay path, which
//      starves the request the user is waiting on.
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_move_sort.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeRepo extends GamebaseRepository {
  _FakeRepo({this.delay = Duration.zero}) : super(Dio(), apiKey: 'test');

  final Duration delay;
  final List<List<String>> calls = [];

  @override
  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) async {
    calls.add(List<String>.of(moves));
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    // Answer with every legal move so the aggregates survive the notifier's
    // legality filter regardless of which position is queried.
    final position = Position.setupPosition(Rule.chess, Setup.parseFen(fen));
    final legal = <MoveAggregate>[];
    for (final entry in position.legalMoves.entries) {
      for (final to in entry.value.squares) {
        final move = NormalMove(from: entry.key, to: to);
        if (!position.isLegal(move)) continue;
        legal.add(
          MoveAggregate(uci: move.uci, white: 3, black: 2, draws: 1, total: 6),
        );
      }
    }
    return GamebaseResponse(status: 'success', data: GamebaseData(moves: legal));
  }
}

/// A real 30-ply line, so the walked positions sit well past the ply-20
/// indexed boundary.
const _line = <String>[
  'e2e4', 'c7c5', 'g1f3', 'd7d6', 'd2d4', 'c5d4', 'f3d4', 'g8f6',
  'b1c3', 'a7a6', 'c1g5', 'e7e6', 'f2f4', 'f8e7', 'd1f3', 'd8c7',
  'e1c1', 'b8d7', 'g2g4', 'b7b5', 'g5f6', 'd7f6', 'g4g5', 'f6d7',
  'f4f5', 'd7c5', 'f5f6', 'g7f6', 'g5f6', 'e7f8',
];

/// FEN reached after the first [plies] moves of [_line].
String _fenAfter(int plies) {
  Position position = Chess.initial;
  for (final uci in _line.take(plies)) {
    position = position.play(NormalMove.fromUci(uci));
  }
  return position.fen;
}

({ProviderContainer container, _FakeRepo repo}) _harness(_FakeRepo repo) {
  final container = ProviderContainer(
    overrides: [gamebaseRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  final sub = container.listen(
    gamebaseExplorerProvider,
    (_, __) {},
    fireImmediately: true,
  );
  addTearDown(sub.close);
  return (container: container, repo: repo);
}

void main() {
  group('explorer move sort', () {
    test('null sort keeps the backend order', () {
      expect(_order(null), _sortFixture.map((a) => a.uci).toList());
    });

    test('games', () {
      expect(
        _order(
          const ExplorerMoveSort(
            field: ExplorerMoveSortField.games,
            ascending: true,
          ),
        ),
        <String>['h2h3', 'a2a3', 'd2d4', 'e2e4'],
      );
      expect(
        _order(
          const ExplorerMoveSort(
            field: ExplorerMoveSortField.games,
            ascending: false,
          ),
        ),
        <String>['e2e4', 'd2d4', 'a2a3', 'h2h3'],
      );
    });

    test('score is white win-rate including half a point per draw', () {
      expect(
        _order(
          const ExplorerMoveSort(
            field: ExplorerMoveSortField.score,
            ascending: true,
          ),
        ),
        <String>['h2h3', 'e2e4', 'a2a3', 'd2d4'],
      );
    });

    test('last played', () {
      expect(
        _order(
          const ExplorerMoveSort(
            field: ExplorerMoveSortField.last,
            ascending: true,
          ),
        ),
        <String>['e2e4', 'a2a3', 'd2d4', 'h2h3'],
      );
    });

    test('move name orders by SAN, not uci', () {
      expect(
        _order(
          const ExplorerMoveSort(
            field: ExplorerMoveSortField.move,
            ascending: true,
          ),
        ),
        <String>['a2a3', 'd2d4', 'e2e4', 'h2h3'],
      );
    });

    test('header tap cycles ascending -> descending -> unsorted', () {
      var sort = ExplorerMoveSort.cycle(null, ExplorerMoveSortField.games);
      expect(sort!.field, ExplorerMoveSortField.games);
      expect(sort.ascending, isTrue);

      sort = ExplorerMoveSort.cycle(sort, ExplorerMoveSortField.games);
      expect(sort!.ascending, isFalse);

      sort = ExplorerMoveSort.cycle(sort, ExplorerMoveSortField.games);
      expect(sort, isNull);
    });

    test('switching column restarts at ascending', () {
      const desc = ExplorerMoveSort(
        field: ExplorerMoveSortField.games,
        ascending: false,
      );
      final next = ExplorerMoveSort.cycle(desc, ExplorerMoveSortField.score);
      expect(next!.field, ExplorerMoveSortField.score);
      expect(next.ascending, isTrue);
    });
  });


  test(
    'a deep position change never leaves the table settled-but-empty',
    () async {
      final h = _harness(_FakeRepo(delay: const Duration(seconds: 2)));
      final notifier = h.container.read(gamebaseExplorerProvider.notifier);

      // Land on a position past the indexed boundary and settle it.
      notifier.setPositionWithMoves(
        _fenAfter(24),
        _line.take(24).toList(),
        startingFen: Chess.initial.fen,
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(h.container.read(gamebaseExplorerProvider).isLoading, isFalse);
      expect(
        h.container.read(gamebaseExplorerProvider).moveAggregates,
        isNotEmpty,
      );

      final stale =
          h.container
              .read(gamebaseExplorerProvider)
              .moveAggregates
              .map((m) => m.uci)
              .toList();

      // Now advance a ply. Through the whole debounce + request window the
      // panel must read as "loading" — never as a settled table. Serving the
      // previous position's rows is worse than a spinner: those moves are
      // mostly illegal in the new position, so tapping one is silently
      // rejected by the board and the explorer looks broken.
      notifier.setPositionWithMoves(
        _fenAfter(25),
        _line.take(25).toList(),
        startingFen: Chess.initial.fen,
      );

      for (var i = 0; i < 25; i++) {
        final state = h.container.read(gamebaseExplorerProvider);
        final settledRows = !state.isLoading;
        if (settledRows) {
          expect(
            state.moveAggregates.map((m) => m.uci).toList(),
            isNot(stale),
            reason:
                'explorer served the previous position\'s moves as a settled '
                'table ${i * 100}ms into a pending deep fetch',
          );
        }
        expect(
          state.moveAggregates.isEmpty && !state.isLoading,
          isFalse,
          reason:
              'panel would render "No games found for this position" '
              '${i * 100}ms into a pending deep fetch',
        );
        if (state.moveAggregates.isNotEmpty && !state.isLoading) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      final settled = h.container.read(gamebaseExplorerProvider);
      expect(settled.isLoading, isFalse);
      expect(settled.moveAggregates, isNotEmpty);
    },
  );

  test('prefetch does not fan out past the indexed boundary', () async {
    final h = _harness(_FakeRepo());
    final notifier = h.container.read(gamebaseExplorerProvider.notifier);

    notifier.setPositionWithMoves(
      _fenAfter(24),
      _line.take(24).toList(),
      startingFen: Chess.initial.fen,
    );
    await Future<void>.delayed(const Duration(seconds: 1));

    // One request for the position itself; no speculative replay-path queries
    // for its children.
    expect(
      h.repo.calls.length,
      1,
      reason:
          'deep positions must not spawn prefetch into the replay-backed path',
    );
    expect(h.repo.calls.single.length, 24);
  });

  test('shallow positions still prefetch the likely next positions', () async {
    final h = _harness(_FakeRepo());
    final notifier = h.container.read(gamebaseExplorerProvider.notifier);

    notifier.setPositionWithMoves(
      _fenAfter(4),
      _line.take(4).toList(),
      startingFen: Chess.initial.fen,
    );
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(
      h.repo.calls.length,
      greaterThan(1),
      reason: 'inside the fast indexed window prefetch is still worthwhile',
    );
  });

  test('the full move line is sent so the backend can replay deep', () async {
    final h = _harness(_FakeRepo());
    final notifier = h.container.read(gamebaseExplorerProvider.notifier);

    notifier.setPositionWithMoves(
      _fenAfter(28),
      _line.take(28).toList(),
      startingFen: Chess.initial.fen,
    );
    await Future<void>.delayed(const Duration(seconds: 1));

    // Dropping the line collapses the backend onto the position-only lookup,
    // which returns nothing past ply 20.
    expect(h.repo.calls.first, _line.take(28).toList());
  });
}

/// Four moves whose games / score / last-played ranks are all different, so
/// each sort column yields a distinct order.
final _sortFixture = <MoveAggregate>[
  MoveAggregate(
    uci: 'e2e4',
    white: 10,
    black: 90,
    draws: 0,
    total: 100,
    lastPlayed: DateTime.utc(2020),
  ), // score 0.10
  MoveAggregate(
    uci: 'd2d4',
    white: 45,
    black: 5,
    draws: 0,
    total: 50,
    lastPlayed: DateTime.utc(2023),
  ), // score 0.90
  MoveAggregate(
    uci: 'a2a3',
    white: 5,
    black: 5,
    draws: 0,
    total: 10,
    lastPlayed: DateTime.utc(2021),
  ), // score 0.50
  MoveAggregate(
    uci: 'h2h3',
    white: 0,
    black: 5,
    draws: 0,
    total: 5,
    lastPlayed: DateTime.utc(2024),
  ), // score 0.00
];

List<String> _order(ExplorerMoveSort? sort) => applyExplorerMoveSort(
  _sortFixture,
  sort,
  Chess.initial.fen,
).map((a) => a.uci).toList();
