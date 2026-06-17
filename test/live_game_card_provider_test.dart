import 'dart:async';

import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeGameStreamRepository extends GameStreamRepository {
  _FakeGameStreamRepository(this.stream);

  final Stream<Map<String, dynamic>?> stream;
  int individualSubscriptions = 0;
  int batchSubscriptions = 0;

  @override
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) {
    individualSubscriptions++;
    return stream;
  }

  @override
  Stream<LiveGameUpdate?> subscribeToLiveGameUpdate(String gameId) {
    individualSubscriptions++;
    return stream.map(
      (update) =>
          update == null ? null : LiveGameUpdate.fromLegacyMap(gameId, update),
    );
  }

  @override
  Stream<Map<String, LiveGameUpdate>> subscribeToLiveGameUpdatesBatch(
    List<String> gameIds,
  ) {
    batchSubscriptions++;
    return stream.map((update) {
      if (update == null) return const <String, LiveGameUpdate>{};
      return {
        for (final gameId in gameIds)
          gameId: LiveGameUpdate.fromLegacyMap(gameId, update),
      };
    });
  }
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: 'GM',
    rating: 2700,
    countryCode: 'USA',
    team: null,
  );
}

GamesTourModel _game({
  required String id,
  required GameStatus status,
  String? fen,
  String? pgn,
  String? lastMove,
  DateTime? lastMoveTime,
  int? whiteClockSeconds,
  int? blackClockSeconds,
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player('White'),
    blackPlayer: _player('Black'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: status,
    roundId: 'round-1',
    tourId: 'tour-1',
    fen: fen,
    pgn: pgn,
    lastMove: lastMove,
    lastMoveTime: lastMoveTime,
    whiteClockSeconds: whiteClockSeconds,
    blackClockSeconds: blackClockSeconds,
  );
}

class _LiveGameProbe extends ConsumerWidget {
  const _LiveGameProbe({required this.game, required this.onBuild});

  final GamesTourModel game;
  final void Function(GamesTourModel game) onBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveGame = watchLiveGame(ref, game);
    onBuild(liveGame);
    return const SizedBox.shrink();
  }
}

void main() {
  group('liveGameCardProvider', () {
    const afterE4 =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
    const afterE4E5 =
        'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
    const pgnAfterE4E5 = '''
[Event "Test"]

1. e4 e5 *
''';

    test('finished base games still consume the live row stream', () async {
      final controller = StreamController<Map<String, dynamic>?>();
      addTearDown(controller.close);

      final container = ProviderContainer(
        overrides: [
          gameStreamRepositoryProvider.overrideWithValue(
            _FakeGameStreamRepository(controller.stream),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(baseGameProvider('game-1').notifier).state = _game(
        id: 'game-1',
        status: GameStatus.whiteWins,
        fen: afterE4,
        lastMove: 'e2e4',
      );

      final sub = container.listen(
        liveGameCardProvider('game-1'),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      expect(sub.read()?.fen, afterE4);

      controller.add({
        'fen': afterE4,
        'pgn': pgnAfterE4E5,
        'last_move': 'e7e5',
        'status': '1-0',
      });
      await Future<void>.delayed(Duration.zero);

      final liveGame = sub.read();
      expect(liveGame?.gameStatus, GameStatus.whiteWins);
      expect(liveGame?.lastMove, 'e7e5');
      expect(liveGame?.fen, afterE4E5);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(baseGameProvider('game-1'))?.fen, afterE4E5);
    });

    testWidgets(
      'parent rebuilds cannot overwrite newer streamed clocks at the same ply',
      (tester) async {
        final controller = StreamController<Map<String, dynamic>?>();
        addTearDown(controller.close);

        final container = ProviderContainer(
          overrides: [
            gameStreamRepositoryProvider.overrideWithValue(
              _FakeGameStreamRepository(controller.stream),
            ),
          ],
        );
        addTearDown(container.dispose);

        final moveTime = DateTime.utc(2026, 4, 29, 12);
        final parentGame = _game(
          id: 'game-1',
          status: GameStatus.ongoing,
          fen: afterE4E5,
          pgn: pgnAfterE4E5,
          lastMove: 'e7e5',
          lastMoveTime: moveTime,
          whiteClockSeconds: 120,
          blackClockSeconds: 130,
        );

        GamesTourModel? renderedGame;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _LiveGameProbe(
              game: parentGame,
              onBuild: (game) => renderedGame = game,
            ),
          ),
        );
        await tester.pump();

        controller.add({
          'fen': afterE4E5,
          'pgn': pgnAfterE4E5,
          'last_move': 'e7e5',
          'last_move_time': moveTime.toIso8601String(),
          'last_clock_white': 100,
          'last_clock_black': 110,
          'status': '*',
        });
        await tester.pump();
        await tester.pump();

        expect(renderedGame?.whiteClockSeconds, 100);
        expect(renderedGame?.blackClockSeconds, 110);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _LiveGameProbe(
              game: parentGame,
              onBuild: (game) => renderedGame = game,
            ),
          ),
        );
        await tester.pump();

        expect(renderedGame?.whiteClockSeconds, 100);
        expect(renderedGame?.blackClockSeconds, 110);
        expect(
          container.read(baseGameProvider('game-1'))?.whiteClockSeconds,
          100,
        );
      },
    );

    test('disabled stream gate pauses card realtime subscriptions', () async {
      final controller = StreamController<Map<String, dynamic>?>();
      addTearDown(controller.close);
      final repository = _FakeGameStreamRepository(controller.stream);

      final container = ProviderContainer(
        overrides: [gameStreamRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      container.read(shouldStreamProvider.notifier).state = false;
      container.read(baseGameProvider('game-1').notifier).state = _game(
        id: 'game-1',
        status: GameStatus.ongoing,
        fen: afterE4,
        lastMove: 'e2e4',
      );

      final sub = container.listen(
        liveGameCardProvider('game-1'),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      expect(repository.individualSubscriptions, 0);
      expect(sub.read()?.fen, afterE4);

      controller.add({'fen': afterE4E5, 'last_move': 'e7e5', 'status': '*'});
      await Future<void>.delayed(Duration.zero);
      expect(sub.read()?.fen, afterE4);

      container.read(shouldStreamProvider.notifier).state = true;
      await Future<void>.delayed(Duration.zero);
      expect(repository.individualSubscriptions, 1);

      controller.add({
        'fen': afterE4,
        'pgn': pgnAfterE4E5,
        'last_move': 'e7e5',
        'status': '*',
      });
      await Future<void>.delayed(Duration.zero);
      expect(sub.read()?.lastMove, 'e7e5');
      expect(sub.read()?.fen, afterE4E5);
    });

    test(
      'disabled per-card stream gate avoids realtime subscriptions',
      () async {
        final repository = _FakeGameStreamRepository(
          const Stream<Map<String, dynamic>?>.empty(),
        );

        final container = ProviderContainer(
          overrides: [
            gameStreamRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        container.read(baseGameProvider('game-1').notifier).state = _game(
          id: 'game-1',
          status: GameStatus.ongoing,
          fen: afterE4,
          lastMove: 'e2e4',
        );

        final sub = container.listen(
          scopedLiveGameCardProvider(
            const LiveGameWatchParams(gameId: 'game-1', streamEnabled: false),
          ),
          (_, __) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);

        expect(repository.individualSubscriptions, 0);
        expect(sub.read()?.fen, afterE4);
      },
    );
  });
}
