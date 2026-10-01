import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/for_you/for_you_feed_local_storage.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _BroadcastRepository implements GroupBroadcastRepository {
  int calls = 0;
  Future<List<GroupBroadcast>>? result;

  @override
  Future<List<GroupBroadcast>> getForYouGroupBroadcasts({
    int limit = 20,
    int offset = 0,
    List<String>? timeControlFilters,
    int? minElo,
    int? maxElo,
    Set<String>? statusFilters,
  }) async {
    calls++;
    return result ??
        Future.value([
          GroupBroadcast(
            id: 'event-1',
            name: 'Today event',
            createdAt: DateTime.utc(2026, 10, 1),
            search: const [],
          ),
        ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected broadcast call: ${invocation.memberName}');
}

class _GameRepository implements GameRepository {
  int calls = 0;
  int favoriteCalls = 0;
  Future<Map<String, List<Games>>>? result;
  Future<Map<String, List<int>>>? favoriteMatches;

  @override
  Future<Map<String, List<Games>>> getForYouTopGamesByEventIds({
    required List<String> eventIds,
    int boardsPerEvent = 4,
  }) async {
    calls++;
    return result ??
        {
          'event-1': [_game()],
        };
  }

  @override
  Future<Map<String, List<int>>> getForYouFavoritePlayerFideIdsByEventIds({
    required List<String> eventIds,
    required List<int> favoriteFideIds,
  }) async {
    favoriteCalls++;
    return favoriteMatches ?? {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected game call: ${invocation.memberName}');
}

class _FavoritePlayers extends FavoritePlayersNotifierNew {
  _FavoritePlayers(this.players, this.result);
  final List<FavoritePlayer> players;
  final Future<List<FavoritePlayer>>? result;

  @override
  Future<List<FavoritePlayer>> build() async => result ?? players;
}

class _FavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => [];
}

class _Database implements AppDatabase {
  final entries = <String, CacheEntry>{};
  bool failWrites = false;
  Future<CacheEntry?>? readResult;

  @override
  Future<CacheEntry?> getCache({
    required String key,
    String? userId,
    Duration? maxAge,
  }) async => readResult ?? entries[key];

  @override
  Future<void> setCache({
    required String key,
    required String value,
    String? userId,
  }) async {
    if (failWrites) throw StateError('Cache write failed');
    entries[key] = CacheEntry(value: value, cachedAt: DateTime.now());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected database call: ${invocation.memberName}');
}

Games _game() => Games(
  id: 'game-1',
  roundId: 'round-1',
  roundSlug: 'round-1',
  tourId: 'tour-1',
  tourSlug: 'tour-1',
  status: 'ongoing',
  lastMove: 'e2e4',
  players: [
    Player(
      name: 'White',
      title: 'GM',
      rating: 2700,
      fideId: 123,
      fed: 'USA',
      clock: 600,
      team: '',
    ),
    Player(
      name: 'Black',
      title: 'GM',
      rating: 2690,
      fideId: 456,
      fed: 'USA',
      clock: 600,
      team: '',
    ),
  ],
);

ProviderContainer _container({
  required _BroadcastRepository broadcasts,
  required _GameRepository games,
  required ForYouFeedLocalStorage storage,
  Stream<List<String>> liveIds = const Stream.empty(),
  List<FavoritePlayer> favorites = const [],
  Future<List<FavoritePlayer>>? favoriteResult,
}) => ProviderContainer(
  overrides: [
    groupBroadcastRepositoryProvider.overrideWithValue(broadcasts),
    gameRepositoryProvider.overrideWithValue(games),
    forYouFeedLocalStorageProvider.overrideWithValue(storage),
    liveGroupBroadcastIdsProvider.overrideWith((ref) => liveIds),
    liveRoundsIdProvider.overrideWith((ref) => const Stream.empty()),
    liveTourIdProvider.overrideWith((ref) => const Stream.empty()),
    favoritePlayersProviderNew.overrideWith(
      () => _FavoritePlayers(favorites, favoriteResult),
    ),
    favoriteEventsProvider.overrideWith(_FavoriteEvents.new),
  ],
);

Future<void> _flush(WidgetTester tester) async {
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

void main() {
  ForYouFeedCacheEntry cachedPage({String eventId = 'cached-event'}) =>
      ForYouFeedCacheEntry(
        filterKey: forYouFeedCacheFilterKey(defaultFilterPopupState),
        cachedAt: DateTime.now(),
        broadcasts: [
          GroupBroadcast(
            id: eventId,
            name: 'Cached event',
            createdAt: DateTime(2026),
            search: const [],
          ),
        ],
        gamesByEventId: const {},
        hasMore: false,
      );

  testWidgets('Today loads while the startup live-ID stream is pending', (
    tester,
  ) async {
    final liveIds = StreamController<List<String>>();
    final broadcasts = _BroadcastRepository();
    final games = _GameRepository();
    final container = _container(
      broadcasts: broadcasts,
      games: games,
      storage: ForYouFeedLocalStorage(_Database()),
      liveIds: liveIds.stream,
    );
    addTearDown(() {
      container.dispose();
      unawaited(liveIds.close());
    });

    container.read(forYouEventsProvider);
    await _flush(tester);

    final state = container.read(forYouEventsProvider);
    expect(broadcasts.calls, 1);
    expect(state.isLoading, isFalse);
    expect(state.events.map((event) => event.id), ['event-1']);
    expect(games.calls, 1);

    liveIds.add(['event-1']);
    await _flush(tester);
    expect(
      container.read(forYouEventsProvider).events.single.tourEventCategory,
      TourEventCategory.live,
    );
    expect(broadcasts.calls, 1);
  });

  testWidgets('Today renders boards before favorite matching finishes', (
    tester,
  ) async {
    final counts = Completer<Map<String, List<int>>>();
    final games = _GameRepository()..favoriteMatches = counts.future;
    final container = _container(
      broadcasts: _BroadcastRepository(),
      games: games,
      storage: ForYouFeedLocalStorage(_Database()),
      liveIds: Stream.value([]),
      favorites: [
        FavoritePlayer(
          id: 'favorite',
          userId: 'user',
          fideId: '123',
          playerName: 'Favorite player',
          metadata: const {},
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(forYouEventsProvider);
    await _flush(tester);

    expect(container.read(forYouEventsProvider).isLoading, isFalse);
    expect(
      container
          .read(forYouTopGamesSnapshotCacheProvider)['event-1']
          ?.visibleGames
          .single
          .gameId,
      'game-1',
    );
    counts.complete({
      'event-1': [123],
    });
    await _flush(tester);
    expect(
      container.read(eventFavoritePlayersCacheProvider)['event-1']?.count,
      1,
    );
    expect(games.favoriteCalls, 1);
  });

  testWidgets(
    'live IDs arriving during board loading survive first-page publication',
    (tester) async {
      final liveIds = StreamController<List<String>>();
      final boards = Completer<Map<String, List<Games>>>();
      final container = _container(
        broadcasts: _BroadcastRepository(),
        games: _GameRepository()..result = boards.future,
        storage: ForYouFeedLocalStorage(_Database()),
        liveIds: liveIds.stream,
      );
      addTearDown(() {
        container.dispose();
        unawaited(liveIds.close());
      });
      container.read(forYouEventsProvider);
      await _flush(tester);
      liveIds.add(['event-1']);
      await _flush(tester);
      boards.complete({
        'event-1': [_game()],
      });
      await _flush(tester);
      expect(
        container.read(forYouEventsProvider).events.single.tourEventCategory,
        TourEventCategory.live,
      );
    },
  );

  testWidgets('late favorite hydration still promotes matching events once', (
    tester,
  ) async {
    final favorites = Completer<List<FavoritePlayer>>();
    final games = _GameRepository()
      ..favoriteMatches = Future.value({
        'event-2': [123],
      });
    final container = _container(
      broadcasts: _BroadcastRepository()
        ..result = Future.value([
          GroupBroadcast(
            id: 'event-1',
            name: 'Higher Elo',
            createdAt: DateTime(2026),
            search: const [],
            maxAvgElo: 2800,
          ),
          GroupBroadcast(
            id: 'event-2',
            name: 'Favorite player event',
            createdAt: DateTime(2026),
            search: const [],
            maxAvgElo: 2700,
          ),
        ]),
      games: games,
      storage: ForYouFeedLocalStorage(_Database()),
      favoriteResult: favorites.future,
    );
    addTearDown(container.dispose);
    container.read(forYouEventsProvider);
    await _flush(tester);
    expect(container.read(forYouEventsProvider).isLoading, isFalse);
    expect(
      container.read(forYouEventsProvider).events.map((event) => event.id),
      ['event-1', 'event-2'],
    );
    favorites.complete([
      FavoritePlayer(
        id: 'favorite',
        userId: 'user',
        fideId: '123',
        playerName: 'Favorite player',
        metadata: const {},
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ]);
    await _flush(tester);
    expect(
      container.read(forYouEventsProvider).events.map((event) => event.id),
      ['event-2', 'event-1'],
    );
    expect(games.favoriteCalls, 1);
  });

  testWidgets(
    'slow cache reads and failed writes do not delay a fresh Today page',
    (tester) async {
      final read = Completer<CacheEntry?>();
      final database = _Database()
        ..readResult = read.future
        ..failWrites = true;
      final container = _container(
        broadcasts: _BroadcastRepository(),
        games: _GameRepository(),
        storage: ForYouFeedLocalStorage(database),
      );
      addTearDown(container.dispose);
      container.read(forYouEventsProvider);
      await _flush(tester);
      expect(container.read(forYouEventsProvider).isLoading, isFalse);
      expect(container.read(forYouEventsProvider).events.single.id, 'event-1');
      read.complete(null);
      await _flush(tester);
    },
  );

  testWidgets('hot restart restores Today while its event RPC is stalled', (
    tester,
  ) async {
    final database = _Database();
    var container = _container(
      broadcasts: _BroadcastRepository(),
      games: _GameRepository(),
      storage: ForYouFeedLocalStorage(database),
      liveIds: Stream.value([]),
    );
    container.read(forYouEventsProvider);
    await _flush(tester);
    expect(container.read(forYouEventsProvider).isLoading, isFalse);
    container.dispose();

    final eventRequest = Completer<List<GroupBroadcast>>();
    final broadcasts = _BroadcastRepository()..result = eventRequest.future;
    container = _container(
      broadcasts: broadcasts,
      games: _GameRepository(),
      storage: ForYouFeedLocalStorage(database),
    );
    addTearDown(container.dispose);
    container.read(forYouEventsProvider);
    await _flush(tester);

    expect(broadcasts.calls, 1);
    expect(
      container.read(forYouEventsProvider).events.map((event) => event.id),
      ['event-1'],
    );
    expect(
      container
          .read(forYouTopGamesSnapshotCacheProvider)['event-1']
          ?.visibleGames
          .single
          .gameId,
      'game-1',
    );

    // A successful empty response must replace the saved page, never revive it.
    eventRequest.complete([]);
    await _flush(tester);
    expect(container.read(forYouEventsProvider).events, isEmpty);
    expect(container.read(forYouTopGamesSnapshotCacheProvider), isEmpty);
  });

  testWidgets(
    'a late disk read cannot revive events after a fresh empty response',
    (tester) async {
      final diskRead = Completer<CacheEntry?>();
      final container = _container(
        broadcasts: _BroadcastRepository()..result = Future.value([]),
        games: _GameRepository(),
        storage: ForYouFeedLocalStorage(
          _Database()..readResult = diskRead.future,
        ),
      );
      addTearDown(container.dispose);
      container.read(forYouEventsProvider);
      await _flush(tester);
      expect(container.read(forYouEventsProvider).isLoading, isFalse);
      diskRead.complete(
        CacheEntry(
          value: jsonEncode(cachedPage().toJson()),
          cachedAt: DateTime.now(),
        ),
      );
      await _flush(tester);
      expect(container.read(forYouEventsProvider).events, isEmpty);
    },
  );

  testWidgets('late board responses are harmless after Today is disposed', (
    tester,
  ) async {
    final boards = Completer<Map<String, List<Games>>>();
    final container = _container(
      broadcasts: _BroadcastRepository(),
      games: _GameRepository()..result = boards.future,
      storage: ForYouFeedLocalStorage(_Database()),
    );
    container.read(forYouEventsProvider);
    await _flush(tester);
    container.dispose();
    boards.complete({
      'event-1': [_game()],
    });
    await _flush(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached Today survives a failed refresh and recovers on retry', (
    tester,
  ) async {
    final database = _Database();
    final storage = ForYouFeedLocalStorage(database);
    await storage.write(cachedPage());
    final request = Completer<List<GroupBroadcast>>();
    final broadcasts = _BroadcastRepository()..result = request.future;
    final container = _container(
      broadcasts: broadcasts,
      games: _GameRepository(),
      storage: storage,
    );
    addTearDown(container.dispose);
    container.read(forYouEventsProvider);
    await _flush(tester);
    request.completeError(StateError('Database error: 522'));
    await _flush(tester);
    expect(container.read(forYouEventsProvider).isLoading, isFalse);
    expect(
      container.read(forYouEventsProvider).events.single.id,
      'cached-event',
    );
    expect(container.read(forYouEventsProvider).error, contains('522'));
    broadcasts.result = null;
    unawaited(container.read(forYouEventsProvider.notifier).refresh());
    await _flush(tester);
    expect(container.read(forYouEventsProvider).events.single.id, 'event-1');
    expect(container.read(forYouEventsProvider).error, isNull);
  });

  test('corrupt saved data is treated as a cache miss', () async {
    final database = _Database();
    final storage = ForYouFeedLocalStorage(database);
    await storage.write(cachedPage());
    final key = database.entries.keys.single;
    database.entries[key] = CacheEntry(
      value: 'broken JSON',
      cachedAt: DateTime.now(),
    );
    expect(await storage.read(filterKey: cachedPage().filterKey), isNull);
  });

  test('saved Today data expires and cannot cross filters or midnight', () {
    final now = DateTime(2026, 10, 1, 12);
    final key = forYouFeedCacheFilterKey(defaultFilterPopupState);
    ForYouFeedCacheEntry entry(DateTime cachedAt) => ForYouFeedCacheEntry(
      filterKey: key,
      cachedAt: cachedAt,
      broadcasts: const [],
      gamesByEventId: const {},
      hasMore: false,
    );

    expect(entry(now).isFreshFor(key, now), isTrue);
    expect(entry(now).isFreshFor('another filter', now), isFalse);
    expect(
      entry(now.subtract(const Duration(minutes: 6))).isFreshFor(key, now),
      isFalse,
    );
    expect(
      entry(now.add(const Duration(seconds: 1))).isFreshFor(key, now),
      isFalse,
    );
    expect(
      entry(
        DateTime(2026, 9, 30, 23, 59),
      ).isFreshFor(key, DateTime(2026, 10, 1, 0, 1)),
      isFalse,
    );
  });
}
