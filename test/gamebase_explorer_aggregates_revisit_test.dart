import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A position the explorer answered moments ago is answered again from its
/// memory cache in the same frame, so the move table (and the games warm-ups
/// behind it) never blank on a back-step. The data is exactly what the
/// debounced fetch would install a moment later.

class _Repo extends GamebaseRepository {
  _Repo() : super(Dio(), apiKey: 'test');

  final List<String> fens = <String>[];

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
    fens.add(fen);
    final position = Chess.fromSetup(Setup.parseFen(fen));
    final moves = <MoveAggregate>[];
    for (final entry in position.legalMoves.entries) {
      for (final to in entry.value.squares) {
        moves.add(
          MoveAggregate(
            uci: NormalMove(from: entry.key, to: to).uci,
            white: 3,
            black: 2,
            draws: 1,
            total: 6,
          ),
        );
        if (moves.length >= 3) break;
      }
      if (moves.length >= 3) break;
    }
    return GamebaseResponse(
      status: 'success',
      data: GamebaseData(moves: moves),
    );
  }
}

void main() {
  final start = Chess.initial;
  final afterE4 = start.play(NormalMove.fromUci('e2e4'));
  final afterE5 = afterE4.play(NormalMove.fromUci('e7e5'));

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 350));

  test(
    'a back-step shows the cached move table at once, with no request',
    () async {
      final repo = _Repo();
      final container = ProviderContainer(
        overrides: [gamebaseRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(gamebaseExplorerProvider, (_, __) {});
      addTearDown(sub.close);
      final notifier = container.read(gamebaseExplorerProvider.notifier);

      notifier.setPositionWithMoves(afterE4.fen, const [
        'e2e4',
      ], startingFen: start.fen);
      await settle();
      final e4Table = container.read(gamebaseExplorerProvider).moveAggregates;
      expect(e4Table, isNotEmpty);

      notifier.setPositionWithMoves(afterE5.fen, const [
        'e2e4',
        'e7e5',
      ], startingFen: start.fen);
      await settle();
      final requestsBeforeBackStep = repo.fens.length;

      notifier.setPositionWithMoves(afterE4.fen, const [
        'e2e4',
      ], startingFen: start.fen);
      // Same frame: no loading state, no blank table.
      final state = container.read(gamebaseExplorerProvider);
      expect(state.isLoading, isFalse);
      expect(state.moveAggregates, e4Table);
      expect(state.exploredMoves, const ['e2e4']);

      await settle();
      expect(repo.fens.length, requestsBeforeBackStep);
      expect(container.read(gamebaseExplorerProvider).moveAggregates, e4Table);
    },
  );

  test('a position never answered still loads through the fetch', () async {
    final repo = _Repo();
    final container = ProviderContainer(
      overrides: [gamebaseRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gamebaseExplorerProvider, (_, __) {});
    addTearDown(sub.close);
    final notifier = container.read(gamebaseExplorerProvider.notifier);

    notifier.setPositionWithMoves(afterE4.fen, const [
      'e2e4',
    ], startingFen: start.fen);
    final loading = container.read(gamebaseExplorerProvider);
    expect(loading.isLoading, isTrue);
    expect(loading.moveAggregates, isEmpty);

    await settle();
    final loaded = container.read(gamebaseExplorerProvider);
    expect(loaded.isLoading, isFalse);
    expect(loaded.moveAggregates, isNotEmpty);
  });
}
