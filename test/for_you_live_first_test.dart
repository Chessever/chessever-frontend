import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/for_you/for_you_feed_local_storage.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Trello #1420, the For You tab (labelled Home): Live first floats over
/// Today while an event is live (or while it is on), in words that count the
/// live events, on the flag the Events tab uses, and lists the Today feed's
/// live events first, including ones below the pages it has loaded.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await SharedPreferencesService.instance.initialize();
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'http://localhost:54321',
        publishableKey: 'test-anon-key',
      );
    }
  });

  group('Today feed', () {
    test(
      'lists live events first, and off restores its order exactly',
      () async {
        final feed = _Feed([_gb('a', 2900), _gb('b', 2800), _gb('c', 2700)]);
        final container = _container(feed, liveIds: const ['c']);
        await _loaded(container);
        expect(_ids(container), ['a', 'b', 'c']);

        _flag(container).state = true;
        expect(_ids(container), ['c', 'a', 'b']);

        _flag(container).state = false;
        expect(_ids(container), ['a', 'b', 'c']);
      },
    );

    test('a feed built while Live first is on loads live first', () async {
      final feed = _Feed([_gb('a', 2900), _gb('b', 2800), _gb('c', 2700)]);
      final container = _container(feed, liveIds: const ['c']);
      _flag(container).state = true;
      await _loaded(container);

      expect(_ids(container), ['c', 'a', 'b']);
    });

    test('pulls in a live event ranked below the loaded pages', () async {
      // 25 events by rating: the first page holds 20, the live one is 24th.
      final feed = _Feed([
        for (var i = 0; i < 25; i++) _gb('e$i', 2800 - i * 10),
      ]);
      final container = _container(feed, liveIds: const ['e23']);
      await _loaded(container);
      final firstPage = _ids(container);
      expect(firstPage, hasLength(20));
      expect(firstPage, isNot(contains('e23')));

      final notifier = container.read(forYouEventsProvider.notifier);
      expect(await notifier.hasLiveEvent(), isTrue);
      expect(feed.fetchedByIds, [
        ['e23'],
      ]);

      _flag(container).state = true;
      expect(_ids(container).first, 'e23');
      expect(_ids(container), hasLength(21));
      // Its boards were fetched with it, so its section can draw.
      expect(
        container.read(forYouTopGamesSnapshotCacheProvider),
        contains('e23'),
      );

      // Off, the feed is the first page again, as it was.
      _flag(container).state = false;
      expect(_ids(container), firstPage);

      // On again: a page that brings the event in takes it over, once.
      _flag(container).state = true;
      expect(await notifier.hasLiveEvent(), isTrue);
      expect(_ids(container).first, 'e23');
      await notifier.loadMore();
      final all = _ids(container);
      expect(all.first, 'e23');
      expect(all, hasLength(25));
      expect(all.toSet(), hasLength(25));
      // And keeps it in its own place once Live first is off.
      _flag(container).state = false;
      expect(_ids(container), [for (var i = 0; i < 25; i++) 'e$i']);
    });

    test('waits for the first page before fetching live events', () async {
      final gate = Completer<void>();
      final feed = _Feed([
        for (var i = 0; i < 25; i++) _gb('e$i', 2800 - i * 10),
      ], gate: gate.future);
      final container = _container(feed, liveIds: const ['e23']);
      _flag(container).state = true;
      final sub = container.listen(forYouEventsProvider, (_, __) {});
      addTearDown(sub.close);
      final live = container.listen(liveGroupBroadcastIdsProvider, (_, __) {});
      addTearDown(live.close);
      await _settle(
        () => container.read(liveGroupBroadcastIdsProvider).hasValue,
      );

      // Pressed during the first load, the live set answers.
      final notifier = container.read(forYouEventsProvider.notifier);
      expect(await notifier.hasLiveEvent(), isTrue);
      expect(feed.fetchedByIds, isEmpty);
      expect(_ids(container), isEmpty);

      gate.complete();
      await _settle(() => _ids(container).length == 21);
      expect(_ids(container).first, 'e23');
      expect(feed.fetchedByIds, [
        ['e23'],
      ]);
    });

    test('keeps out a live event its filters would not list', () async {
      final feed = _Feed([
        for (var i = 0; i < 25; i++) _gb('e$i', 2800 - i * 10),
      ]);
      final container = _container(
        feed,
        liveIds: const ['e23'],
        filters: defaultFilterPopupState.copyWith(formatsAndStates: {'Blitz'}),
      );
      await _loaded(container);

      final notifier = container.read(forYouEventsProvider.notifier);
      expect(await notifier.hasLiveEvent(), isFalse);
      // Asked once, not again on every press.
      expect(await notifier.hasLiveEvent(), isFalse);
      expect(feed.fetchedByIds, hasLength(1));
    });

    test('follows the live set while it is on', () async {
      final live = StreamController<List<String>>();
      addTearDown(live.close);
      final feed = _Feed([_gb('a', 2900), _gb('b', 2800), _gb('c', 2700)]);
      final container = _container(feed, liveStream: live.stream);
      live.add(const ['c']);
      await _loaded(container);
      _flag(container).state = true;
      await _settle(() => _ids(container).first == 'c');
      expect(_ids(container), ['c', 'a', 'b']);

      live.add(const ['b']);
      await _settle(() => _ids(container).first == 'b');
      expect(_ids(container), ['b', 'a', 'c']);
    });
  });

  group('Today count', () {
    int? count(ProviderContainer container) {
      final sub = container.listen(todayLiveEventCountProvider, (_, __) {});
      addTearDown(sub.close);
      return sub.read();
    }

    test('counts the loaded events in play, not every event in play', () async {
      // 'gone' is in play somewhere, but no event of this feed answers to it.
      final feed = _Feed([_gb('a', 2900), _gb('b', 2800), _gb('c', 2700)]);
      final container = _container(feed, liveIds: const ['c', 'gone']);
      await _loaded(container);
      await _settle(() => count(container) != null);

      expect(count(container), 1);
      expect(feed.fetchedByIds, [
        ['gone'],
      ]);
    });

    test(
      'counts a live event below the loaded pages before any press',
      () async {
        final feed = _Feed([
          for (var i = 0; i < 25; i++) _gb('e$i', 2800 - i * 10),
        ]);
        final container = _container(feed, liveIds: const ['e3', 'e23']);
        await _loaded(container);
        await _settle(() => count(container) == 2);

        // Counted, not shown: off, Today is still its first page.
        expect(_ids(container), hasLength(20));
        expect(_ids(container), isNot(contains('e23')));
        // On, exactly the counted events lead.
        _flag(container).state = true;
        expect(_ids(container).take(2).toSet(), {'e3', 'e23'});
      },
    );

    test('leaves out a live event its filters would not list', () async {
      final feed = _Feed([
        for (var i = 0; i < 25; i++) _gb('e$i', 2800 - i * 10),
      ]);
      final container = _container(
        feed,
        liveIds: const ['e23'],
        filters: defaultFilterPopupState.copyWith(formatsAndStates: {'Blitz'}),
      );
      await _loaded(container);
      await _settle(() => count(container) != null);

      expect(count(container), 0);
    });

    test(
      'leaves out a live event whose section has no boards to show',
      () async {
        final feed = _Feed([_gb('a', 2900), _gb('b', 2800), _gb('c', 2700)]);
        final container = _container(
          feed,
          liveIds: const ['a', 'c'],
          boardless: const {'c'},
        );
        await _loaded(container);
        await _settle(() => count(container) != null);

        expect(count(container), 1);
      },
    );

    test(
      'is 0 with nothing in play, and unknown before the first page',
      () async {
        final gate = Completer<void>();
        final feed = _Feed([_gb('a', 2900)], gate: gate.future);
        final live = StreamController<List<String>>();
        addTearDown(live.close);
        final container = _container(feed, liveStream: live.stream);
        final sub = container.listen(forYouEventsProvider, (_, __) {});
        addTearDown(sub.close);
        final ids = container.listen(liveGroupBroadcastIdsProvider, (_, __) {});
        addTearDown(ids.close);

        live.add(const []);
        await _settle(
          () => container.read(liveGroupBroadcastIdsProvider).hasValue,
        );
        expect(count(container), 0);

        // In play, but the feed has no page yet: it cannot say how many.
        live.add(const ['a']);
        await _settle(
          () => container.read(liveGroupBroadcastIdsProvider).value!.isNotEmpty,
        );
        await Future<void>.delayed(Duration.zero);
        expect(count(container), isNull);
        expect(
          LiveFirstCapsule.labelFor(on: false, liveCount: count(container)),
          LiveFirstCapsule.unknownLabel,
        );

        gate.complete();
        await _settle(() => count(container) == 1);
      },
    );
  });

  group('liveEventPassesForYouFilters', () {
    final event = _gb('x', 2500, timeControl: 'rapid');

    test('lists what the feed query lists', () {
      expect(
        liveEventPassesForYouFilters(event, defaultFilterPopupState),
        isTrue,
      );
      expect(
        liveEventPassesForYouFilters(
          event,
          defaultFilterPopupState.copyWith(formatsAndStates: {'Rapid', 'Live'}),
        ),
        isTrue,
      );
    });

    test('drops another time control, completed only, or Elo outside', () {
      expect(
        liveEventPassesForYouFilters(
          event,
          defaultFilterPopupState.copyWith(formatsAndStates: {'Blitz'}),
        ),
        isFalse,
      );
      expect(
        liveEventPassesForYouFilters(
          event,
          defaultFilterPopupState.copyWith(formatsAndStates: {'Completed'}),
        ),
        isFalse,
      );
      expect(
        liveEventPassesForYouFilters(
          event,
          defaultFilterPopupState.copyWith(
            eloRange: const RangeValues(2600, 2800),
          ),
        ),
        isFalse,
      );
    });
  });

  group('Today button', () {
    final toggle = find.byKey(const ValueKey(kForYouLiveFirstButtonKey));
    final filter = find.byKey(const ValueKey(kForYouFilterButtonKey));
    Finder words(String state) => find.descendant(
      of: toggle,
      matching: find.byKey(ValueKey('live_first_capsule_$state')),
    );
    Rect glassOf(WidgetTester tester, Finder button) => tester.getRect(
      find.descendant(of: button, matching: find.byType(GlassSurface)).first,
    );

    testWidgets('with nothing live there is no button to press', (
      tester,
    ) async {
      final container = await _pumpHome(tester, liveIds: const []);

      expect(toggle, findsNothing);
      expect(find.byType(LiveFirstCapsule), findsNothing);
      expect(filter, findsOneWidget);
      expect(container.read(homeEventsLiveFirstProvider), isFalse);
      expect(_rows(tester), ['a', 'b', 'c']);
      await _unmount(tester);
    });

    testWidgets('says in words how many events are live, in the thumb\'s '
        'reach', (tester) async {
      await _pumpHome(tester, liveIds: const ['a', 'c']);

      expect(tester.widget(toggle), isA<LiveFirstCapsule>());
      expect(
        find.descendant(of: toggle, matching: find.text('See 2 live')),
        findsOneWidget,
      );
      expect(words('on'), findsNothing);
      expect(
        find.bySemanticsLabel('Show the 2 live events first'),
        findsOneWidget,
      );
      // In the lower half, where the thumb rests, not in a top bar.
      expect(tester.getCenter(toggle).dy, greaterThan(852 / 2));
      await _unmount(tester);
    });

    testWidgets('one live event reads "See 1 live"', (tester) async {
      await _pumpHome(tester, liveIds: const ['c']);

      expect(
        find.descendant(of: toggle, matching: find.text('See 1 live')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Show the live event first'),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('comes in above the filter, which stays put on the gutter', (
      tester,
    ) async {
      final live = StreamController<List<String>>();
      addTearDown(live.close);
      live.add(const []);
      await _pumpHome(tester, liveStream: live.stream);
      expect(toggle, findsNothing);
      final rest = tester.getRect(filter);

      live.add(const ['c']);
      await tester.pump();
      await tester.pump();

      expect(toggle, findsOneWidget);
      expect(tester.getRect(filter), rest);
      // Stacked as every page's buttons are (the event screen's): the small
      // capsule a step above the regular filter, rims on one trailing edge.
      expect(
        rest.top - tester.getRect(toggle).bottom,
        moreOrLessEquals(InkFabStack.step, epsilon: 0.01),
      );
      final capsule = glassOf(tester, toggle);
      final disc = glassOf(tester, filter);
      expect(capsule.right, moreOrLessEquals(disc.right, epsilon: 0.01));
      expect(
        capsule.height,
        moreOrLessEquals(InkFabSize.small.disc, epsilon: 0.01),
      );
      expect(
        disc.height,
        moreOrLessEquals(InkFabSize.regular.disc, epsilon: 0.01),
      );
      // On the floating buttons' gutter.
      expect(rest.right, 393 - 16);

      // Turned on, it springs to its new words leftward; the filter holds.
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.getRect(filter), rest);
      expect(tester.getRect(toggle).right, rest.right);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.getRect(filter), rest);
      expect(
        glassOf(tester, toggle).right,
        moreOrLessEquals(disc.right, epsilon: 0.01),
      );
      await _unmount(tester);
    });

    testWidgets('with an event live it lists it first on Today and goes to '
        'its top', (tester) async {
      final container = await _pumpHome(tester, liveIds: const ['c']);
      expect(_rows(tester), ['a', 'b', 'c']);
      final reTaps = container.read(bottomNavBarReTapRequestProvider).sequence;

      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(container.read(homeEventsLiveFirstProvider), isTrue);
      expect(find.text(kNoLiveEventsRightNowMessage), findsNothing);
      expect(_rows(tester), ['c', 'a', 'b']);
      final top = container.read(bottomNavBarReTapRequestProvider);
      expect(top.item, BottomNavBarItem.forYou);
      expect(top.sequence, reTaps + 1);
      // On, it says what it does now.
      expect(words('on'), findsOneWidget);
      expect(
        find.descendant(of: toggle, matching: find.text('Live first')),
        findsOneWidget,
      );
      expect(words('off'), findsNothing);
      expect(find.bySemanticsLabel('Live events shown first'), findsOneWidget);

      // Off again with one more tap, in the order it had, the count back.
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(container.read(homeEventsLiveFirstProvider), isFalse);
      expect(_rows(tester), ['a', 'b', 'c']);
      expect(
        find.descendant(of: toggle, matching: find.text('See 1 live')),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('shows the flag the Events bar sets', (tester) async {
      final container = await _pumpHome(tester, liveIds: const ['c']);

      container.read(homeEventsLiveFirstProvider.notifier).state = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.bySemanticsLabel('Live events shown first'), findsOneWidget);
      expect(words('on'), findsOneWidget);
      expect(_rows(tester), ['c', 'a', 'b']);
      await _unmount(tester);
    });

    testWidgets('stays while on with nothing live, so it can be turned off', (
      tester,
    ) async {
      final container = await _pumpHome(tester, liveIds: const []);
      container.read(homeEventsLiveFirstProvider.notifier).state = true;
      await tester.pump();

      expect(words('on'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();

      expect(container.read(homeEventsLiveFirstProvider), isFalse);
      expect(toggle, findsNothing);
      expect(find.text(kNoLiveEventsRightNowMessage), findsNothing);
      await _unmount(tester);
    });

    testWidgets('the filter always floats over Today, counting what it '
        'narrows', (tester) async {
      // Home has no search field any more: the filter for this feed is a
      // floating button of its own.
      final container = await _pumpHome(tester, liveIds: const []);
      expect(filter, findsOneWidget);
      expect(find.bySemanticsLabel('Filters'), findsOneWidget);

      container
          .read(eventAppliedFilterProvider.notifier)
          .state = defaultFilterPopupState.copyWith(
        eloRange: const RangeValues(2600, kFilterMaxElo),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Filters, 1 applied'), findsOneWidget);
      await _unmount(tester);
    });

    for (final textScale in const [1.0, 2.0]) {
      testWidgets('fits a 320pt phone at ${textScale}x text', (tester) async {
        await _pumpHome(
          tester,
          liveIds: const ['a', 'b', 'c'],
          size: const Size(320, 640),
          textScale: textScale,
        );

        expect(tester.takeException(), isNull);
        final rect = tester.getRect(toggle);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(
          find.descendant(of: toggle, matching: find.text('See 3 live')),
          findsOneWidget,
        );
        await _unmount(tester);
      });
    }
  });
}

Games _board(String eventId) => Games(
  id: 'g_$eventId',
  roundId: 'r_$eventId',
  roundSlug: 'r_$eventId',
  tourId: 't_$eventId',
  tourSlug: 't_$eventId',
  players: [
    Player(
      name: 'White $eventId',
      title: 'GM',
      rating: 2700,
      fideId: 1,
      fed: 'USA',
      clock: 600,
      team: '',
    ),
    Player(
      name: 'Black $eventId',
      title: 'GM',
      rating: 2690,
      fideId: 2,
      fed: 'USA',
      clock: 600,
      team: '',
    ),
  ],
  lastMove: 'e2e4',
  status: 'ongoing',
  boardNr: 1,
  avgElo: 2695,
);

GroupBroadcast _gb(String id, int elo, {String timeControl = 'standard'}) {
  final now = DateTime.now();
  return GroupBroadcast(
    id: id,
    createdAt: DateTime.utc(2026),
    name: 'Event $id',
    search: const [],
    maxAvgElo: elo,
    dateStart: now.subtract(const Duration(days: 1)),
    dateEnd: now.add(const Duration(days: 3)),
    timeControl: timeControl,
  );
}

StateController<bool> _flag(ProviderContainer container) =>
    container.read(homeEventsLiveFirstProvider.notifier);

List<String> _ids(ProviderContainer container) =>
    container.read(forYouEventsProvider).events.map((e) => e.id).toList();

ProviderContainer _container(
  _Feed feed, {
  List<String> liveIds = const [],
  Stream<List<String>>? liveStream,
  FilterPopupState? filters,
  Set<String> boardless = const {},
}) {
  final container = ProviderContainer(
    overrides: _overrides(feed, liveIds, liveStream, boardless),
  );
  addTearDown(container.dispose);
  if (filters != null) {
    container.read(eventAppliedFilterProvider.notifier).state = filters;
  }
  return container;
}

List<Override> _overrides(
  _Feed feed,
  List<String> liveIds, [
  Stream<List<String>>? liveStream,
  Set<String> boardless = const {},
]) => [
  groupBroadcastRepositoryProvider.overrideWithValue(feed),
  gameRepositoryProvider.overrideWithValue(_Boards(boardless)),
  forYouFeedLocalStorageProvider.overrideWithValue(
    ForYouFeedLocalStorage(_Database()),
  ),
  favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
  favoritePlayersProviderNew.overrideWith(_NoFavoritePlayers.new),
  liveGroupBroadcastIdsProvider.overrideWith(
    (ref) => liveStream ?? Stream.value(liveIds),
  ),
  liveRoundsIdProvider.overrideWith((ref) => const Stream.empty()),
  liveTourIdProvider.overrideWith((ref) => const Stream.empty()),
];

/// Builds the feed, with the live ids it reads, and waits for its first page.
Future<void> _loaded(ProviderContainer container) async {
  final feed = container.listen(forYouEventsProvider, (_, __) {});
  addTearDown(feed.close);
  final live = container.listen(liveGroupBroadcastIdsProvider, (_, __) {});
  addTearDown(live.close);
  await _settle(
    () =>
        !container.read(forYouEventsProvider).isLoading &&
        container.read(forYouEventsProvider).events.isNotEmpty &&
        container.read(liveGroupBroadcastIdsProvider).hasValue,
  );
}

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(done(), isTrue, reason: 'For You never settled');
}

/// The For You screen, offline: its real header over stand-in pages, Today
/// drawing the feed's event ids in order.
Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  List<String> liveIds = const [],
  Stream<List<String>>? liveStream,
  ForYouTab tab = ForYouTab.today,
  Size size = const Size(393, 852),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final container = ProviderContainer(
    overrides: [
      ..._overrides(
        _Feed([_gb('a', 2900), _gb('b', 2800), _gb('c', 2700)]),
        liveIds,
        liveStream,
      ),
      recentSearchStorageProvider.overrideWithValue(_MemoryRecentSearches()),
      currentUserProvider.overrideWithValue(
        AppUser(id: 'u1', displayName: 'Test User', createdAt: DateTime(2026)),
      ),
      subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
      selectedBottomNavBarItemProvider.overrideWith(
        (ref) => BottomNavBarItem.forYou,
      ),
      selectedForYouTabProvider.overrideWith((ref) => ForYouTabController(tab)),
    ],
  );
  addTearDown(container.dispose);
  final feed = container.listen(forYouEventsProvider, (_, __) {});
  addTearDown(feed.close);
  final live = container.listen(liveGroupBroadcastIdsProvider, (_, __) {});
  addTearDown(live.close);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const Scaffold(
              resizeToAvoidBottomInset: false,
              floatingActionButton: ForYouTodayFabs(),
              body: ForYouScreen(pageBuilder: _page),
            );
          },
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(container.read(forYouEventsProvider).events, hasLength(3));
  return container;
}

Widget _page(BuildContext context, ForYouTab tab, ScrollController c) =>
    Consumer(
      builder: (context, ref, _) => ListView(
        controller: c,
        children: [
          Text('page:${tab.name}'),
          if (tab == ForYouTab.today)
            for (final event in ref.watch(forYouEventsProvider).events)
              Text('row:${event.id}'),
        ],
      ),
    );

/// Today's rows, top to bottom.
List<String> _rows(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.textContaining('row:')))
    text.data!.substring('row:'.length),
];

/// Unmounts inside the fake clock so no snack or spring timer outlives it.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 61));
}

/// The For You feed by rating, paged as the RPC pages it, and every event
/// fetchable by id.
class _Feed implements GroupBroadcastRepository {
  _Feed(this.ranked, {this.gate});

  final List<GroupBroadcast> ranked;

  /// Holds every page until it completes.
  final Future<void>? gate;
  final List<List<String>> fetchedByIds = [];

  @override
  Future<List<GroupBroadcast>> getForYouGroupBroadcasts({
    int limit = 20,
    int offset = 0,
    List<String>? timeControlFilters,
    int? minElo,
    int? maxElo,
    Set<String>? statusFilters,
  }) async {
    await gate;
    return ranked.skip(offset).take(limit).toList();
  }

  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByIdsOrNames(
    List<String> identifiers,
  ) async {
    fetchedByIds.add(List.of(identifiers));
    return [
      for (final event in ranked)
        if (identifiers.contains(event.id)) event,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected feed call: ${invocation.memberName}');
}

/// One board for every event, but the [boardless] ones, whose sections
/// hide themselves.
class _Boards implements GameRepository {
  _Boards([this.boardless = const {}]);

  final Set<String> boardless;

  @override
  Future<Map<String, List<Games>>> getForYouTopGamesByEventIds({
    required List<String> eventIds,
    int boardsPerEvent = 4,
  }) async => {
    for (final id in eventIds)
      id: boardless.contains(id) ? const <Games>[] : [_board(id)],
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

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}

class _NoFavoritePlayers extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

class _MemoryRecentSearches implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

class _FreeSubscription extends SubscriptionNotifier {
  _FreeSubscription() : super() {
    state = SubscriptionState(isSubscribed: false, isLoading: false);
  }

  @override
  set state(SubscriptionState value) =>
      super.state = value.copyWith(isSubscribed: false, isLoading: false);
}
