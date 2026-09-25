import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/widget/events_load_error_state.dart';
import 'package:chessever2/screens/group_event/widget/upcoming_events_empty_state.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory stand-in for the SQLite cache the event lists persist into.
class _FakeAppDatabase implements AppDatabase {
  final Map<String, String> cache = {};
  final Map<String, int> ints = {};

  @override
  Future<int?> getInt(String key) async => ints[key];

  @override
  Future<CacheEntry?> getCache({
    required String key,
    String? userId,
    Duration? maxAge,
  }) async {
    final value = cache[key];
    if (value == null) return null;
    return CacheEntry(value: value, cachedAt: DateTime.now());
  }

  @override
  Future<void> setCacheAndInt({
    required String cacheKey,
    required String cacheValue,
    String? userId,
    required String intKey,
    required int intValue,
  }) async {
    cache[cacheKey] = cacheValue;
    ints[intKey] = intValue;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UpcomingCall {
  const _UpcomingCall(this.orderBy, this.ascending, this.limit);

  final String orderBy;
  final bool ascending;
  final int? limit;
}

class _FakeGroupBroadcastRepository extends GroupBroadcastRepository {
  _FakeGroupBroadcastRepository({
    this.upcoming = const [],
    this.current = const [],
    this.upcomingFailures = 0,
  });

  final List<GroupBroadcast> upcoming;
  final List<GroupBroadcast> current;

  /// How many upcoming reads fail before one succeeds.
  int upcomingFailures;
  final upcomingCalls = <_UpcomingCall>[];
  int currentCalls = 0;

  @override
  Future<List<GroupBroadcast>> getUpcomingGroupBroadcasts({
    int? limit,
    int? offset,
    String orderBy = 'max_avg_elo',
    bool ascending = false,
  }) async {
    upcomingCalls.add(_UpcomingCall(orderBy, ascending, limit));
    if (upcomingFailures > 0) {
      upcomingFailures--;
      throw Exception('upcoming view unavailable');
    }
    return upcoming;
  }

  @override
  Future<List<GroupBroadcast>> getCurrentGroupBroadcasts({
    int? limit,
    int? offset,
    String orderBy = 'max_avg_elo',
    bool ascending = false,
    List<String>? timeControlFilters,
    int? minElo,
    int? maxElo,
  }) async {
    currentCalls++;
    return current;
  }
}

class _FakeFavoriteEventsNotifier extends FavoriteEventsNotifier {
  _FakeFavoriteEventsNotifier(this._favorites);

  final List<FavoriteEvent> _favorites;

  @override
  Future<List<FavoriteEvent>> build() async => _favorites;
}

GroupBroadcast _broadcast(
  String id, {
  DateTime? start,
  int? elo,
  String? name,
}) {
  return GroupBroadcast(
    id: id,
    createdAt: DateTime.utc(2026),
    name: name ?? 'Event $id',
    search: [name ?? 'Event $id'],
    maxAvgElo: elo,
    dateStart: start,
    dateEnd: start?.add(const Duration(days: 3)),
    timeControl: 'standard',
  );
}

GroupEventCardModel _card(String id, {DateTime? start, int elo = 0}) {
  return GroupEventCardModel(
    id: id,
    title: 'Event $id',
    dates: '',
    maxAvgElo: elo,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.upcoming,
    timeControl: 'Standard',
    endDate: null,
    startDate: start,
  );
}

FavoriteEvent _favorite(String eventId) {
  final at = DateTime.utc(2026, 9, 1);
  return FavoriteEvent(
    id: 'fav_$eventId',
    userId: 'user',
    eventId: eventId,
    eventName: 'Event $eventId',
    metadata: const {},
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'http://localhost:54321',
        publishableKey: 'test-anon-key',
      );
    }
  });

  group('Events segments', () {
    test('read Past | Current | Upcoming, in that order', () {
      expect(visibleEventCategories(hasActiveSearch: false), [
        GroupEventCategory.past,
        GroupEventCategory.current,
        GroupEventCategory.upcoming,
      ]);
    });

    test('append Search only while a query is active', () {
      expect(visibleEventCategories(hasActiveSearch: true), [
        GroupEventCategory.past,
        GroupEventCategory.current,
        GroupEventCategory.upcoming,
        GroupEventCategory.search,
      ]);
    });

    test('clearing a search started on Upcoming returns to Upcoming', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedGroupCategoryProvider.notifier).state =
          GroupEventCategory.upcoming;

      final controller = container.read(groupEventSearchTabControllerProvider);
      controller.showSearch();
      controller.restorePreviousTab();

      expect(
        container.read(selectedGroupCategoryProvider),
        GroupEventCategory.upcoming,
      );
    });
  });

  group('sortUpcomingEvents', () {
    test('orders by start date, soonest first, undated last', () {
      final sorted = sortUpcomingEvents([
        _card('later', start: DateTime.utc(2026, 10, 20)),
        _card('undated'),
        _card('soon', start: DateTime.utc(2026, 9, 25)),
        _card('mid', start: DateTime.utc(2026, 10, 1)),
      ]);

      expect(sorted.map((e) => e.id), ['soon', 'mid', 'later', 'undated']);
    });

    test('pins starred events on top, each group soonest first', () {
      final sorted = sortUpcomingEvents(
        [
          _card('a', start: DateTime.utc(2026, 9, 25)),
          _card('starred-late', start: DateTime.utc(2026, 12, 1)),
          _card('b', start: DateTime.utc(2026, 9, 26)),
          _card('starred-soon', start: DateTime.utc(2026, 11, 1)),
        ],
        starredIds: {'starred-late', 'starred-soon'},
      );

      expect(sorted.map((e) => e.id), [
        'starred-soon',
        'starred-late',
        'a',
        'b',
      ]);
    });

    test('breaks same-start ties on Elo, strongest first', () {
      final start = DateTime.utc(2026, 10, 1);
      final sorted = sortUpcomingEvents([
        _card('open', start: start, elo: 2300),
        _card('elite', start: start, elo: 2750),
      ]);

      expect(sorted.map((e) => e.id), ['elite', 'open']);
    });
  });

  group('Upcoming cache', () {
    test('reads the upcoming view soonest-first under its own key', () async {
      final db = _FakeAppDatabase();
      final repo = _FakeGroupBroadcastRepository(
        upcoming: [_broadcast('gb_up', start: DateTime.utc(2026, 10, 1))],
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          groupBroadcastRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final events = await container
          .read(groupBroadcastLocalStorage(GroupEventCategory.upcoming))
          .refresh();

      expect(events.map((e) => e.id), ['gb_up']);
      expect(repo.upcomingCalls, hasLength(1));
      expect(repo.upcomingCalls.single.orderBy, 'date_start');
      expect(repo.upcomingCalls.single.ascending, isTrue);
      expect(repo.upcomingCalls.single.limit, kUpcomingEventsFetchLimit);
      expect(db.cache.keys, contains('group_broadcast_upcoming'));
    });

    test('a Search refresh never saves an empty list over Current', () async {
      final db = _FakeAppDatabase();
      final repo = _FakeGroupBroadcastRepository(
        current: [_broadcast('gb_now', start: DateTime.utc(2026, 9, 20))],
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          groupBroadcastRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final events = await container
          .read(groupBroadcastLocalStorage(GroupEventCategory.search))
          .refresh();

      expect(events.map((e) => e.id), ['gb_now']);
      expect(repo.currentCalls, 1);
      expect(repo.upcomingCalls, isEmpty);
      expect(db.cache['group_broadcast_current'], contains('gb_now'));
    });
  });

  test(
    'the Upcoming tab lists the upcoming view soonest first, starred on top',
    () async {
      // Relative to now: the card model derives "upcoming" from the clock.
      final now = DateTime.now();
      final repo = _FakeGroupBroadcastRepository(
        upcoming: [
          _broadcast(
            'gb_far',
            start: now.add(const Duration(days: 60)),
            elo: 2780,
          ),
          _broadcast(
            'gb_next',
            start: now.add(const Duration(days: 2)),
            elo: 2400,
          ),
          _broadcast(
            'gb_starred',
            start: now.add(const Duration(days: 90)),
            elo: 2200,
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(_FakeAppDatabase()),
          groupBroadcastRepositoryProvider.overrideWithValue(repo),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream.value(const <String>[]),
          ),
          favoriteEventsProvider.overrideWith(
            () => _FakeFavoriteEventsNotifier([_favorite('gb_starred')]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(favoriteEventsProvider.future);

      container.read(selectedGroupCategoryProvider.notifier).state =
          GroupEventCategory.upcoming;
      final subscription = container.listen(
        groupEventScreenProvider,
        (_, __) {},
      );
      addTearDown(subscription.close);

      for (var i = 0; i < 20 && !subscription.read().hasValue; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final events = subscription.read().requireValue;
      expect(events.map((e) => e.id), ['gb_starred', 'gb_next', 'gb_far']);
      expect(events.map((e) => e.tourEventCategory).toSet(), {
        TourEventCategory.upcoming,
      });
    },
  );

  group('isStillUpcoming', () {
    final now = DateTime.utc(2026, 9, 23, 12);

    test('keeps an event that has not started yet', () {
      expect(
        isStillUpcoming(
          _broadcast('soon', start: DateTime.utc(2026, 9, 25)),
          now: now,
        ),
        isTrue,
      );
    });

    test('drops an event whose start has already passed', () {
      // The August rows the upcoming view still carries in test data.
      expect(
        isStillUpcoming(
          _broadcast('august', start: DateTime.utc(2026, 8, 14)),
          now: now,
        ),
        isFalse,
      );
      // Started earlier today: it belongs to Current now.
      expect(
        isStillUpcoming(
          _broadcast('this-morning', start: DateTime.utc(2026, 9, 23, 9)),
          now: now,
        ),
        isFalse,
      );
    });

    test('an event starting this very instant is no longer upcoming', () {
      expect(isStillUpcoming(_broadcast('now', start: now), now: now), isFalse);
    });

    test('keeps an undated event unless its end has passed', () {
      expect(isStillUpcoming(_broadcast('undated'), now: now), isTrue);
      final endedOnly = GroupBroadcast(
        id: 'ended',
        createdAt: DateTime.utc(2026),
        name: 'Ended',
        search: const ['Ended'],
        dateEnd: DateTime.utc(2026, 8, 30),
        timeControl: 'standard',
      );
      expect(isStillUpcoming(endedOnly, now: now), isFalse);
    });

    test('dropStartedUpcomingBroadcasts keeps the order of the rest', () {
      final kept = dropStartedUpcomingBroadcasts([
        _broadcast('b', start: DateTime.utc(2026, 10, 2)),
        _broadcast('stale', start: DateTime.utc(2026, 8, 1)),
        _broadcast('a', start: DateTime.utc(2026, 9, 30)),
        _broadcast('undated'),
      ], now: now);

      expect(kept.map((e) => e.id), ['b', 'a', 'undated']);
    });
  });

  group('Upcoming tab load', () {
    ProviderContainer upcomingContainer(_FakeGroupBroadcastRepository repo) {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(_FakeAppDatabase()),
          groupBroadcastRepositoryProvider.overrideWithValue(repo),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream.value(const <String>[]),
          ),
          favoriteEventsProvider.overrideWith(
            () => _FakeFavoriteEventsNotifier(const []),
          ),
        ],
      );
      container.read(selectedGroupCategoryProvider.notifier).state =
          GroupEventCategory.upcoming;
      return container;
    }

    Future<AsyncValue<List<GroupEventCardModel>>> settle(
      ProviderSubscription<AsyncValue<List<GroupEventCardModel>>> sub,
    ) async {
      for (var i = 0; i < 20 && sub.read().isLoading; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return sub.read();
    }

    test('never lists an event whose start date already passed', () async {
      final now = DateTime.now();
      final repo = _FakeGroupBroadcastRepository(
        upcoming: [
          _broadcast(
            'gb_august',
            start: now.subtract(const Duration(days: 40)),
            elo: 2800,
          ),
          _broadcast('gb_next', start: now.add(const Duration(days: 3))),
          _broadcast(
            'gb_started_today',
            start: now.subtract(const Duration(hours: 2)),
          ),
        ],
      );
      final container = upcomingContainer(repo);
      addTearDown(container.dispose);
      await container.read(favoriteEventsProvider.future);

      final sub = container.listen(groupEventScreenProvider, (_, __) {});
      addTearDown(sub.close);

      final events = (await settle(sub)).requireValue;
      expect(events.map((e) => e.id), ['gb_next']);
    });

    test('only stale rows is a successful empty list, not an error', () async {
      final repo = _FakeGroupBroadcastRepository(
        upcoming: [
          _broadcast(
            'gb_august',
            start: DateTime.now().subtract(const Duration(days: 40)),
          ),
        ],
      );
      final container = upcomingContainer(repo);
      addTearDown(container.dispose);

      final sub = container.listen(groupEventScreenProvider, (_, __) {});
      addTearDown(sub.close);

      final result = await settle(sub);
      expect(result.hasError, isFalse);
      expect(result.requireValue, isEmpty);
    });

    test('a failed load with nothing cached is an error, and Retry re-runs '
        'the load', () async {
      final repo = _FakeGroupBroadcastRepository(
        upcoming: [
          _broadcast(
            'gb_next',
            start: DateTime.now().add(const Duration(days: 3)),
          ),
        ],
        upcomingFailures: 1,
      );
      final container = upcomingContainer(repo);
      addTearDown(container.dispose);

      final sub = container.listen(groupEventScreenProvider, (_, __) {});
      addTearDown(sub.close);

      final failed = await settle(sub);
      expect(failed.hasError, isTrue);
      expect(repo.upcomingCalls, hasLength(1));

      // What the error state's Retry does.
      await container.read(groupEventScreenProvider.notifier).loadTours();

      final recovered = sub.read();
      expect(recovered.hasError, isFalse);
      expect(recovered.requireValue.map((e) => e.id), ['gb_next']);
      expect(repo.upcomingCalls, hasLength(2));
    });
  });

  group('EventsLoadErrorState', () {
    Future<void> pump(WidgetTester tester, {required VoidCallback onRetry}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: EventsLoadErrorState(
                  error: Exception('upcoming view unavailable'),
                  fallbackMessage: "Couldn't load upcoming events.",
                  onRetry: onRetry,
                ),
              );
            },
          ),
        ),
      );
    }

    testWidgets('says the load failed and never claims nothing is scheduled', (
      tester,
    ) async {
      await pump(tester, onRetry: () {});

      expect(find.text("Couldn't load upcoming events."), findsOneWidget);
      expect(find.text('Nothing scheduled yet'), findsNothing);
      // The raw exception text never reaches the screen.
      expect(find.textContaining('unavailable'), findsNothing);
    });

    testWidgets('Retry runs the load again', (tester) async {
      var retries = 0;
      await pump(tester, onRetry: () => retries++);

      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('stays scrollable so pull-to-refresh also retries', (
      tester,
    ) async {
      await pump(tester, onRetry: () {});

      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollable.physics, isA<AlwaysScrollableScrollPhysics>());
    });
  });

  group('UpcomingEventsEmptyState', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool filtersActive,
      required VoidCallback onReset,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: UpcomingEventsEmptyState(
                  filtersActive: filtersActive,
                  onResetFilters: onReset,
                ),
              );
            },
          ),
        ),
      );
    }

    testWidgets('says nothing is scheduled when no filter hides events', (
      tester,
    ) async {
      await pump(tester, filtersActive: false, onReset: () {});

      expect(find.text('Nothing scheduled yet'), findsOneWidget);
      expect(find.text('Reset filters'), findsNothing);
    });

    testWidgets('offers a working reset when filters hide every event', (
      tester,
    ) async {
      var resets = 0;
      await pump(tester, filtersActive: true, onReset: () => resets++);

      expect(
        find.text('No upcoming events match your filters'),
        findsOneWidget,
      );
      await tester.tap(find.text('Reset filters'));
      expect(resets, 1);
    });

    testWidgets('stays scrollable so pull-to-refresh reaches an empty tab', (
      tester,
    ) async {
      await pump(tester, filtersActive: false, onReset: () {});

      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollable.physics, isA<AlwaysScrollableScrollPhysics>());
    });
  });
}
