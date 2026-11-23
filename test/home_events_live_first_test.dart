import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Trello #1420, home: Live first floats over the Events lists on every
/// segment, in words that count the live events, lists Current's live events
/// first, and says why when there is nothing to lift. The field's filter
/// glyph lost its tile.
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

  // The pushed copy (the `/group_event_screen` route, and Events opened
  // with no home shell under it) keeps its back; only the dock's section
  // is a root without one.
  testWidgets('the pushed Events page keeps its back and holds no start '
      'screen on its segments', (tester) async {
    await _pumpEvents(tester, liveIds: const []);
    expect(find.byKey(const ValueKey('events_back')), findsOneWidget);
    final segments = tester.widget<SegmentedSwitcher>(
      find.byType(SegmentedSwitcher),
    );
    expect(segments.longPressFor, isNull);
    await _unmount(tester);
  });

  group('liveEventsFirst', () {
    test('lifts live events, keeping the order on both sides', () {
      final ordered = liveEventsFirst([
        _card('a'),
        _card('b', live: true),
        _card('c'),
        _card('d'),
        _card('e', live: true),
      ], const <String>{});

      expect(ordered.map((e) => e.id), ['b', 'e', 'a', 'c', 'd']);
    });

    test('counts an id on the live stream as live, as the card does', () {
      // The card's category lags the stream by a refresh as a round starts.
      final ordered = liveEventsFirst(
        [_card('a'), _card('b'), _card('c')],
        const {'c'},
      );

      expect(ordered.map((e) => e.id), ['c', 'a', 'b']);
    });

    test('nothing live, or everything live, is the same list', () {
      final none = [_card('a'), _card('b')];
      expect(identical(liveEventsFirst(none, const <String>{}), none), isTrue);

      final all = [_card('a', live: true), _card('b', live: true)];
      expect(identical(liveEventsFirst(all, const <String>{}), all), isTrue);
    });

    test('anyLiveEvent asks the list on screen when there is one', () {
      // A live id filtered out of Current is not a live event to show.
      expect(
        anyLiveEvent(liveIds: const {'x'}, currentEvents: [_card('a')]),
        isFalse,
      );
      expect(
        anyLiveEvent(
          liveIds: const <String>{},
          currentEvents: [_card('a', live: true)],
        ),
        isTrue,
      );
      expect(anyLiveEvent(liveIds: const {'x'}), isTrue);
      expect(anyLiveEvent(liveIds: const <String>{}), isFalse);
    });

    test('homeLiveEventIds prefers the strict stream once it has a value', () {
      expect(homeLiveEventIds(strict: const ['s'], mirror: const ['m']), {'s'});
      expect(homeLiveEventIds(strict: const [], mirror: const ['m']), isEmpty);
      expect(homeLiveEventIds(strict: null, mirror: const ['m']), {'m'});
    });
  });

  group('Current list', () {
    final now = DateTime.now();
    // Ongoing by the clock, so only the live id makes an event live.
    GroupBroadcast ongoing(String id, int elo) => GroupBroadcast(
      id: id,
      createdAt: DateTime.utc(2026),
      name: 'Event $id',
      search: ['Event $id'],
      maxAvgElo: elo,
      dateStart: now.subtract(const Duration(days: 1)),
      dateEnd: now.add(const Duration(days: 3)),
      timeControl: 'standard',
    );

    Future<
      (
        ProviderContainer,
        ProviderSubscription<AsyncValue<List<GroupEventCardModel>>>,
      )
    >
    currentList({bool liveFirst = false}) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(_FakeAppDatabase()),
          groupBroadcastRepositoryProvider.overrideWithValue(
            _FakeGroupBroadcastRepository(
              current: [
                ongoing('gb_top', 2750),
                ongoing('gb_live', 2600),
                ongoing('gb_open', 2400),
              ],
            ),
          ),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream.value(const ['gb_live']),
          ),
          favoriteEventsProvider.overrideWith(
            () => _FakeFavoriteEventsNotifier(const []),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(favoriteEventsProvider.future);
      container.read(selectedGroupCategoryProvider.notifier).state =
          GroupEventCategory.current;
      container.read(homeEventsLiveFirstProvider.notifier).state = liveFirst;
      final sub = container.listen(groupEventScreenProvider, (_, __) {});
      addTearDown(sub.close);
      for (var i = 0; i < 40 && !sub.read().hasValue; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return (container, sub);
    }

    List<String> ids(
      ProviderSubscription<AsyncValue<List<GroupEventCardModel>>> sub,
    ) => sub.read().requireValue.map((e) => e.id).toList();

    test('keeps its ranking while Live first is off', () async {
      final (_, sub) = await currentList();
      expect(ids(sub), ['gb_top', 'gb_live', 'gb_open']);
    });

    test('loads live events first while Live first is on', () async {
      final (_, sub) = await currentList(liveFirst: true);
      expect(ids(sub), ['gb_live', 'gb_top', 'gb_open']);
    });

    test(
      're-publishes on a press and restores the ranking on release',
      () async {
        final (container, sub) = await currentList();
        final flag = container.read(homeEventsLiveFirstProvider.notifier);

        flag.state = true;
        expect(ids(sub), ['gb_live', 'gb_top', 'gb_open']);

        flag.state = false;
        expect(ids(sub), ['gb_top', 'gb_live', 'gb_open']);
      },
    );

    group('as the Events tab shows it', () {
      // The screen re-ranks the list it is handed by favourites and hearts
      // (sortBasedOnFavorite), which on its own would undo Live first.
      Future<List<String>> shown({
        required bool liveFirst,
        List<String> starred = const [],
      }) async {
        final (container, sub) = await currentList(liveFirst: liveFirst);
        return currentEventsDisplayOrder(
          events: sub.read().requireValue,
          sorter: container.read(tournamentSortingServiceProvider),
          favorites: starred,
          liveFirst: liveFirst,
          liveIds: const {'gb_live'},
        ).map((e) => e.id).toList();
      }

      test('keeps its ranking while Live first is off', () async {
        expect(await shown(liveFirst: false), ['gb_top', 'gb_live', 'gb_open']);
      });

      test('lists the live event first while Live first is on', () async {
        expect(await shown(liveFirst: true), ['gb_live', 'gb_top', 'gb_open']);
      });

      test('puts live events above starred ones', () async {
        expect(await shown(liveFirst: true, starred: const ['gb_open']), [
          'gb_live',
          'gb_open',
          'gb_top',
        ]);
        // Off, the star leads as before.
        expect(await shown(liveFirst: false, starred: const ['gb_open']), [
          'gb_open',
          'gb_top',
          'gb_live',
        ]);
      });
    });
  });

  group('Events button', () {
    final toggle = find.byKey(const ValueKey(kHomeLiveFirstButtonKey));
    Finder words(String state) => find.descendant(
      of: toggle,
      matching: find.byKey(ValueKey('live_first_capsule_$state')),
    );

    testWidgets('with nothing live there is no button to press', (
      tester,
    ) async {
      final container = await _pumpEvents(tester, liveIds: const []);

      expect(find.byType(LiveFirstCapsule), findsNothing);
      expect(find.bySemanticsLabel(RegExp('live events? first')), findsNothing);
      expect(container.read(homeEventsLiveFirstProvider), isFalse);
      // Nothing left inside the search field but the search.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('simple-search-field-surface')),
          matching: find.byType(LiveFirstCapsule),
        ),
        findsNothing,
      );
      await _unmount(tester);
    });

    testWidgets('says in words how many events are live, in the thumb\'s '
        'reach', (tester) async {
      await _pumpEvents(tester, liveIds: const ['gb_live', 'gb_b', 'gb_c']);

      expect(
        find.descendant(of: toggle, matching: find.byType(LiveFirstCapsule)),
        findsOneWidget,
      );
      expect(find.text('See 3 live'), findsNothing);
      expect(words('on'), findsNothing);
      expect(
        find.bySemanticsLabel('Show the 3 live events first'),
        findsOneWidget,
      );
      final rect = tester.getRect(toggle);
      expect(rect.center.dy, greaterThan(852 / 2));
      // Its only floating action uses the regular disc and the page gutter.
      expect(rect.height, InkFabSize.regular.side);
      expect(rect.right, 393 - 16);
      expect(rect.bottom, 852 - kFloatingActionButtonMargin);
      await _unmount(tester);
    });

    testWidgets('counts only the live events Current lists under its filters', (
      tester,
    ) async {
      // Three events in play: one is not on Current at all, one is blitz.
      await _pumpEvents(
        tester,
        liveIds: const ['gb_live', 'gb_blitz', 'gb_elsewhere'],
        liveCurrent: [_broadcast('gb_live'), _broadcast('gb_blitz', 'blitz')],
        filters: defaultFilterPopupState.copyWith(
          formatsAndStates: {'Standard'},
        ),
      );

      expect(
        find.bySemanticsLabel('Show the live event first'),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('announces Live first without a count until known', (
      tester,
    ) async {
      await _pumpEvents(
        tester,
        liveIds: const ['gb_live'],
        liveCurrentError: true,
      );

      expect(find.bySemanticsLabel('Show live events first'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('with an event live it comes on from Past and opens Current', (
      tester,
    ) async {
      final container = await _pumpEvents(
        tester,
        liveIds: const ['gb_live'],
        category: GroupEventCategory.past,
      );
      expect(find.text('events:past'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Show the live event first'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsLabel('Show the live event first'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(container.read(homeEventsLiveFirstProvider), isTrue);
      expect(
        container.read(selectedGroupCategoryProvider),
        GroupEventCategory.current,
      );
      expect(find.text('events:current'), findsOneWidget);
      expect(find.text(kNoLiveEventsRightNowMessage), findsNothing);
      // On, it says what it does now.
      expect(words('on'), findsOneWidget);
      expect(words('off'), findsNothing);
      expect(
        find.descendant(of: toggle, matching: find.text('Live first')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Live events shown first'), findsOneWidget);

      // Off again with one more tap, and Current stays open.
      await tester.tap(find.bySemanticsLabel('Live events shown first'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(container.read(homeEventsLiveFirstProvider), isFalse);
      expect(
        container.read(selectedGroupCategoryProvider),
        GroupEventCategory.current,
      );
      expect(
        find.bySemanticsLabel('Show the live event first'),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('stays while on with nothing live, so it can be turned off', (
      tester,
    ) async {
      final container = await _pumpEvents(tester, liveIds: const []);
      container.read(homeEventsLiveFirstProvider.notifier).state = true;
      await tester.pump();

      expect(words('on'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();

      expect(container.read(homeEventsLiveFirstProvider), isFalse);
      expect(find.byType(LiveFirstCapsule), findsNothing);
      expect(find.text(kNoLiveEventsRightNowMessage), findsNothing);
      await _unmount(tester);
    });

    for (final narrowed in const [false, true]) {
      testWidgets('a live event Current does not list is not offered '
          '(${narrowed ? 'its filters keep it out' : 'not on Current'})', (
        tester,
      ) async {
        final container = await _pumpEvents(
          tester,
          liveIds: const ['gb_live'],
          // Current holds it only when the filters are what keep it out.
          liveCurrent: narrowed ? [_broadcast('gb_live')] : const [],
          filters: narrowed
              ? defaultFilterPopupState.copyWith(formatsAndStates: {'Blitz'})
              : null,
        );

        // Nothing to lift: no "See 1 live" that a press would answer with
        // "No live events".
        expect(find.byType(LiveFirstCapsule), findsNothing);
        expect(container.read(eventsLiveEventCountProvider), 0);
        await _unmount(tester);
      });

      testWidgets('a press while the count is unknown that finds nothing says '
          '${narrowed ? 'the filters keep it out' : 'nothing is live'}, '
          'above the button', (tester) async {
        final container = await _pumpEvents(
          tester,
          liveIds: const ['gb_live'],
          liveCurrentError: true,
          filters: narrowed
              ? defaultFilterPopupState.copyWith(formatsAndStates: {'Blitz'})
              : null,
        );
        // Current on screen, loaded, and without the live event.
        final list = container.listen(groupEventScreenProvider, (_, __) {});
        addTearDown(list.close);
        for (var i = 0; i < 40 && !list.read().hasValue; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(list.read().requireValue, isEmpty);

        await tester.tap(toggle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(container.read(homeEventsLiveFirstProvider), isFalse);
        final message = narrowed
            ? kNoLiveEventsMatchFiltersMessage
            : kNoLiveEventsRightNowMessage;
        expect(find.text(message), findsOneWidget);
        // The page's own Scaffold knows its button: the snack lands above
        // it, never over the button just pressed.
        expect(
          tester.getRect(find.byType(SnackBar)).bottom,
          lessThanOrEqualTo(tester.getRect(toggle).top + 0.01),
        );
        await _unmount(tester);
      });
    }

    for (final textScale in const [1.0, 2.0]) {
      testWidgets('fits a 320pt phone at ${textScale}x text', (tester) async {
        await _pumpEvents(
          tester,
          liveIds: const ['gb_live'],
          size: const Size(320, 640),
          textScale: textScale,
        );

        expect(tester.takeException(), isNull);
        final rect = tester.getRect(toggle);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(
          find.bySemanticsLabel('Show the live event first'),
          findsOneWidget,
        );
        await _unmount(tester);
      });
    }
  });

  group('home Live first helpers', () {
    test('the Events count is Current\'s events in play under its filters, '
        'refetched as the live set changes', () async {
      final live = StreamController<List<String>>();
      addTearDown(live.close);
      final repository = _FakeGroupBroadcastRepository(
        liveCurrent: [
          _broadcast('a'),
          _broadcast('b', 'blitz'),
          _broadcast('c'),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          liveGroupBroadcastIdsProvider.overrideWith((ref) => live.stream),
          groupBroadcastRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final count = container.listen(eventsLiveEventCountProvider, (_, __) {});
      addTearDown(count.close);
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      // Nothing in play is a known 0, not an unknown.
      live.add(const []);
      await settle();
      expect(count.read(), 0);

      // In play, then answered: 'x' is not on Current.
      live.add(const ['a', 'b', 'x']);
      await settle();
      expect(count.read(), 2);
      expect(repository.currentByIds.last, ['a', 'b', 'x']);

      // The filters narrow it, as Current shows it.
      container.read(eventAppliedFilterProvider.notifier).state =
          defaultFilterPopupState.copyWith(formatsAndStates: {'Standard'});
      await settle();
      expect(count.read(), 1);

      // A new live event is asked for and counted.
      live.add(const ['a', 'b', 'c']);
      await settle();
      expect(count.read(), 2);
    });

    test(
      'the Events count keeps its last answer through a failed refetch',
      () async {
        final live = StreamController<List<String>>();
        addTearDown(live.close);
        final repository = _FakeGroupBroadcastRepository(
          liveCurrent: [_broadcast('a')],
        );
        final container = ProviderContainer(
          overrides: [
            liveGroupBroadcastIdsProvider.overrideWith((ref) => live.stream),
            groupBroadcastRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        final count = container.listen(
          eventsLiveEventCountProvider,
          (_, __) {},
        );
        addTearDown(count.close);
        Future<void> settle() async {
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        live.add(const ['a']);
        await settle();
        expect(count.read(), 1);

        repository.failByIds = true;
        live.add(const ['a', 'b']);
        await settle();
        expect(count.read(), 1);
      },
    );

    test('the button is there while something is live, while the count is '
        'unknown, or while on', () {
      expect(showsHomeLiveFirst(liveCount: 0, on: false), isFalse);
      expect(showsHomeLiveFirst(liveCount: 2, on: false), isTrue);
      expect(showsHomeLiveFirst(liveCount: null, on: false), isTrue);
      expect(showsHomeLiveFirst(liveCount: 0, on: true), isTrue);
    });

    test('a press that finds nothing says why', () {
      final blitz = defaultFilterPopupState.copyWith(
        formatsAndStates: {'Blitz'},
      );
      // Nothing in play: nothing is live, filters or not.
      expect(
        noLiveEventsMessage(liveIds: const {}, filters: blitz),
        kNoLiveEventsRightNowMessage,
      );
      // In play but kept out by the filters: say so, not "nothing live".
      expect(
        noLiveEventsMessage(liveIds: const {'x'}, filters: blitz),
        kNoLiveEventsMatchFiltersMessage,
      );
      expect(
        noLiveEventsMessage(
          liveIds: const {'x'},
          filters: defaultFilterPopupState.copyWith(
            eloRange: const RangeValues(2600, kFilterMaxElo),
          ),
        ),
        kNoLiveEventsMatchFiltersMessage,
      );
      expect(
        noLiveEventsMessage(
          liveIds: const {'x'},
          filters: defaultFilterPopupState,
        ),
        kNoLiveEventsRightNowMessage,
      );
    });
  });

  group('Search field filter glyph', () {
    const filterKey = ValueKey('filter');

    Future<int Function()> pumpBar(WidgetTester tester, {int badge = 0}) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Center(
                  child: SimpleSearchBar(
                    controller: TextEditingController(),
                    focusNode: FocusNode(),
                    onCloseTap: () {},
                    onOpenFilter: () => opened++,
                    filterBadgeCount: badge,
                    filterButtonKey: filterKey,
                  ),
                ),
              );
            },
          ),
        ),
      );
      return () => opened;
    }

    testWidgets('is a bare glyph: no tile behind it', (tester) async {
      await pumpBar(tester);

      final filled = find.descendant(
        of: find.byKey(filterKey),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color != null,
        ),
      );
      expect(filled, findsNothing);
      expect(find.bySemanticsLabel('Filters'), findsOneWidget);
    });

    testWidgets('its whole box still takes the tap', (tester) async {
      final opened = await pumpBar(tester);

      // Just inside the box's corner, off the glyph itself.
      final box = tester.getRect(find.byKey(filterKey));
      await tester.tapAt(box.topLeft + const Offset(1, 1));
      expect(opened(), 1);
    });

    testWidgets('keeps its count badge, and reads it out', (tester) async {
      await pumpBar(tester, badge: 2);

      expect(
        find.descendant(of: find.byKey(filterKey), matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Filters, 2 active'), findsOneWidget);
    });
  });
}

GroupEventCardModel _card(String id, {bool live = false}) =>
    GroupEventCardModel(
      id: id,
      title: 'Event $id',
      dates: '',
      maxAvgElo: 0,
      timeUntilStart: '',
      tourEventCategory: live
          ? TourEventCategory.live
          : TourEventCategory.ongoing,
      timeControl: 'Standard',
      endDate: null,
      startDate: null,
    );

/// The Events tab, offline: its real top bar over stand-in list pages, with
/// the strict live-ids stream held at [liveIds] and kept alive the way the
/// lists and cards keep it alive in the app.
Future<ProviderContainer> _pumpEvents(
  WidgetTester tester, {
  required List<String> liveIds,
  GroupEventCategory category = GroupEventCategory.current,
  FilterPopupState? filters,
  Size size = const Size(393, 852),
  double textScale = 1,
  List<GroupBroadcast>? liveCurrent,
  bool liveCurrentError = false,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final container = ProviderContainer(
    overrides: [
      recentSearchStorageProvider.overrideWithValue(_MemoryRecentSearches()),
      currentUserProvider.overrideWithValue(
        AppUser(id: 'u1', displayName: 'Test User', createdAt: DateTime(2026)),
      ),
      subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
      liveGroupBroadcastIdsProvider.overrideWith(
        (ref) => Stream.value(liveIds),
      ),
      // Switching segments reloads the list underneath the stand-in pages.
      appDatabaseProvider.overrideWithValue(_FakeAppDatabase()),
      groupBroadcastRepositoryProvider.overrideWithValue(
        _FakeGroupBroadcastRepository(
          // By default every event in play is on Current.
          liveCurrent:
              liveCurrent ?? [for (final id in liveIds) _broadcast(id)],
        )..failByIds = liveCurrentError,
      ),
      favoriteEventsProvider.overrideWith(
        () => _FakeFavoriteEventsNotifier(const []),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(selectedGroupCategoryProvider.notifier).state = category;
  if (filters != null) {
    container.read(eventAppliedFilterProvider.notifier).state = filters;
  }
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
            // The page is its own Scaffold, held bare by its route.
            return const GroupEventScreen(pageBuilder: _page);
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  // The count lands a moment after the page ("See live" until then) and
  // the capsule springs to its words.
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 600));
  return container;
}

/// An event on Current, ongoing by the clock.
GroupBroadcast _broadcast(String id, [String timeControl = 'standard']) {
  final now = DateTime.now();
  return GroupBroadcast(
    id: id,
    createdAt: DateTime.utc(2026),
    name: 'Event $id',
    search: ['Event $id'],
    maxAvgElo: 2600,
    dateStart: now.subtract(const Duration(days: 1)),
    dateEnd: now.add(const Duration(days: 3)),
    timeControl: timeControl,
  );
}

/// Unmounts inside the fake clock so no snack or spring timer outlives it.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 61));
}

Widget _page(
  BuildContext context,
  GroupEventCategory category,
  ScrollController controller,
) => ListView(
  controller: controller,
  children: [Text('events:${category.name}')],
);

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

class _FakeGroupBroadcastRepository extends GroupBroadcastRepository {
  _FakeGroupBroadcastRepository({
    this.current = const [],
    this.liveCurrent = const [],
  });

  final List<GroupBroadcast> current;

  /// What Current answers when asked for events by id: the events in play
  /// it holds.
  final List<GroupBroadcast> liveCurrent;

  /// Asking by id fails (the count stays unknown, or at its last answer).
  bool failByIds = false;
  final List<List<String>> currentByIds = [];

  @override
  Future<List<GroupBroadcast>> getCurrentGroupBroadcastsByIds(
    List<String> ids,
  ) async {
    currentByIds.add(List.of(ids));
    if (failByIds) throw StateError('offline');
    return [
      for (final broadcast in [...current, ...liveCurrent])
        if (ids.contains(broadcast.id)) broadcast,
    ];
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
  }) async => current;
}

class _FakeFavoriteEventsNotifier extends FavoriteEventsNotifier {
  _FakeFavoriteEventsNotifier(this._favorites);

  final List<FavoriteEvent> _favorites;

  @override
  Future<List<FavoriteEvent>> build() async => _favorites;
}
