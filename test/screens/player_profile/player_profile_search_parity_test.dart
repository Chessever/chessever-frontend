import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/tabs/player_games_tab.dart'
    show playerGamesStaleRowsKey;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/standings/utils/scorecard_name_actions.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The player profile's search, against what it did before the navigation
/// overhaul (38.17.6, the last release before the 38.18.0 shell).
///
/// PM and owner report, 2026-11-22, on GM Boris Alterman's Games tab:
/// "Search disappeared here. I mean when I click search it is not working
/// the same way." The owner expects it to work as before, fully.
///
/// Before (38.17.6): a search row headed the Games list (field, Filters,
/// board view) under the profile's name, tabs and its Build Tree / Save to
/// Library actions, which all stayed on screen. Typing narrowed the list on
/// the server (TWIC `q`, every game of the player, not only the loaded
/// page) after 400ms, and the words stayed with the list across tabs.
///
/// Reported: a floating search button on the Games tab only. Its glass
/// flew into a field that took the place of the whole profile header (name,
/// tabs, Build Tree, Save to Library), and a tab change dropped the words;
/// the query still went to the server.
///
/// Fixed: the glass flies into the name row only. The tabs, Build Tree and
/// Save to Library ("Filtered games") stay drawn and in reach under the
/// field, the tabs swipe, the words stay with the list across tabs (the
/// field comes back with them on Games), and the rows a query will replace
/// step back until its hits land.
///
/// The first group pins what kept working, the second the report itself,
/// the third the fix.

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

  group('Player profile search: what still works', () {
    testWidgets('About and Events carry no search, as before; Games does', (
      tester,
    ) async {
      final pages = _Pages();
      await _pumpProfile(tester, pages, initialTab: PlayerProfileTab.about);
      expect(find.byKey(_fabKey), findsNothing);
      expect(find.byKey(_fieldKey), findsNothing);

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      expect(find.byKey(_fabKey), findsNothing);
      expect(find.byKey(_fieldKey), findsNothing);

      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();
      expect(find.byKey(_fabKey).hitTestable(), findsOneWidget);
    });

    testWidgets('reached from About, the button opens a focused field and '
        'the query narrows every game of the player on the server', (
      tester,
    ) async {
      final pages = _Pages();
      final harness = await _pumpProfile(
        tester,
        pages,
        initialTab: PlayerProfileTab.about,
      );
      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_fieldKey), findsOneWidget);
      expect(_field(tester).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.enterText(find.byKey(_fieldKey), 'carl');
      await tester.pump(const Duration(milliseconds: 399));
      // Not before the pause: one server query per pause, as before.
      expect(harness.read().searchQuery, '');
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      // Asked of the server (TWIC `q`), not filtered from the loaded page.
      expect(pages.requests.last.searchQuery, 'carl');
      expect(pages.pageNumbers.last, 0);
      expect(find.byKey(const ValueKey('live_gamebase_a2')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsNothing);
    });

    for (final mode in [
      GamesListViewMode.chessBoardGrid,
      GamesListViewMode.chessBoard,
    ]) {
      testWidgets('the board view (${mode.name}) searches the same way', (
        tester,
      ) async {
        final pages = _Pages();
        final harness = await _pumpProfile(tester, pages, viewMode: mode);
        await tester.tap(find.byKey(_fabKey));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_fieldKey), 'carl');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(harness.read().allGames.map((g) => g.gameId), ['a2']);
      });
    }

    testWidgets('Done keeps the hits while words are typed; with none it '
        'closes the search and the button comes back', (tester) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);
      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), 'carl');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(_fieldKey), findsOneWidget);
      expect(harness.read().searchQuery, 'carl');

      await tester.enterText(find.byKey(_fieldKey), '');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(_fieldKey), findsNothing);
      expect(find.byKey(_fabKey).hitTestable(), findsOneWidget);
      expect(harness.read().allGames.map((g) => g.gameId), ['a1', 'a2', 'b1']);
    });

    testWidgets('iOS: close restores the whole list and the button opens '
        'the search again', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final pages = _Pages();
        final harness = await _pumpProfile(tester, pages);
        await tester.tap(find.byKey(_fabKey));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_fieldKey), 'carl');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_closeKey));
        await tester.pumpAndSettle();
        expect(find.byKey(_fieldKey), findsNothing);
        expect(harness.read().allGames.map((g) => g.gameId), [
          'a1',
          'a2',
          'b1',
        ]);

        await tester.tap(find.byKey(_fabKey));
        await tester.pumpAndSettle();
        expect(find.byKey(_fieldKey), findsOneWidget);
        expect(_field(tester).controller.text, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a route opened from the hits comes back to the same '
        'search', (tester) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);
      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), 'carl');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.byKey(_fieldKey), findsOneWidget);
      expect(harness.read().searchQuery, 'carl');
    });
  });

  group('PM report 2026-11-22: search does not work the same way', () {
    // 38.17.6: the field sat at the head of the Games list; focusing it and
    // typing left the profile's name, its tabs and the Games actions where
    // they were, and Save to Library offered the searched games ("Filtered
    // games", the search counted as a filter). As reported, the search
    // header took the whole header's place: tabs, Build Tree and Save to
    // Library were gone (not drawn, not hit-testable) for as long as the
    // search was open, so a searched list could not be saved or taken to
    // another tab. It now takes the name row only.
    testWidgets('searching keeps the profile header, its tabs and Save to '
        'Library (Filtered games) on screen, as the 38.17 search row did', (
      tester,
    ) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);
      expect(find.text('Save to Library').hitTestable(), findsOneWidget);

      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), 'carl');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(harness.read().searchQuery, 'carl');
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsNothing);

      expect(
        find.text('About').hitTestable(),
        findsOneWidget,
        reason: 'the tabs stayed on screen while searching in 38.17',
      );
      expect(
        find.text('Save to Library').hitTestable(),
        findsOneWidget,
        reason:
            'the searched games could be saved to the Library in 38.17 '
            '(Save to Library stayed under the search)',
      );
      expect(
        find.text('Filtered games').hitTestable(),
        findsOneWidget,
        reason: 'Save to Library offered the searched games as filtered',
      );
    });
  });

  group('Search works as before, in the new header (fixed 2026-11-22)', () {
    testWidgets('the field takes only the name row: the tabs and the Games '
        'actions hold still under it, and the button flies back on close', (
      tester,
    ) async {
      final pages = _Pages();
      await _pumpProfile(tester, pages);
      final tabsTop = tester.getTopLeft(find.text('About'));
      final saveTop = tester.getTopLeft(find.text('Save to Library'));
      final back = tester.getCenter(find.byTooltip('Back'));

      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();

      // The chevron holds its spot, the name row gives way to the field.
      expect(tester.getCenter(find.byKey(_closeKey)), back);
      expect(find.byKey(_fieldKey).hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(find.text('About')), tabsTop);
      expect(tester.getTopLeft(find.text('Save to Library')), saveTop);
      expect(find.text('Build Tree'), findsNothing);
      expect(find.byKey(_fabKey).hitTestable(), findsNothing);

      await tester.tap(find.byKey(_closeKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_fieldKey), findsNothing);
      expect(find.byKey(_fabKey).hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(find.text('About')), tabsTop);
    });

    testWidgets('the words stay with the list across tabs: About keeps them, '
        'and back on Games the field comes back with them, keyboard down', (
      tester,
    ) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);
      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), 'carl');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final asked = pages.requests.length;

      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      // The field follows the tab (Games only); the words stay asked.
      expect(find.byKey(_fieldKey), findsNothing);
      expect(find.byKey(_fabKey), findsNothing);
      expect(harness.read().searchQuery, 'carl');

      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();
      expect(find.byKey(_fieldKey).hitTestable(), findsOneWidget);
      expect(_field(tester).controller.text, 'carl');
      expect(_field(tester).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      // Nothing asked again: the list on screen already answers it.
      expect(pages.requests, hasLength(asked));
      expect(find.byKey(const ValueKey('live_gamebase_a2')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsNothing);
      expect(find.text('Filtered games').hitTestable(), findsOneWidget);

      // Closing still clears them and brings the whole list back.
      await tester.tap(find.byKey(_closeKey));
      await tester.pumpAndSettle();
      expect(harness.read().searchQuery, '');
      expect(harness.read().allGames.map((g) => g.gameId), ['a1', 'a2', 'b1']);
      expect(find.byKey(_fabKey).hitTestable(), findsOneWidget);
    });

    testWidgets('words typed inside the pause go with the tab change too', (
      tester,
    ) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);
      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), 'caru');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      expect(harness.read().searchQuery, 'caru');

      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();
      expect(_field(tester).controller.text, 'caru');
      expect(harness.read().allGames.map((g) => g.gameId), ['b1']);
    });

    testWidgets('the tabs swipe while searching, as they did over the old '
        'search row', (tester) async {
      final pages = _Pages();
      final harness = await _pumpProfile(tester, pages);
      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), 'carl');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(_fieldKey), findsNothing);
      expect(harness.read().searchQuery, 'carl');
    });

    testWidgets('typing reads as working at once: the rows a query will '
        'replace step back until its hits land', (tester) async {
      final pages = _Pages();
      await _pumpProfile(tester, pages);
      double rowsOpacity() => tester
          .widget<SliverOpacity>(find.byKey(playerGamesStaleRowsKey))
          .opacity;
      expect(rowsOpacity(), 1);

      await tester.tap(find.byKey(_fabKey));
      await tester.pumpAndSettle();
      pages.hold = true;
      await tester.enterText(find.byKey(_fieldKey), 'carl');
      await tester.pump(const Duration(milliseconds: 400));
      // The quiet line runs while it waits: no settling, the dim's spring
      // lands well inside half a second.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Still there and in reach, stepped back.
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsOneWidget);
      expect(rowsOpacity(), lessThan(0.6));

      pages.release();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live_gamebase_b1')), findsNothing);
      expect(rowsOpacity(), 1);
    });
  });
}

EditableText _field(WidgetTester tester) => tester.widget<EditableText>(
  find.descendant(
    of: find.byKey(_fieldKey),
    matching: find.byType(EditableText),
  ),
);

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

Future<_Harness> _pumpProfile(
  WidgetTester tester,
  _Pages pages, {
  PlayerProfileTab initialTab = PlayerProfileTab.games,
  GamesListViewMode viewMode = GamesListViewMode.gamesCard,
}) async {
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
      // The About tab's stats ask the gamebase for the player's id.
      twicPlayerIdProvider.overrideWith((ref, key) async => null),
      twicPlayerStatsProvider.overrideWith((ref, request) async => null),
      playerEventsKeyProvider.overrideWith(
        (ref, key) async => const <PlayerEventData>[],
      ),
      favoritePlayersProviderNew.overrideWith(_NoFavorites.new),
      discoveryDotsSourceProvider.overrideWithValue(_NoDiscoveryDots()),
      gamesListViewModeProvider.overrideWithValue(viewMode),
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
            return PlayerProfileScreen(
              playerName: 'Carlsen, Magnus',
              initialTab: initialTab,
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
