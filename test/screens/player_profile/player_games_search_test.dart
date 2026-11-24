import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/tabs/player_games_tab.dart'
    show playerGamesSkeletonKey;
import 'package:chessever2/screens/player_profile/widgets/player_games_event_section.dart';
import 'package:chessever2/screens/player_profile/widgets/player_games_toolbar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/standings/utils/scorecard_name_actions.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:fake_async/fake_async.dart';
import 'package:chessever2/widgets/ink_fab.dart' show InkFabStack;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The player profile's Games tab under its full-page search: the list,
/// its toolbar and its folds are the tab's own, before, during and after.

const _key = PlayerProfileKey(
  playerName: 'Carlsen, Magnus',
  source: PlayerProfileDataSource.twic,
);

const _fabKey = ValueKey<String>(E2eIds.playerGamesSearchFab);
const _fieldKey = ValueKey<String>(E2eIds.playerGamesSearchField);
const _closeKey = ValueKey<String>('player_games_search_close');

void main() {
  // The name's share coachmark opens the app database on first paint, and
  // that open only times out under the test binding. Park one claim in a
  // clock that never runs: the coachmark then stays claimed for this file.
  setUpAll(() {
    FakeAsync().run((_) => playerNameShareCoachmarkTracker.claim());
  });

  group('TWIC games under a search', () {
    test('a new query keeps the list on screen until its first page '
        'lands', () async {
      final pages = _Pages();
      final harness = _container(pages);
      final games = harness.notifier;
      await pages.settle();
      expect(_ids(harness.state), ['a1', 'a2', 'b1']);

      games.setSearchQuery('carl');
      // Asked, not answered: the whole list stays, marked as loading.
      expect(harness.state.isLoading, isTrue);
      expect(_ids(harness.state), ['a1', 'a2', 'b1']);
      expect(harness.state.totalCount, 3);

      await pages.settle();
      expect(harness.state.isLoading, isFalse);
      expect(_ids(harness.state), ['a2']);
      expect(harness.state.totalCount, 1);
    });

    test('clearing the query brings the list back as it was left, with no '
        'reload', () async {
      final pages = _Pages();
      final harness = _container(pages);
      await pages.settle();
      harness.notifier.setSearchQuery('carl');
      await pages.settle();
      final asked = pages.requests.length;

      harness.notifier.setSearchQuery('');

      expect(pages.requests, hasLength(asked));
      expect(harness.state.isLoading, isFalse);
      expect(harness.state.searchQuery, '');
      expect(_ids(harness.state), ['a1', 'a2', 'b1']);
      expect(harness.state.totalCount, 3);
    });

    test(
      'a search cleared after the filters changed reloads instead',
      () async {
        final pages = _Pages();
        final harness = _container(pages);
        await pages.settle();
        harness.notifier.setSearchQuery('carl');
        await pages.settle();
        harness.notifier.applyFilter(
          GameFilter(timeControl: GameTimeControlFilter.rapid),
        );
        await pages.settle();
        final asked = pages.requests.length;

        harness.notifier.setSearchQuery('');

        expect(pages.requests, hasLength(asked + 1));
        expect(harness.state.isLoading, isTrue);
      },
    );

    test('a failed new query is not shown over the old list; a failed '
        'refresh keeps it', () async {
      final pages = _Pages();
      final harness = _container(pages);
      await pages.settle();

      pages.failNext = true;
      await harness.notifier.refresh();
      expect(harness.state.error, isNotNull);
      expect(_ids(harness.state), ['a1', 'a2', 'b1']);

      pages.failNext = true;
      harness.notifier.setSearchQuery('carl');
      await pages.settle();
      expect(harness.state.error, isNotNull);
      expect(harness.state.allGames, isEmpty);
    });

    test("the list's own Clear keeps the search's words", () async {
      final pages = _Pages();
      final harness = _container(pages);
      await pages.settle();
      harness.notifier
        ..setSearchQuery('carl')
        ..setPlayerResultFilter(PlayerResultFilter.win);
      await pages.settle();
      expect(harness.state.filterSheetCount, 1);

      harness.notifier.clearFilter(keepSearchQuery: true);

      expect(harness.state.searchQuery, 'carl');
      expect(harness.state.filterSheetCount, 0);
    });
  });

  group('Games tab and its search', () {
    testWidgets('filters and layout sit on the Games list without searching, '
        'and the search button wears no count of its own', (tester) async {
      final pages = _Pages();
      await _pumpProfile(tester, pages);

      final toolbar = find.byType(PlayerGamesListToolbar);
      expect(toolbar, findsOneWidget);
      expect(
        find.descendant(of: toolbar, matching: find.byType(BoardViewGlyph)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: toolbar,
          matching: find.byType(SearchModeFilterButton),
        ),
        findsOneWidget,
      );
      expect(_toolbarSays('3 games'), findsOneWidget);
      expect(find.byKey(_fieldKey), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(_fabKey),
          matching: find.byType(SearchCountBadge),
        ),
        findsNothing,
      );
    });

    testWidgets('opening and closing the search keeps the list: no '
        'skeleton, no remount, nothing over it moves', (tester) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);
      final listState = tester.state(_gamesList);
      final toolbarTop = tester.getTopLeft(find.byType(PlayerGamesListToolbar));
      final back = tester.getCenter(find.byTooltip('Back'));

      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();

      // The search header took the name row's place over the very same
      // list. The chevron went with the name row: the search's way out is
      // Cancel.
      expect(find.byKey(_fieldKey), findsOneWidget);
      expect(find.byTooltip('Back').hitTestable(), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SearchModeHeader),
          matching: find.byIcon(Icons.arrow_back_ios_new_outlined),
        ),
        findsNothing,
      );
      // Filters and the board view stand at the search header's end while
      // it is open, as on every searched list; the list's toolbar keeps
      // only its count, and the hidden button no count of its own.
      expect(
        find.byKey(const ValueKey('player_games_search_filters')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find
            .descendant(
              of: find.byType(PlayerGamesListToolbar),
              matching: find.byType(SearchModeFilterButton),
            )
            .hitTestable(),
        findsNothing,
      );
      // X's row: the field from the gutter, the list's controls outside
      // it with Filters last, then Cancel, its word ending on the gutter.
      final gutter = SearchHeaderMetrics.gutter;
      final field = tester.getRect(
        find.descendant(
          of: find.byType(SearchModeHeader),
          matching: find.byType(SearchFieldFill),
        ),
      );
      final filters = tester.getRect(
        find.byKey(const ValueKey('player_games_search_filters')),
      );
      final cancel = tester.getRect(find.byKey(_closeKey));
      final word = tester.getRect(
        find.descendant(
          of: find.byKey(_closeKey),
          matching: find.text('Cancel'),
        ),
      );
      expect(field.left, closeTo(gutter, 0.01));
      expect(field.right, lessThanOrEqualTo(filters.left + 0.01));
      expect(filters.right, closeTo(cancel.left, 0.01));
      expect(word.right, closeTo(393 - gutter, 0.01));
      expect(word.center.dy, closeTo(field.center.dy, 0.01));
      expect(tester.state(_gamesList), same(listState));
      expect(_toolbarSays('3 games'), findsOneWidget);
      final searchToolbarTop = tester.getTopLeft(
        find.byType(PlayerGamesListToolbar),
      );

      pages.hold = true;
      await tester.enterText(find.byKey(_fieldKey), 'carl');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // Asked, not answered yet: the whole list stays under a quiet line,
      // and the toolbar does not move for the query.
      expect(harness.read().searchQuery, 'carl');
      expect(harness.read().isLoading, isTrue);
      expect(find.text('Loading games...'), findsNothing);
      expect(find.byKey(playerGamesSkeletonKey), findsNothing);
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsOneWidget);
      expect(tester.state(_gamesList), same(listState));
      expect(
        tester.getTopLeft(find.byType(PlayerGamesListToolbar)),
        searchToolbarTop,
      );

      pages.release();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live_gamebase_a2')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsNothing);
      expect(_toolbarSays('1 game'), findsOneWidget);
      final asked = pages.requests.length;

      await tester.tap(find.byKey(_closeKey));
      await tester.pumpAndSettle();

      // Closed: the list the reader left, at once and with no reload.
      expect(find.byKey(_fieldKey), findsNothing);
      expect(harness.read().searchQuery, '');
      expect(pages.requests, hasLength(asked));
      expect(find.text('Loading games...'), findsNothing);
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsOneWidget);
      expect(_toolbarSays('3 games'), findsOneWidget);
      expect(tester.state(_gamesList), same(listState));
      expect(
        tester.getTopLeft(find.byType(PlayerGamesListToolbar)),
        toolbarTop,
      );
      // The page's chevron is back where it was, in reach.
      expect(tester.getCenter(find.byTooltip('Back').hitTestable()), back);
    });

    testWidgets('sections folded on the Games tab open for the hits and '
        'fold again after', (tester) async {
      final pages = _Pages();
      await _pumpProfile(tester, pages);
      // Event B is the last section: fold it.
      final fold = find.byType(PlayerGamesCollapseToggle).last;
      await tester.ensureVisible(fold);
      await tester.pumpAndSettle();
      await tester.tap(fold);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsNothing);

      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      // Opening alone changes nothing on the list.
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsNothing);

      await tester.enterText(find.byKey(_fieldKey), 'black');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsOneWidget);

      await tester.tap(find.byKey(_closeKey));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsNothing);
    });

    testWidgets('a search that finds nothing says so; the next keystroke '
        'waits quietly, with no skeleton, and Clear brings the list back', (
      tester,
    ) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);
      final listState = tester.state(_gamesList);
      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(_fieldKey), 'zzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // No hits for the query: not "this player has no games". The words
      // are echoed, and with no filter on, the way back clears them.
      expect(find.byType(PlayerGamesNoMatches), findsOneWidget);
      expect(find.text('No matches for "zzz"'), findsOneWidget);
      expect(find.text('Clear search'), findsOneWidget);
      expect(find.text('This player has no recorded games yet.'), findsNothing);
      expect(_toolbarSays('0 games'), findsOneWidget);

      pages.hold = true;
      await tester.enterText(find.byKey(_fieldKey), 'zzzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // Asked, not answered: a quiet line, never the page's skeleton, and
      // the toolbar keeps its count.
      expect(harness.read().searchQuery, 'zzzz');
      expect(harness.read().isLoading, isTrue);
      expect(find.byKey(playerGamesSkeletonKey), findsNothing);
      expect(find.text('Loading games...'), findsNothing);
      expect(find.text('Searching games...'), findsOneWidget);
      expect(_toolbarSays('0 games'), findsOneWidget);
      expect(tester.state(_gamesList), same(listState));

      pages.release();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerGamesNoMatches), findsOneWidget);
      final asked = pages.requests.length;

      // Clear empties the field and lands on the list the search started
      // from, at once, with the search still open.
      await tester.tap(find.byKey(const ValueKey('search_no_matches_clear')));
      await tester.pumpAndSettle();
      expect(harness.read().searchQuery, '');
      expect(pages.requests, hasLength(asked));
      expect(find.byKey(_fieldKey), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(_fieldKey), matching: find.text('zzzz')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsOneWidget);
      expect(_toolbarSays('3 games'), findsOneWidget);
      expect(tester.state(_gamesList), same(listState));
    });

    testWidgets('a filter that matches nothing outside a search says so, '
        'and the next one waits quietly', (tester) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);

      harness.notifier.applyFilter(
        GameFilter(timeControl: GameTimeControlFilter.blitz),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlayerGamesNoMatches), findsOneWidget);
      expect(find.text('This player has no recorded games yet.'), findsNothing);

      pages.hold = true;
      harness.notifier.setPlayerResultFilter(PlayerResultFilter.win);
      await tester.pump();
      expect(find.byKey(playerGamesSkeletonKey), findsNothing);
      expect(find.text('Searching games...'), findsOneWidget);
      // The count the reader last saw stays beside the filters.
      expect(
        find.descendant(
          of: find.byType(PlayerGamesListToolbar),
          matching: find.textContaining('2 filters · 0 games'),
        ),
        findsOneWidget,
      );

      pages.release();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerGamesNoMatches), findsOneWidget);
      // No words to echo; the filters empty the list, and the way back
      // clears them.
      expect(find.text('No matching games'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(harness.read().filterSheetCount, 0);
      expect(find.byType(PlayerGamesNoMatches), findsNothing);
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsOneWidget);
    });

    testWidgets('Clear filters keeps an open search\'s words', (tester) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);
      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), 'carl');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      harness.notifier.applyFilter(
        GameFilter(timeControl: GameTimeControlFilter.blitz),
      );
      await tester.pumpAndSettle();

      expect(find.text('No matches for "carl"'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(harness.read().searchQuery, 'carl');
      expect(harness.read().filterSheetCount, 0);
      expect(find.byKey(const ValueKey('live_gamebase_a2')), findsOneWidget);
      expect(find.byKey(_fieldKey), findsOneWidget);
    });

    testWidgets('the list ends clear of the search button, and gives that '
        'room up as the search opens', (tester) async {
      final pages = _Pages();
      await _pumpProfile(tester, pages);
      final end = find.byType(SearchModeListEnd, skipOffstage: false);
      expect(end, findsOneWidget);
      final closed = tester.getSize(end).height;
      final fab = tester.getRect(find.byKey(_fabKey));
      // What the button covers, from its top to the screen's bottom.
      expect(closed, greaterThanOrEqualTo(852 - fab.top));

      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      expect(tester.getSize(end).height, lessThan(closed));
    });

    testWidgets('the search floats in the floating stack, and the list\'s '
        'toolbar heads the list instead of snapping back as a second header', (
      tester,
    ) async {
      final pages = _Pages();
      await _pumpProfile(tester, pages);
      expect(
        find.ancestor(
          of: find.byKey(_fabKey),
          matching: find.byType(InkFabStack),
        ),
        findsOneWidget,
      );
      final bar = tester.widget<SliverAppBar>(
        find.ancestor(
          of: find.byType(PlayerGamesListToolbar),
          matching: find.byType(SliverAppBar),
        ),
      );
      expect(bar.floating, isFalse);
      expect(bar.snap, isFalse);
      expect(bar.pinned, isFalse);
    });

    testWidgets('a first page that leaves the list\'s end in view asks '
        'for the next one with no scroll', (tester) async {
      final pages = _Pages()..more = true;
      await _pumpProfile(tester, pages);
      // Three games end well inside the screen and nothing scrolls: the
      // list asks on its own. This pins the behaviour, not which of the
      // list's two askers (the footer as it is built, the list's measure as
      // the page lands) gets there first.
      expect(pages.pageNumbers.first, 0);
      expect(pages.pageNumbers, contains(1));
    });

    testWidgets('system back closes the search before the profile', (
      tester,
    ) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);
      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), 'carl');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(PlayerProfileScreen), findsOneWidget);
      expect(find.byKey(_fieldKey), findsNothing);
      expect(harness.read().searchQuery, '');
    });
  });
}

/// The Games list's own scrollable (inside the profile's page view).
final Finder _gamesList = find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

/// [text] on the list's toolbar (the sections' stats count games too).
Finder _toolbarSays(String text) => find.descendant(
  of: find.byType(PlayerGamesListToolbar),
  matching: find.text(text),
);

List<String> _ids(PlayerProfileGamesState state) =>
    state.allGames.map((game) => game.gameId).toList();

/// TWIC pages: the whole list, or what a query matches. [hold] keeps the
/// next answer back until [release].
class _Pages {
  final List<PlayerProfileGamesState> requests = [];
  bool failNext = false;
  bool hold = false;
  Completer<void>? _held;

  /// The first page says more can come; the next one is empty and last.
  bool more = false;

  /// The page numbers asked for, in order.
  final List<int> pageNumbers = [];

  static final List<GamesTourModel> all = [
    _game('a1', event: 'Event A', white: 'Nakamura', day: 3),
    _game('a2', event: 'Event A', white: 'Carlsen', day: 2),
    _game('b1', event: 'Event B', white: 'Caruana', day: 1),
  ];

  Future<PlayerGamesTwicPage> load(
    PlayerProfileGamesState state,
    int pageNumber,
  ) async {
    requests.add(state);
    pageNumbers.add(pageNumber);
    if (hold) {
      hold = false;
      await (_held = Completer<void>()).future;
    }
    await Future<void>.delayed(Duration.zero);
    if (failNext) {
      failNext = false;
      throw StateError('offline');
    }
    final query = state.searchQuery.toLowerCase();
    final games = all
        .where(
          (game) =>
              query.isEmpty ||
              game.whitePlayer.name.toLowerCase().contains(query) ||
              game.blackPlayer.name.toLowerCase().contains(query),
        )
        .where(
          (game) =>
              state.playerResultFilter == PlayerResultFilter.all ||
              game.gameStatus == GameStatus.whiteWins,
        )
        // No blitz games on record.
        .where((_) => state.filter.timeControl != GameTimeControlFilter.blitz)
        .where((_) => !more || pageNumber == 0)
        .toList();
    return (
      games: games,
      hasMore: more && pageNumber == 0,
      nextPageNumber: pageNumber + 1,
      totalCount: more ? all.length : games.length,
    );
  }

  void release() => _held?.complete();

  /// Lets every page asked for so far land.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class _Harness {
  _Harness(this.container);

  final ProviderContainer container;

  PlayerProfileGamesNotifier get notifier =>
      container.read(playerProfileGamesKeyProvider(_key).notifier);
  PlayerProfileGamesState get state =>
      container.read(playerProfileGamesKeyProvider(_key));
  PlayerProfileGamesState read() => state;
}

_Harness _container(_Pages pages) {
  final container = ProviderContainer(
    overrides: [
      playerProfileGamesKeyProvider.overrideWith(
        (ref, key) => PlayerProfileGamesNotifier(
          ref,
          key,
          debugTwicPageLoader: pages.load,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(playerProfileGamesKeyProvider(_key), (_, _) {});
  return _Harness(container);
}

Future<_Harness> _pumpProfile(WidgetTester tester, _Pages pages) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final container = ProviderContainer(
    overrides: [
      playerProfileGamesKeyProvider.overrideWith(
        (ref, key) => PlayerProfileGamesNotifier(
          ref,
          key,
          debugTwicPageLoader: pages.load,
        ),
      ),
      playerProfileDataKeyProvider.overrideWith((ref, key) async => null),
      twicProfileSummaryProvider.overrideWith((ref, key) async => null),
      playerEventsKeyProvider.overrideWith(
        (ref, key) async => const <PlayerEventData>[],
      ),
      favoritePlayersProviderNew.overrideWith(_NoFavorites.new),
      discoveryDotsSourceProvider.overrideWithValue(_NoDiscoveryDots()),
      gamesListViewModeProvider.overrideWithValue(GamesListViewMode.gamesCard),
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
            return const PlayerProfileScreen(
              playerName: 'Carlsen, Magnus',
              initialTab: PlayerProfileTab.games,
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(container);
}

class _NoFavorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

class _NoDiscoveryDots implements DiscoveryDotsSource {
  @override
  Future<String> initialize() async => '';

  @override
  Future<String> fetch() async => '';

  @override
  Stream<String> get updates => const Stream<String>.empty();
}

GamesTourModel _game(
  String id, {
  required String event,
  required String white,
  required int day,
}) {
  return GamesTourModel(
    gameId: id,
    source: GameSource.twic,
    whitePlayer: _player(white),
    blackPlayer: _player('Black'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: '1',
    roundSlug: '1',
    tourId: event,
    // The canonical event name the profile groups by.
    pgn: '[Event "$event"]\n[Site "?"]\n\n1. e4 e5 1-0',
    lastMoveTime: DateTime.utc(2026, 11, day),
  );
}

PlayerCard _player(String name) => PlayerCard(
  name: name,
  federation: '',
  title: '',
  rating: 2700,
  countryCode: '',
  team: null,
);
