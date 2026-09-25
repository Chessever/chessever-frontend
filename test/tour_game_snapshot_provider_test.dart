import 'dart:async';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/tour_game_snapshot_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _pgn = '[Event "Test"]\n\n1. e4 e5 2. Nf3 Nc6 1-0';
const _finalFen =
    'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';

Games _game(String id, {bool deferred = false}) => Games(
  id: id,
  roundId: 'round-1',
  roundSlug: 'round-1',
  tourId: 'tour-1',
  tourSlug: 'tour-1',
  status: '1-0',
  fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
  lastMove: 'b8c6',
  pgn: deferred ? null : _pgn,
  isPgnDeferred: deferred,
  lastClockWhite: 60,
  lastClockBlack: 60,
  players: [
    for (final name in ['White', 'Black'])
      Player(
        name: name,
        title: 'GM',
        rating: 2600,
        fideId: 1,
        fed: 'USA',
        clock: 0,
        team: '',
      ),
  ],
);

class _Repository extends GameRepository {
  final requests = <List<String>>[];
  Future<List<Games>> Function(List<String>)? load;

  @override
  Future<List<Games>> getGamesByIds(List<String> ids) async {
    requests.add(ids);
    return load == null ? ids.map(_game).toList() : load!(ids);
  }
}

class _Card extends ConsumerWidget {
  const _Card(this.game);
  final GamesTourModel game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = watchLiveGamePosition(ref, game);
    return Text(resolved.fen ?? '');
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder',
    );
  });

  testWidgets(
    'large bursts bound in-flight PGN batches and cancel queued cards',
    (tester) async {
      final replies = <Completer<List<Games>>>[];
      final repo =
          _Repository()
            ..load = (_) {
              final reply = Completer<List<Games>>();
              replies.add(reply);
              return reply.future;
            };
      final container = ProviderContainer(
        overrides: [gameRepositoryProvider.overrideWithValue(repo)],
      );
      final listeners = [
        for (var i = 0; i < 800; i++)
          container.listen(tourGameSnapshotProvider('g$i'), (_, __) {}),
      ];
      await tester.pump(const Duration(milliseconds: 100));
      final initialRequests = repo.requests.length;

      // A fling removes all but the last queued card while two batches are slow.
      for (var i = 32; i < 799; i++) {
        listeners[i].close();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      replies.first.complete(repo.requests.first.map(_game).toList());
      await tester.pump();
      final afterRelease = repo.requests.length;
      final lastRequest = repo.requests.last;

      // Drain and dispose even when the initial concurrency assertion fails.
      for (final listener in listeners.take(32)) {
        listener.close();
      }
      listeners.last.close();
      container.dispose();
      for (var i = 1; i < replies.length; i++) {
        replies[i].complete(repo.requests[i].map(_game).toList());
      }
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        initialRequests,
        2,
        reason: '800 mounted requests must not launch 50 PGN downloads at once',
      );
      expect(afterRelease, 3);
      expect(lastRequest, [
        'g799',
      ], reason: 'Unmounted cards must leave the queue before a slot opens');
    },
  );

  testWidgets('mounted cards batch by 16 and release snapshots on unmount', (
    tester,
  ) async {
    final repo = _Repository();
    final container = ProviderContainer(
      overrides: [gameRepositoryProvider.overrideWithValue(repo)],
    );
    final listeners = [
      for (var i = 0; i < 35; i++)
        container.listen(tourGameSnapshotProvider('g$i'), (_, __) {}),
    ];
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.requests.map((ids) => ids.length), [16, 16, 3]);
    expect(
      container.read(tourGameSnapshotProvider('g0')).valueOrNull?.pgn,
      _pgn,
    );
    for (final listener in listeners) {
      listener.close();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(container.exists(tourGameSnapshotProvider('g0')), isFalse);
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'in-flight requests share the concurrency budget across remounts',
    (tester) async {
      final replies = <Completer<List<Games>>>[];
      final repo =
          _Repository()
            ..load = (_) {
              final reply = Completer<List<Games>>();
              replies.add(reply);
              return reply.future;
            };
      final container = ProviderContainer(
        overrides: [gameRepositoryProvider.overrideWithValue(repo)],
      );
      final old = [
        for (var i = 0; i < 32; i++)
          container.listen(tourGameSnapshotProvider('old$i'), (_, __) {}),
      ];
      await tester.pump(const Duration(milliseconds: 100));
      for (final listener in old) {
        listener.close();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final current = container.listen(
        tourGameSnapshotProvider('new'),
        (_, __) {},
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.requests, hasLength(2));
      container.read(liveGameCardsPauseReasonsProvider.notifier).state = {
        'scroll',
      };
      await tester.pump();
      replies.first.completeError(StateError('offline'));
      await tester.pump();
      expect(
        repo.requests,
        hasLength(2),
        reason: 'A free slot must respect scroll pause',
      );
      container.read(liveGameCardsPauseReasonsProvider.notifier).state = {};
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.requests.last, ['new']);
      replies.last.complete([_game('new')]);
      await tester.pump();
      expect(current.read().valueOrNull?.id, 'new');
      current.close();
      container.dispose();
      replies[1].complete([]);
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('a fling cancels unmounted requests and delays remaining work', (
    tester,
  ) async {
    final repo = _Repository();
    final container = ProviderContainer(
      overrides: [
        gameRepositoryProvider.overrideWithValue(repo),
        liveGameCardsPauseReasonsProvider.overrideWith((ref) => {'scroll'}),
      ],
    );
    final gone = container.listen(tourGameSnapshotProvider('gone'), (_, __) {});
    final kept = container.listen(tourGameSnapshotProvider('kept'), (_, __) {});
    await tester.pump(const Duration(seconds: 1));
    expect(repo.requests, isEmpty);
    gone.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    container.read(liveGameCardsPauseReasonsProvider.notifier).state = {};
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.requests, [
      ['kept'],
    ]);
    kept.close();
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('late replies cannot replace a remounted card request', (
    tester,
  ) async {
    final repo = _Repository();
    final oldReply = Completer<List<Games>>();
    repo.load = (_) => oldReply.future;
    final container = ProviderContainer(
      overrides: [gameRepositoryProvider.overrideWithValue(repo)],
    );
    final old = container.listen(tourGameSnapshotProvider('g'), (_, __) {});
    await tester.pump(const Duration(milliseconds: 100));
    old.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    repo.load = (_) async => [_game('g').copyWith(name: 'new')];
    final current = container.listen(tourGameSnapshotProvider('g'), (_, __) {});
    await tester.pump(const Duration(milliseconds: 100));
    oldReply.complete([_game('g').copyWith(name: 'old')]);
    await tester.pump();
    expect(
      container.read(tourGameSnapshotProvider('g')).valueOrNull?.name,
      'new',
    );
    current.close();
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('errors release with the card and retry on its next mount', (
    tester,
  ) async {
    final repo = _Repository()..load = (_) async => throw StateError('offline');
    final container = ProviderContainer(
      overrides: [gameRepositoryProvider.overrideWithValue(repo)],
    );
    final first = container.listen(tourGameSnapshotProvider('g'), (_, __) {});
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(tourGameSnapshotProvider('g')).hasError, isTrue);
    first.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    repo.load = null;
    final second = container.listen(tourGameSnapshotProvider('g'), (_, __) {});
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      container.read(tourGameSnapshotProvider('g')).valueOrNull?.pgn,
      _pgn,
    );
    second.close();
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'index models repair a visible board from retained PGN without a fetch',
    (tester) async {
      final repo = _Repository();
      final container = ProviderContainer(
        overrides: [gameRepositoryProvider.overrideWithValue(repo)],
      );
      final raw = _game('g');
      final indexGame = GamesTourModel.fromGameIndex(raw);
      expect(indexGame.fen, raw.fen);
      expect(indexGame.pgn, _pgn);
      expect(indexGame.isPgnDeferred, isFalse);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: _Card(indexGame)),
        ),
      );
      await tester.pump();
      expect(find.text(_finalFen), findsOneWidget);
      expect(repo.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'a card repaints the repaired position and releases it when covered',
    (tester) async {
      final repo = _Repository();
      final container = ProviderContainer(
        overrides: [gameRepositoryProvider.overrideWithValue(repo)],
      );
      final enabled = ValueNotifier(true);
      final game = GamesTourModel.fromGame(_game('g', deferred: true));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: enabled,
              builder:
                  (_, enabled, child) =>
                      TickerMode(enabled: enabled, child: child!),
              child: _Card(game),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump();
      expect(find.text(_finalFen), findsOneWidget);
      enabled.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(container.exists(tourGameSnapshotProvider('g')), isFalse);
      expect(container.exists(baseGameProvider('g')), isFalse);
      // A board switcher can still enable the global stream flag. Hidden cards
      // must not reacquire their data until Flutter reveals the route.
      container.read(shouldStreamProvider.notifier).state = true;
      await tester.pump(const Duration(seconds: 1));
      expect(repo.requests.length, 1);
      enabled.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.requests.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
      enabled.dispose();
    },
  );
}
