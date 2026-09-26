import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pull to refresh brings new games: none of the ones the feed held, and
/// none shown before while anything unseen is left. The ready reserve is
/// landed on only while it is recent and new.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the reserve a refresh lands on', () {
    final now = DateTime(2026, 9, 26, 12);
    final items = [
      for (final id in ['a', 'b', 'c']) _item(id),
    ];

    test('a recent one lands whole', () {
      final landing = feedReserveLanding(
        items: items,
        drawnAt: now.subtract(const Duration(minutes: 2)),
        now: now,
        exclude: const {'x'},
      );
      expect(_ids(landing), ['a', 'b', 'c']);
    });

    test('never with a game the viewer has seen', () {
      final landing = feedReserveLanding(
        items: items,
        drawnAt: now,
        now: now,
        exclude: const {'b'},
      );
      expect(_ids(landing), ['a', 'c']);
      expect(
        feedReserveLanding(
          items: items,
          drawnAt: now,
          now: now,
          exclude: const {'a', 'b', 'c'},
        ),
        isEmpty,
      );
    });

    test('an old one is not landed on at all', () {
      final landing = feedReserveLanding(
        items: items,
        drawnAt: now.subtract(
          FeedNotifier.reserveMaxAge + const Duration(seconds: 1),
        ),
        now: now,
        exclude: const {},
      );
      expect(landing, isEmpty);
    });
  });

  group('refresh, over the real notifier', () {
    test(
      'lands on none of the games the feed held',
      () => _quietly(() async {
        final f = await _Harness.start();
        final before = f.ids;
        expect(before, isNotEmpty);
        final reserve = f.notifier.reserveIds!;

        await f.notifier.refresh();
        final after = f.ids;
        expect(after, isNotEmpty);
        expect(after.toSet().intersection(before.toSet()), isEmpty);
        // The ready reserve was the new first page, landed at once.
        expect(after, reserve);
      }),
      timeout: _realTime,
    );

    test(
      'five pulls in a row: no pull opens on a game shown before',
      () => _quietly(() async {
        final f = await _Harness.start();
        final shown = <String>{...f.ids};
        for (var pull = 0; pull < 5; pull++) {
          await f.waitForReserve();
          await f.notifier.refresh();
          final opening = f.ids.take(3).toSet();
          expect(
            opening.intersection(shown),
            isEmpty,
            reason: 'pull ${pull + 1} opened on $opening',
          );
          await f.waitForTopUp();
          shown.addAll(f.ids);
        }
      }),
      timeout: _realTime,
    );

    test(
      'an old reserve is not landed on: the pull reads the sources',
      () => _quietly(() async {
        final f = await _Harness.start();
        final reserve = f.notifier.reserveIds!;
        final before = f.ids.toSet();
        f.clock = f.clock.add(
          FeedNotifier.reserveMaxAge + const Duration(minutes: 1),
        );
        final reads = f.games.reads;

        await f.notifier.refresh();
        // A first page drawn from the sources (its size, not the reserve's),
        // after asking them again.
        expect(f.games.reads, greaterThan(reads));
        expect(f.ids, hasLength(2));
        expect(f.ids, isNot(reserve));
        expect(f.ids.toSet().intersection(before), isEmpty);
      }),
      timeout: _realTime,
    );

    test(
      'an old reserve is drawn again behind the viewer',
      () => _quietly(() async {
        final f = await _Harness.start();
        f.clock = f.clock.add(
          FeedNotifier.reserveMaxAge + const Duration(minutes: 1),
        );
        final reads = f.games.reads;
        f.notifier.onVisible(1);
        expect(f.notifier.reserveIds, isNull);
        await f.waitForReserve();
        // Drawn again from the sources, and recent: the next pull lands on
        // it at once. (Its games may be the old reserve's: those were never
        // shown, so they went back to the draw.)
        expect(f.games.reads, greaterThan(reads));
        final reserve = f.notifier.reserveIds!;
        await f.notifier.refresh();
        expect(f.ids, reserve);
      }),
      timeout: _realTime,
    );
  });

  group('the reserve after a refresh', () {
    test(
      'a redraw still running when the viewer pulls does not stop the new '
      'feed from drawing its own',
      () => _quietly(() async {
        final f = await _Harness.start();
        f.clock = f.clock.add(
          FeedNotifier.reserveMaxAge + const Duration(minutes: 1),
        );
        // The stale reserve is drawn again behind the viewer, and that
        // draw's first read hangs.
        final stall = Completer<void>();
        addTearDown(() {
          if (!stall.isCompleted) stall.complete();
        });
        f.games.stallNext = stall;
        f.notifier.onVisible(0);
        expect(f.notifier.reserveIds, isNull);
        expect(f.games.stallNext, isNull, reason: 'the redraw read nothing');

        // The pull finds no reserve and reads the sources itself.
        await f.notifier.refresh();
        expect(f.ids, isNotEmpty);
        // The new feed draws its reserve while the old draw still hangs,
        // so the next pull lands at once.
        await f.waitForReserve();
        expect(stall.isCompleted, isFalse);
        final reserve = f.notifier.reserveIds!;
        stall.complete();
        await f.notifier.refresh();
        expect(f.ids, reserve);
      }),
      timeout: _realTime,
    );
  });

  group('news after a refresh', () {
    test('articles the viewer reached go to the back of the line', () {
      final news = [for (var id = 1; id <= 3; id++) _news(id)];
      expect(feedNewsUnseenFirst(news, const {}).map((n) => n.id), [1, 2, 3]);
      expect(feedNewsUnseenFirst(news, const {1}).map((n) => n.id), [2, 3, 1]);
      expect(feedNewsUnseenFirst(news, const {1, 2, 3}).map((n) => n.id), [
        1,
        2,
        3,
      ]);
    });

    test('a refresh opens its news slot on an article not read yet', () async {
      final games = _SettableFeed([for (var i = 0; i < 8; i++) _item('old$i')]);
      final container = ProviderContainer(
        overrides: [
          feedProvider.overrideWith(() => games),
          feedNewsProvider.overrideWith((ref) async => [_news(1), _news(2)]),
        ],
      );
      addTearDown(container.dispose);
      container.listen(feedEntriesProvider, (_, _) {});
      await container.read(feedProvider.future);
      await container.read(feedNewsProvider.future);

      List<FeedEntry> entries() => container.read(feedEntriesProvider);
      int newsAt(List<FeedEntry> list) =>
          list.indexWhere((e) => e is FeedNewsEntry);
      final first = entries();
      final slot = newsAt(first);
      expect((first[slot] as FeedNewsEntry).news.id, 1);
      // The viewer reads it.
      container.read(feedEntriesProvider.notifier).markSeen(slot);

      games.set([for (var i = 0; i < 8; i++) _item('new$i')]);
      final next = entries();
      expect((next[newsAt(next)] as FeedNewsEntry).news.id, 2);
    });
  });
}

// --------------------------------------------------------------- harness

/// The real notifier runs on real time: it draws its pages and its reserve
/// in background isolates, and [_Harness] polls for them. On a machine busy
/// with other test runs one of these tests can outlast the default 30s, so
/// they get the room [_Harness._until]'s own deadlines need.
const _realTime = Timeout(Duration(minutes: 2));

/// Runs [body] where the notifier's SQLite reads may fail: there is no
/// SQLite plugin in a unit test, and the database's own completer reports
/// that failure a second time, unlistened. Anything else still fails.
Future<void> _quietly(Future<void> Function() body) {
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      try {
        await body();
        if (!done.isCompleted) done.complete();
      } catch (error, stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      }
    },
    (error, stack) {
      if (error is MissingPluginException) return;
      if (!done.isCompleted) done.completeError(error, stack);
    },
  );
  return done.future;
}

List<String> _ids(List<FeedItem> items) => [
  for (final item in items) item.game.gameId,
];

/// The real [FeedNotifier] over fake sources: 120 finished strong games
/// from this week, no running events, no followed players; the Most Liked
/// and miniature sources are down.
class _Harness {
  _Harness._(this.container, this.games, this.notifier);

  final ProviderContainer container;
  final _Games games;
  final _ClockedFeed notifier;

  DateTime get clock => notifier.clock;
  set clock(DateTime value) => notifier.clock = value;

  List<String> get ids => _ids(container.read(feedProvider).value ?? const []);

  static Future<_Harness> start() async {
    final games = _Games();
    final notifier = _ClockedFeed();
    final container = ProviderContainer(
      overrides: [
        gameRepositoryProvider.overrideWithValue(games),
        gamebaseRepositoryProvider.overrideWithValue(_NoGamebase()),
        discoveryRepositoryProvider.overrideWithValue(_NoDiscovery()),
        favoritePlayersProviderNew.overrideWith(_NoFavorites.new),
        boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
        feedProvider.overrideWith(() => notifier),
      ],
    );
    addTearDown(container.dispose);
    container.listen(feedProvider, (_, _) {});
    await container.read(feedProvider.future);
    final harness = _Harness._(container, games, notifier);
    await harness.waitForTopUp();
    await harness.waitForReserve();
    return harness;
  }

  /// The opening pages behind the first one have landed.
  Future<void> waitForTopUp() => _until(() => ids.length >= 5);

  Future<void> waitForReserve() => _until(() => notifier.reserveIds != null);

  static Future<void> _until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for the feed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

class _ClockedFeed extends FeedNotifier {
  DateTime clock = DateTime.now();

  @override
  DateTime now() => clock;
}

const _pgn =
    '[Event "Test Open 2026"]\n[Result "1-0"]\n\n'
    '1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf6 4. O-O Nxe4 5. Re1 Nd6 6. Nxe5 Be7 '
    '7. Bf1 Nxe5 8. Rxe5 O-O 9. d4 Bf6 10. Re1 Re8 11. c3 Rxe1 '
    '12. Qxe1 Ne8 13. Bf4 d6 14. Nd2 Bf5 1-0';

class _Games implements GameRepository {
  /// Twelve strong games that just finished, and a hundred weaker ones from
  /// three days ago. Every read carries the strong ones (the newest, as the
  /// real listing does), and they outrank the rest even once shown: only a
  /// rule that keeps shown games out of a pull's first page keeps them from
  /// coming straight back.
  static const int _strong = 12;

  final List<Games> rows = [
    for (var i = 0; i < _strong + 100; i++)
      Games(
        id: 'r$i',
        roundId: 'round-$i',
        roundSlug: 'round-$i',
        tourId: 'tour-${i % 30}',
        tourSlug: 'tour-${i % 30}',
        players: [
          Player(
            name: 'White $i',
            title: 'GM',
            rating: i < _strong ? 2860 : 2260,
            fideId: 1000 + i,
            fed: 'NOR',
            clock: 0,
            team: '',
          ),
          Player(
            name: 'Black $i',
            title: 'GM',
            rating: i < _strong ? 2840 : 2240,
            fideId: 5000 + i,
            fed: 'USA',
            clock: 0,
            team: '',
          ),
        ],
        lastMove: 'f8f5',
        status: '1-0',
        isPgnDeferred: true,
        lastMoveTime: DateTime.now().subtract(
          i < _strong ? Duration(minutes: i) : Duration(days: 3, minutes: i),
        ),
      ),
  ];
  int reads = 0;

  /// The next read waits for this before it answers.
  Completer<void>? stallNext;

  @override
  Future<Map<String, int>> getCurrentEventTourElos({
    int minEventElo = 2300,
  }) async => const {};

  @override
  Future<List<Games>> getFeedCandidateGames({
    required DateTime since,
    List<String>? tourIds,
    int minRating = 2400,
    bool decisiveOnly = false,
    int limit = 60,
    int offset = 0,
  }) async {
    reads++;
    final stall = stallNext;
    if (stall != null) {
      stallNext = null;
      await stall.future;
    }
    final weak = rows.skip(_strong).toList();
    final start = offset % weak.length;
    return [...rows.take(_strong), ...weak.skip(start).take(limit - _strong)];
  }

  @override
  Future<Map<String, String>> getGamePgns(List<String> ids) async => {
    for (final id in ids) id: _pgn,
  };

  @override
  Future<List<Games>> getGamesByMultipleFideIds({
    required List<String> fideIds,
    int limit = 50,
    int offset = 0,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _NoGamebase implements GamebaseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

class _NoDiscovery implements DiscoveryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

class _NoFavorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

class _TestBoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _SettableFeed extends FeedNotifier {
  _SettableFeed(this._items);

  final List<FeedItem> _items;

  @override
  Future<List<FeedItem>> build() async => _items;

  void set(List<FeedItem> items) => state = AsyncData(items);

  @override
  Future<void> loadMore() async {}
}

FeedItem _item(String id) => FeedItem(
  game: GamesTourModel(
    gameId: id,
    whitePlayer: PlayerCard(
      name: 'White',
      federation: '',
      title: 'GM',
      rating: 2700,
      countryCode: '',
      team: null,
    ),
    blackPlayer: PlayerCard(
      name: 'Black',
      federation: '',
      title: 'GM',
      rating: 2690,
      countryCode: '',
      team: null,
    ),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: 'round',
    tourId: 'tour',
  ),
  plies: const [
    FeedPly(fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
  ],
  reason: '',
  eventLabel: 'Test',
  result: '1-0',
);

FeedNews _news(int id) => FeedNews(
  id: id,
  title: 'News $id',
  summary: 'Summary',
  content: 'Body',
  publishedAt: DateTime(2026, 9, 20),
);
