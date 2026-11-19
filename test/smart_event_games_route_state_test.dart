import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/ink_fab.dart' show SearchInkFab;
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _LoadedAggregateNotifier extends SmartAggregateEventNotifier {
  _LoadedAggregateNotifier(super.ref, super.query) {
    state = const AsyncValue.data(SmartAggregateEvent.empty);
  }
}

/// A search whose answer has not landed yet: [land] delivers it.
class _PendingAggregateNotifier extends SmartAggregateEventNotifier {
  _PendingAggregateNotifier(super.ref, super.query) {
    state = const AsyncValue.loading();
  }

  void land(SmartAggregateEvent event) => state = AsyncValue.data(event);
}

class _TestBoardSettingsNotifier extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();

  @override
  Future<void> setGamesListViewModeIndex(int index) async {
    state = AsyncData(
      state.requireValue.copyWith(gamesListViewModeIndex: index),
    );
  }
}

class _TestFavoriteEventsNotifier extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}

/// The app bar's My Space menu action watches this; the real notifier reads the
/// SQLite cache, which has no backend under widget tests.
class _TestSpaceShortcutsNotifier extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

SmartEventRequest _request({String tierLabel = 'All', int minElo = 0}) {
  return SmartEventRequest(
    source: SmartEventSource.forYou,
    tierLabel: tierLabel,
    titleSuffix: 'Games',
    minElo: minElo,
    maxElo: 3200,
    caption: 'From your filters',
    countSingular: 'event',
    countPlural: 'events',
    events: [],
  );
}

Future<ProviderContainer> _pumpSmartEvent(
  WidgetTester tester,
  SmartEventRequest request, {
  SmartAggregateEventNotifier Function(Ref ref, SmartEventGamesQuery query)?
  aggregate,
  bool showFilters = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      boardSettingsProviderNew.overrideWith(_TestBoardSettingsNotifier.new),
      favoriteEventsProvider.overrideWith(_TestFavoriteEventsNotifier.new),
      spaceShortcutsProvider.overrideWith(_TestSpaceShortcutsNotifier.new),
      smartAggregateEventRepositoryProvider.overrideWith(
        aggregate ?? (ref, query) => _LoadedAggregateNotifier(ref, query),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        navigatorObservers: [routeObserver],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return SmartEventScreen(request: request, showFilters: showFilters);
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return container;
}

/// Runs the search's morph (one spring, about a third of a second) to rest.
Future<void> _settleMorph(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

const _fab = ValueKey('smart_event_search_fab');
const _close = ValueKey('smart_event_search_close');

Finder _gamesList(SmartEventRequest request) => find.byKey(
  PageStorageKey<String>('smart_event_games_${request.scopeId}'),
  skipOffstage: false,
);

ScrollableState _gamesScrollable(
  WidgetTester tester,
  SmartEventRequest request,
) => tester.state<ScrollableState>(
  find.descendant(
    of: _gamesList(request),
    matching: find.byType(Scrollable, skipOffstage: false),
  ),
);

void main() {
  testWidgets(
    'Smart Event menu offers My Space without a bookmark save; layout cycles as usual',
    (tester) async {
      final request = _request();
      final container = ProviderContainer(
        overrides: [
          boardSettingsProviderNew.overrideWith(_TestBoardSettingsNotifier.new),
          favoriteEventsProvider.overrideWith(_TestFavoriteEventsNotifier.new),
          spaceShortcutsProvider.overrideWith(_TestSpaceShortcutsNotifier.new),
          smartAggregateEventRepositoryProvider.overrideWith(
            (ref, query) => _LoadedAggregateNotifier(ref, query),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            navigatorObservers: [routeObserver],
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return SmartEventScreen(request: request);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The layout toggle is the Games lists' own board-view button, the
      // Filters glyph's size beside it; the menu stays the header's.
      final layout = find.byType(BoardViewToggleButton);
      final menu = find.byWidgetPredicate(
        (widget) => widget is AppBarIcons && widget.image == SvgAsset.threeDots,
      );
      expect(find.byType(AppBarIcons), findsOneWidget);
      expect(layout, findsOneWidget);
      expect(menu, findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
      expect(find.text('Add to My Space'), findsNothing);

      expect(
        container.read(gamesListViewModeProvider),
        GamesListViewMode.chessBoardGrid,
      );
      for (final expected in [
        GamesListViewMode.chessBoard,
        GamesListViewMode.gamesCard,
        GamesListViewMode.chessBoardGrid,
      ]) {
        await tester.tap(layout);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(container.read(gamesListViewModeProvider), expected);
      }

      await tester.tap(menu);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Add to My Space'), findsOneWidget);
      // My Space is the one way to keep a smart event: no bookmark save.
      expect(find.text('Save ${request.displayName}'), findsNothing);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
      expect(tester.takeException(), isNull);

      // Dismissing the menu leaves the header free of standalone save actions.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Add to My Space'), findsNothing);
      expect(find.text('Save ${request.displayName}'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'Games keeps the same list and provider across routes and sibling tabs',
    (tester) async {
      final request = _request();
      final createdNotifiers = <SmartAggregateEventNotifier>[];
      final container = ProviderContainer(
        overrides: [
          boardSettingsProviderNew.overrideWith(_TestBoardSettingsNotifier.new),
          favoriteEventsProvider.overrideWith(_TestFavoriteEventsNotifier.new),
          spaceShortcutsProvider.overrideWith(_TestSpaceShortcutsNotifier.new),
          smartAggregateEventRepositoryProvider.overrideWith((ref, query) {
            final notifier = _LoadedAggregateNotifier(ref, query);
            createdNotifiers.add(notifier);
            return notifier;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            navigatorObservers: [routeObserver],
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return SmartEventScreen(request: request);
              },
            ),
          ),
        ),
      );
      await tester.pump();

      final listKey = PageStorageKey<String>(
        'smart_event_games_${request.scopeId}',
      );
      final listFinder = find.byKey(listKey, skipOffstage: false);
      expect(listFinder, findsOneWidget);
      final listStateBefore = tester.state<ScrollableState>(
        find.descendant(
          of: listFinder,
          matching: find.byType(Scrollable, skipOffstage: false),
        ),
      );
      final scrollPositionBefore = listStateBefore.position;
      final scrollOffsetBefore = scrollPositionBefore.pixels;
      expect(createdNotifiers, hasLength(1));
      final notifierBefore = createdNotifiers.single;

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push<void>(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      );
      await tester.pumpAndSettle();

      expect(listFinder, findsOneWidget);
      expect(createdNotifiers, [same(notifierBefore)]);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(listFinder, findsOneWidget);
      expect(
        tester.state<ScrollableState>(
          find.descendant(
            of: listFinder,
            matching: find.byType(Scrollable, skipOffstage: false),
          ),
        ),
        same(listStateBefore),
      );
      expect(listStateBefore.position, same(scrollPositionBefore));
      expect(listStateBefore.position.pixels, scrollOffsetBefore);
      expect(createdNotifiers, [same(notifierBefore)]);

      await tester.tap(find.text('Events'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(listFinder, findsOneWidget);
      expect(createdNotifiers, [same(notifierBefore)]);

      await tester.tap(find.text('Games'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(listFinder, findsOneWidget);
      expect(
        tester.state<ScrollableState>(
          find.descendant(
            of: listFinder,
            matching: find.byType(Scrollable, skipOffstage: false),
          ),
        ),
        same(listStateBefore),
      );
      expect(listStateBefore.position, same(scrollPositionBefore));
      expect(listStateBefore.position.pixels, scrollOffsetBefore);
      expect(createdNotifiers, [same(notifierBefore)]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  // Trello #1420: the search and the list controls left the header for a
  // floating search that opens the tab's search in place, on the app's one
  // search mode.
  testWidgets(
    'the floating search opens Games search in place; back closes it and '
    'clears the query',
    (tester) async {
      await _pumpSmartEvent(tester, _request());

      final fab = find.byKey(_fab);
      final close = find.byKey(_close);
      final menu = find.byWidgetPredicate(
        (widget) => widget is AppBarIcons && widget.image == SvgAsset.threeDots,
      );
      expect(fab.hitTestable(), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('No games right now'), findsOneWidget);

      await tester.tap(fab);
      await _settleMorph(tester);

      // The header is the search: a way back, the focused field and the
      // list's own controls. The title row, the tabs and the floating
      // search are out of reach (kept, to come back as they were).
      expect(close.hitTestable(), findsOneWidget);
      expect(menu.hitTestable(), findsNothing);
      expect(find.text('Events').hitTestable(), findsNothing);
      expect(fab.hitTestable(), findsNothing);
      expect(
        find.byKey(const ValueKey('smart_event_search_filters')).hitTestable(),
        findsOneWidget,
      );
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

      await tester.enterText(field, 'carlsen');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(
        find.text(SearchNoMatches.titleFor(query: 'carlsen')),
        findsOneWidget,
      );

      // The no-hits line's way back empties the words and keeps the search
      // open over the whole list.
      await tester.tap(find.byKey(const ValueKey('search_no_matches_clear')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(close.hitTestable(), findsOneWidget);
      expect(find.text('No games right now'), findsOneWidget);
      await tester.enterText(field, 'carlsen');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(
        find.text(SearchNoMatches.titleFor(query: 'carlsen')),
        findsOneWidget,
      );

      // Back closes the search, not the screen, and takes the query with it.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(await navigator.maybePop(), isTrue);
      await _settleMorph(tester);
      expect(find.byType(SmartEventScreen), findsOneWidget);
      expect(close, findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Events').hitTestable(), findsOneWidget);
      expect(find.text('No games right now'), findsOneWidget);
      expect(fab.hitTestable(), findsOneWidget);

      // About has nothing to search.
      await tester.tap(find.text('About'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(fab, findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'searching keeps the Games list on screen: no spinner, skeleton or '
    'remount, and closing brings the list back at once',
    (tester) async {
      final request = _request();
      final created = <String>[];
      final pending = <String, _PendingAggregateNotifier>{};
      await _pumpSmartEvent(
        tester,
        request,
        aggregate: (ref, query) {
          created.add(query.searchQuery);
          if (query.searchQuery.isEmpty) {
            return _LoadedAggregateNotifier(ref, query);
          }
          return pending[query.searchQuery] = _PendingAggregateNotifier(
            ref,
            query,
          );
        },
      );

      final list = _gamesScrollable(tester, request);
      final progress = find.byKey(const ValueKey('games_list_refetch_line'));
      void expectNoLoadingWipe() {
        expect(find.byKey(const ValueKey('smart_games_loading')), findsNothing);
        expect(find.byType(SkeletonWidget), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }

      expect(created, ['']);
      expect(find.text('No games right now'), findsOneWidget);

      await tester.tap(find.byKey(_fab));
      await _settleMorph(tester);
      // Opening changes nothing under the header: the same list, in place.
      expect(_gamesScrollable(tester, request), same(list));
      expect(find.text('No games right now'), findsOneWidget);
      expectNoLoadingWipe();

      await tester.enterText(find.byType(TextField), 'carlsen');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(created, ['', 'carlsen']);
      // The bar fades in on its spring.
      await tester.pump(const Duration(milliseconds: 300));

      // The answer is on its way: the list as it was stays on screen, with
      // only the thin bar to say so.
      expect(_gamesScrollable(tester, request), same(list));
      expect(find.text('No games right now'), findsOneWidget);
      expect(progress, findsOneWidget);
      expectNoLoadingWipe();

      pending['carlsen']!.land(SmartAggregateEvent.empty);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text(SearchNoMatches.titleFor(query: 'carlsen')),
        findsOneWidget,
      );
      expect(progress, findsNothing);
      expect(_gamesScrollable(tester, request), same(list));

      await tester.tap(find.byKey(_close));
      await tester.pump();
      // The list the search narrowed stayed loaded: it is back in the same
      // frame, not fetched again.
      expect(find.text('No games right now'), findsOneWidget);
      expect(progress, findsNothing);
      expect(created.where((query) => query.isEmpty), hasLength(1));
      await _settleMorph(tester);
      expect(_gamesScrollable(tester, request), same(list));
      expectNoLoadingWipe();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'searching Events keeps its list too: a search with no hits is the same '
    'list, and closing it brings the events back in place',
    (tester) async {
      final request = _request();
      final pending = <String, _PendingAggregateNotifier>{};
      await _pumpSmartEvent(
        tester,
        request,
        aggregate: (ref, query) {
          if (query.searchQuery.isEmpty) {
            return _LoadedAggregateNotifier(ref, query);
          }
          return pending[query.searchQuery] = _PendingAggregateNotifier(
            ref,
            query,
          );
        },
      );
      await tester.tap(find.text('Events'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final eventsList = find.byKey(
        PageStorageKey<String>('smart_event_events_${request.scopeId}'),
        skipOffstage: false,
      );
      ScrollableState scrollable() => tester.state<ScrollableState>(
        find.descendant(
          of: eventsList,
          matching: find.byType(Scrollable, skipOffstage: false),
        ),
      );
      final progress = find.byKey(const ValueKey('games_list_refetch_line'));
      // Nothing to show is still the list, not a page in its place.
      expect(find.text('No events right now'), findsOneWidget);
      final list = scrollable();

      final fab = find.byKey(_fab);
      expect(tester.widget<SearchInkFab>(fab).label, 'Search events');
      await tester.tap(fab);
      await _settleMorph(tester);
      expect(scrollable(), same(list));

      await tester.enterText(find.byType(TextField), 'tata');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(progress, findsOneWidget);
      expect(scrollable(), same(list));
      expect(find.byType(SkeletonWidget), findsNothing);

      pending['tata']!.land(SmartAggregateEvent.empty);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text(SearchNoMatches.titleFor(query: 'tata', subject: 'events')),
        findsOneWidget,
      );
      expect(progress, findsNothing);
      expect(scrollable(), same(list));

      await tester.tap(find.byKey(_close));
      await _settleMorph(tester);
      expect(find.text('No events right now'), findsOneWidget);
      expect(scrollable(), same(list));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'Filters is in the header without the search, clean on entry, then '
    'wearing the one count the search shows',
    (tester) async {
      await _pumpSmartEvent(tester, _request(tierLabel: 'GM', minElo: 2500));

      final filters = find.byKey(const ValueKey('smart_event_filters'));
      expect(filters.hitTestable(), findsOneWidget);
      final badge = find.descendant(
        of: filters,
        matching: find.byType(SearchCountBadge),
      );
      // The GM floor is what this smart event is, not a filter on it.
      expect(badge, findsNothing);

      // A level the reader picks is a change: it counts.
      await tester.tap(find.text('GM+').first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('International Master · 2400+').last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(badge, findsOneWidget);
      final count = tester.widget<SearchCountBadge>(badge).count;
      expect(count, 1);
      // The floating search does not repeat it.
      expect(
        find.descendant(
          of: find.byKey(_fab),
          matching: find.byType(SearchCountBadge),
        ),
        findsNothing,
      );

      // It opens the smart event's filters, as the search's does.
      await tester.tap(filters);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(GameFilterDialog), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(GameFilterDialog), findsNothing);

      await tester.tap(find.byKey(_fab));
      await _settleMorph(tester);
      final searchFilters = find.byKey(
        const ValueKey('smart_event_search_filters'),
      );
      expect(searchFilters.hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<SearchCountBadge>(
              find.descendant(
                of: searchFilters,
                matching: find.byType(SearchCountBadge),
              ),
            )
            .count,
        count,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('an untouched GM smart event with no games says so plainly, '
      'never "no matches"', (tester) async {
    await _pumpSmartEvent(tester, _request(tierLabel: 'GM', minElo: 2500));
    expect(find.text('No games right now'), findsOneWidget);
    expect(find.byType(SearchNoMatches), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a Super GM smart event opens on Super GM and loads 2700+ '
      'games', (tester) async {
    final queries = <SmartEventGamesQuery>[];
    await _pumpSmartEvent(
      tester,
      _request(tierLabel: 'Super GM', minElo: 2700),
      aggregate: (ref, query) {
        queries.add(query);
        return _LoadedAggregateNotifier(ref, query);
      },
    );
    // The chip names the tier the floor is, read from the floor, never
    // from the name's first word.
    expect(find.text('Super GM'), findsWidgets);
    expect(queries, isNotEmpty);
    for (final query in queries) {
      expect(query.filter?.minRating, 2700);
    }
    // Its own floor is no filter on it.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('smart_event_filters')),
        matching: find.byType(SearchCountBadge),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Super GM survives a trip through Filters: the dialog offers '
      'it and gives 2700 back', (tester) async {
    await _pumpSmartEvent(
      tester,
      _request(tierLabel: 'Super GM', minElo: 2700),
    );
    await tester.tap(find.byKey(const ValueKey('smart_event_filters')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GameFilterDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GameFilterDialog),
        matching: find.text('Super GM'),
      ),
      findsOneWidget,
    );
    final apply = find.text('Apply Filters');
    await tester.ensureVisible(apply);
    await tester.pump();
    await tester.tap(apply);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GameFilterDialog), findsNothing);
    // Still Super GM, and nothing changed from what it opened with.
    expect(find.text('Super GM'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('smart_event_filters')),
        matching: find.byType(SearchCountBadge),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Apply in Filters keeps the opening an opening smart event is '
      'built on: the dialog offers none, so it gives none back', (
    tester,
  ) async {
    final request = SmartEventRequest.forOpening(GameEcoFilter.forCode('B90'));
    final queries = <SmartEventGamesQuery>[];
    await _pumpSmartEvent(
      tester,
      request,
      aggregate: (ref, query) {
        queries.add(query);
        return _LoadedAggregateNotifier(ref, query);
      },
    );
    expect(queries, isNotEmpty);
    expect(queries.last.filter?.eco, request.eco);
    final filters = find.byKey(const ValueKey('smart_event_filters'));
    final badge = find.descendant(
      of: filters,
      matching: find.byType(SearchCountBadge),
    );
    // Its opening is what it is, not a filter on it.
    expect(badge, findsNothing);

    await tester.tap(filters);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GameFilterDialog), findsOneWidget);
    final apply = find.text('Apply Filters');
    await tester.ensureVisible(apply);
    await tester.pump();
    await tester.tap(apply);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GameFilterDialog), findsNothing);

    // Still the Najdorf's games, and nothing changed from what it opened
    // with: no badge.
    expect(queries.last.filter?.eco, request.eco);
    expect(badge, findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('an untouched GM smart event with nothing on About or Events '
      'says so plainly, never "no matches"; a change the reader makes does', (
    tester,
  ) async {
    await _pumpSmartEvent(tester, _request(tierLabel: 'GM', minElo: 2500));

    await tester.tap(find.text('About'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No tournaments match your filters'), findsNothing);

    await tester.tap(find.text('Events'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No events right now'), findsOneWidget);
    expect(find.byType(SearchNoMatches), findsNothing);

    // A level the reader picks narrows it: now the empty list is theirs.
    await tester.tap(find.text('GM+').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('International Master · 2400+').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('No events right now'), findsNothing);
    expect(find.byType(SearchNoMatches), findsOneWidget);

    await tester.tap(find.text('About'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No tournaments match your filters'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('opened from Search: no Filters in the header or the search', (
    tester,
  ) async {
    await _pumpSmartEvent(
      tester,
      _request(tierLabel: 'GM', minElo: 2500),
      showFilters: false,
    );
    expect(find.byKey(const ValueKey('smart_event_filters')), findsNothing);
    expect(find.byType(SearchModeFilterButton), findsNothing);

    await tester.tap(find.byKey(_fab));
    await _settleMorph(tester);
    expect(find.byKey(_close).hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('smart_event_search_filters')),
      findsNothing,
    );
    expect(find.byType(SearchModeFilterButton), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(_close));
    await _settleMorph(tester);
    expect(find.byKey(_close), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the back chevron holds its place as the search opens', (
    tester,
  ) async {
    await _pumpSmartEvent(tester, _request());
    final chevron = find.byIcon(Icons.arrow_back_ios_new_outlined);
    expect(chevron, findsOneWidget);
    final page = tester.getRect(chevron);

    await tester.tap(find.byKey(_fab));
    await _settleMorph(tester);
    final search = tester.getRect(
      find.descendant(of: find.byKey(_close), matching: chevron),
    );
    expect(search.size, page.size);
    expect(search.center.dx, moreOrLessEquals(page.center.dx, epsilon: 0.5));
    expect(search.center.dy, moreOrLessEquals(page.center.dy, epsilon: 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Filters hold their place on the gutter as the search opens', (
    tester,
  ) async {
    await _pumpSmartEvent(tester, _request(tierLabel: 'GM', minElo: 2500));
    final page = tester.getRect(
      find.byKey(const ValueKey('smart_event_filters')),
    );

    await tester.tap(find.byKey(_fab));
    await _settleMorph(tester);
    final search = tester.getRect(
      find.byKey(const ValueKey('smart_event_search_filters')),
    );
    expect(search.center.dx, moreOrLessEquals(page.center.dx, epsilon: 0.5));
    expect(search.center.dy, moreOrLessEquals(page.center.dy, epsilon: 0.5));
    expect(search.size, page.size);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'back while searching closes the search before it asks about changed '
    'filters',
    (tester) async {
      await _pumpSmartEvent(tester, _request());

      // Change the tier: the config is now dirty.
      await tester.tap(find.text('All').first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Grandmaster · 2500+').last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(_fab));
      await _settleMorph(tester);
      expect(find.byKey(_close).hitTestable(), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(await navigator.maybePop(), isTrue);
      await _settleMorph(tester);
      expect(find.byKey(_close), findsNothing);
      expect(find.text('Apply changes?'), findsNothing);
      expect(find.byType(SmartEventScreen), findsOneWidget);

      expect(await navigator.maybePop(), isTrue);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Apply changes?'), findsOneWidget);
      expect(find.byType(SmartEventScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'a search moves the list to its hits and puts it back where it was, in '
    'the frame the games change',
    (tester) async {
      final keeper = smartEventQueryScrollForTest();
      var query = '';
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              keeper.show(query);
              return ListView.builder(
                controller: keeper.controller,
                itemCount: query.isEmpty ? 200 : 40,
                itemExtent: 50,
                itemBuilder: (context, i) => Text('$query $i'),
              );
            },
          ),
        ),
      );
      keeper.controller.jumpTo(3000);
      await tester.pump();

      rebuild(() => query = 'carl');
      await tester.pump();
      expect(keeper.controller.offset, 0);
      expect(find.text('carl 0'), findsOneWidget);

      keeper.controller.jumpTo(400);
      await tester.pump();
      rebuild(() => query = '');
      await tester.pump();
      expect(keeper.controller.offset, 3000);
      expect(find.text(' 60'), findsOneWidget);

      // A later layout never replays a spent move.
      rebuild(() {});
      await tester.pump();
      expect(keeper.controller.offset, 3000);
    },
  );
}
