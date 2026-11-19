import 'dart:async';

import 'package:chessever2/main.dart' show pageRouteObserver;
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/for_you/for_you_feed_local_storage.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/widget/for_you_games_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Today pages on whenever its end is within reach, not only on a scroll,
/// and its load-more slot holds one height for as long as a page can
/// follow, so the bars and the list never jump at the page point. A page
/// that fails is not asked for again on every frame: the list checks its
/// end once per new list, and the feed backs off after a failure.
void main() {
  const slot = ValueKey('for_you_load_more_slot');

  testWidgets('a first page that ends short of the screen pages on by '
      'itself', (tester) async {
    // Every section of the first page hides itself (no boards): nothing
    // to scroll, and nothing changes size once laid out.
    final broadcasts = _Pages(pageCount: 3);
    final container = _container(broadcasts, _Boards(empty: true));
    await _pumpToday(tester, container);

    for (var i = 0; i < 10 && broadcasts.offsets.length < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(broadcasts.offsets, [0, 20, 40]);
    await _unmount(tester);
  });

  testWidgets('the load-more slot keeps one height while the next page '
      'loads, and leaves with the last page', (tester) async {
    final broadcasts = _Pages(pageCount: 2);
    final hold = Completer<void>();
    broadcasts.holdFrom = 20;
    broadcasts.hold = hold.future;
    final container = _container(broadcasts, _Boards());
    await _pumpToday(tester, container);
    final scroll = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    expect(broadcasts.offsets, [0, 20]);
    // Loading the next page: the slot is still there, at its height.
    expect(find.byKey(slot), findsOneWidget);
    final height = tester.getSize(find.byKey(slot)).height;
    expect(height, greaterThan(0));

    hold.complete();
    await tester.pump();
    await tester.pump();
    // The last page landed: nothing more can follow.
    expect(container.read(forYouEventsProvider).hasMore, isFalse);
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pump();
    expect(find.byKey(slot), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a next page that fails is asked for once, not on every '
      'frame, while the reader waits at the end', (tester) async {
    final broadcasts = _Pages(pageCount: 3)..failFrom = 20;
    final container = _container(broadcasts, _Boards());
    await _pumpToday(tester, container);
    final scroll = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    scroll.jumpTo(scroll.maxScrollExtent);
    // Two seconds of frames with the reader parked at the end, the bars
    // and the list still: one request for the page, not one per frame.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(broadcasts.offsets.where((offset) => offset == 20), hasLength(1));
    final state = container.read(forYouEventsProvider);
    expect(state.error, isNotNull);
    expect(state.hasMore, isTrue);
    // The slot still holds its place at the end.
    expect(find.byKey(slot), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a failed next page waits out a growing back-off, and a page '
      'that lands clears it', (tester) async {
    var now = DateTime.utc(2026, 11, 19, 12);
    final broadcasts = _Pages(pageCount: 4);
    final container = _container(
      broadcasts,
      _Boards(),
      overrides: [
        forYouEventsProvider.overrideWith((ref) {
          ref.keepAlive();
          return ForYouNotifier(ref, now: () => now);
        }),
      ],
    );
    await _pumpToday(tester, container);
    // The reader is at the top of a full page: only the test asks for more.
    expect(broadcasts.offsets, [0]);
    final notifier = container.read(forYouEventsProvider.notifier);
    int asked() => broadcasts.offsets.where((o) => o == 20).length;
    Future<void> loadMore() async {
      unawaited(notifier.loadMore());
      await tester.pump();
      await tester.pump();
    }

    broadcasts.failFrom = 20;
    await loadMore();
    expect(asked(), 1);
    expect(container.read(forYouEventsProvider).error, isNotNull);

    // Two seconds after the first failure.
    await loadMore();
    now = now.add(const Duration(milliseconds: 1999));
    await loadMore();
    expect(asked(), 1);
    now = now.add(const Duration(milliseconds: 1));
    await loadMore();
    expect(asked(), 2);

    // Four after the second.
    now = now.add(const Duration(seconds: 3));
    await loadMore();
    expect(asked(), 2);
    now = now.add(const Duration(seconds: 1));
    await loadMore();
    expect(asked(), 3);

    // The page lands after the back-off; the next one goes at once.
    broadcasts.failFrom = null;
    now = now.add(const Duration(seconds: 8));
    await loadMore();
    expect(asked(), 4);
    expect(container.read(forYouEventsProvider).error, isNull);
    await loadMore();
    expect(broadcasts.offsets.where((o) => o == 40), hasLength(1));
    await _unmount(tester);
  });

  test('the back-off doubles from two seconds up to a minute', () {
    expect(
      [
        for (var failures = 1; failures <= 8; failures++) failures,
      ].map((failures) => forYouLoadMoreBackoff(failures).inSeconds),
      [2, 4, 8, 16, 32, 60, 60, 60],
    );
  });

  testWidgets('the list ends clear of the filter and Live first', (
    tester,
  ) async {
    final broadcasts = _Pages(pageCount: 1, lastPageSize: 3);
    final container = _container(broadcasts, _Boards());
    await _pumpToday(tester, container);

    final list = tester.widget<ListView>(find.byType(ListView));
    final reach = InkFabStack.reach(
      tester.element(find.byType(ListView)),
      smallAbove: 1,
    );
    expect(list.padding!.resolve(TextDirection.ltr).bottom, greaterThan(reach));
    await _unmount(tester);
  });
}

/// The feed by pages of 20; the last one [lastPageSize] long. Pages from
/// [holdFrom] wait on [hold].
class _Pages implements GroupBroadcastRepository {
  _Pages({required this.pageCount, this.lastPageSize = 5});

  final int pageCount;
  final int lastPageSize;
  final List<int> offsets = [];
  int? holdFrom;
  Future<void>? hold;

  /// Pages from here fail, as a server error does.
  int? failFrom;

  @override
  Future<List<GroupBroadcast>> getForYouGroupBroadcasts({
    int limit = 20,
    int offset = 0,
    List<String>? timeControlFilters,
    int? minElo,
    int? maxElo,
    Set<String>? statusFilters,
  }) async {
    offsets.add(offset);
    final from = holdFrom;
    if (from != null && offset >= from) await hold;
    final failing = failFrom;
    if (failing != null && offset >= failing) {
      throw Exception('page $offset failed');
    }
    final page = offset ~/ limit;
    if (page >= pageCount) return const [];
    final size = page == pageCount - 1 ? lastPageSize : limit;
    return [for (var i = 0; i < size; i++) _broadcast('e${offset + i}')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected broadcast call: ${invocation.memberName}');
}

class _Boards implements GameRepository {
  _Boards({this.empty = false});

  final bool empty;

  @override
  Future<Map<String, List<Games>>> getForYouTopGamesByEventIds({
    required List<String> eventIds,
    int boardsPerEvent = 4,
  }) async => {
    for (final id in eventIds) id: empty ? const <Games>[] : [_game(id)],
  };

  @override
  Future<Map<String, List<int>>> getForYouFavoritePlayerFideIdsByEventIds({
    required List<String> eventIds,
    required List<int> favoriteFideIds,
  }) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected game call: ${invocation.memberName}');
}

class _FavoritePlayers extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => [];
}

class _FavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}

class _Database implements AppDatabase {
  @override
  Future<CacheEntry?> getCache({
    required String key,
    String? userId,
    Duration? maxAge,
  }) async => null;

  @override
  Future<void> setCache({
    required String key,
    required String value,
    String? userId,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected database call: ${invocation.memberName}');
}

GroupBroadcast _broadcast(String id) => GroupBroadcast(
  id: id,
  name: id,
  createdAt: DateTime.utc(2026, 10, 1),
  search: const [],
);

Games _game(String eventId) => Games(
  id: 'g_$eventId',
  roundId: 'r_$eventId',
  roundSlug: 'r_$eventId',
  tourId: 't_$eventId',
  tourSlug: 't_$eventId',
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

ProviderContainer _container(
  _Pages broadcasts,
  _Boards boards, {
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      groupBroadcastRepositoryProvider.overrideWithValue(broadcasts),
      gameRepositoryProvider.overrideWithValue(boards),
      forYouFeedLocalStorageProvider.overrideWithValue(
        ForYouFeedLocalStorage(_Database()),
      ),
      liveGroupBroadcastIdsProvider.overrideWith((ref) => Stream.value([])),
      liveRoundsIdProvider.overrideWith((ref) => const Stream.empty()),
      liveTourIdProvider.overrideWith((ref) => const Stream.empty()),
      favoritePlayersProviderNew.overrideWith(_FavoritePlayers.new),
      favoriteEventsProvider.overrideWith(_FavoriteEvents.new),
      forYouTodayTabActiveProvider.overrideWith((ref) => true),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpToday(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view
    ..physicalSize = const Size(393 * 3, 852 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final scrollController = ScrollController();
  addTearDown(scrollController.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        navigatorObservers: [pageRouteObserver],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: ForYouGamesWidget(scrollController: scrollController),
            );
          },
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(Duration.zero);
  }
}

/// Unmounts inside the fake clock so no timer outlives the test.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 61));
}
