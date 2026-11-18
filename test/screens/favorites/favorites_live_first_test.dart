import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/game_list_live_first_provider.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_games_tab.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _liveFirstOff = 'Show live games first';
const _liveFirstOn = 'Live games are shown first';
const _classicalOff = 'Show classical games only';
const _classicalOn = 'Showing classical games only';
const _filters = 'Filters';
const _boardView = 'Change board view';
const _search = 'Search games';
const _closeSearch = 'Close search';
const _filterKey = ValueKey<String>(E2eIds.favoritesGamesFilterButton);
const _searchKey = ValueKey<String>(E2eIds.favoritesGamesSearchField);

void main() {
  group('Favorites header and floating buttons (Trello #1420)', () {
    testWidgets('Games keeps only the board view beside the centred title; '
        'the search and the list controls leave the top', (tester) async {
      final harness = await _pumpScreen(tester);

      final back = tester.getCenter(find.byTooltip('Back'));
      final board = find.byTooltip(_boardView);
      expect(board, findsOneWidget);
      expect(tester.getCenter(board).dy, closeTo(back.dy, 1));
      // The same board-view mark as Countrymen.
      expect(
        find.descendant(of: board, matching: find.byType(BoardViewGlyph)),
        findsOneWidget,
      );
      _expectTitleCentred(tester);

      // Nothing is live, so Live first does not float; Classical and Filters
      // wait in the search; no field sits on the page.
      for (final label in [_liveFirstOff, _classicalOff, _filters]) {
        expect(find.byTooltip(label), findsNothing, reason: label);
      }
      expect(find.byKey(_searchKey), findsNothing);
      expect(find.byKey(_filterKey), findsNothing);

      // The search floats in the thumb's reach.
      final search = tester.getRect(find.byTooltip(_search));
      expect(search.top, greaterThan(852 / 2));
      expect(search.right, greaterThan(393 / 2));
      expect(harness.created, hasLength(1));
    });

    testWidgets('the title row and tabs fold away with the list, the search '
        'slides with them, and a page change brings them back', (tester) async {
      await _pumpScreen(tester);
      final chrome = ScrollChromeScope.maybeOf(
        tester.element(find.byType(PageView)),
      )!;
      final searchTop = tester.getRect(find.byTooltip(_search)).top;

      chrome.hide(animate: false);
      await tester.pump();

      expect(tester.getSize(find.byType(CollapsingChrome)).height, 0);
      // The status-bar inset is not part of the fold: the list now starts
      // right under it.
      expect(tester.getTopLeft(find.byType(PageView)).dy, greaterThan(0));
      expect(
        tester.getRect(find.byTooltip(_search)).top,
        greaterThan(searchTop),
      );

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await _settle(tester);
      expect(chrome.value, 1);
      expect(find.byType(SegmentedSwitcher), findsOneWidget);
    });

    testWidgets('opening on another page never mounts the Games controls', (
      tester,
    ) async {
      final harness = await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.favorites,
      );

      expect(find.byTooltip(_boardView), findsNothing);
      expect(find.byTooltip(_search), findsNothing);
      // Nothing watched the games list, so no games fetch started.
      expect(harness.created, isEmpty);
    });

    testWidgets('other pages keep the centred title with nothing floating', (
      tester,
    ) async {
      final harness = await _pumpScreen(tester);

      harness.container.read(selectedFavoritesModeProvider.notifier).state =
          FavoritesScreenMode.players;
      await tester.pump();

      expect(find.byTooltip(_boardView), findsNothing);
      expect(find.byTooltip(_search), findsNothing);
      _expectTitleCentred(tester);
    });

    testWidgets('the search opens in place: back, the field, Classical and '
        'Filters over the same Games list, and back closes it', (tester) async {
      final harness = await _pumpScreen(tester);

      await _openSearch(tester);

      final field = find.byKey(_searchKey);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      // The header is the search row alone: no title, no tabs, nothing
      // floating.
      expect(_titleText(), findsNothing);
      expect(find.byType(SegmentedSwitcher), findsNothing);
      expect(find.byTooltip(_search), findsNothing);
      expect(find.byType(FavoritesGamesTab), findsOneWidget);
      // One row, left to right: back, field, Classical, Filters.
      final close = tester.getRect(find.byTooltip(_closeSearch));
      final fieldRect = tester.getRect(field);
      final classical = tester.getRect(find.byTooltip(_classicalOff));
      final filters = tester.getRect(find.byKey(_filterKey));
      for (final rect in [fieldRect, classical, filters]) {
        expect(rect.center.dy, closeTo(close.center.dy, 1));
      }
      expect(close.right, lessThanOrEqualTo(fieldRect.left));
      expect(fieldRect.right, lessThanOrEqualTo(classical.left));
      expect(classical.right, lessThanOrEqualTo(filters.left));
      for (final rect in [close, classical, filters]) {
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
      }

      await tester.enterText(field, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      expect(harness.notifier.searches, ['Carlsen']);

      await tester.tap(find.byTooltip(_closeSearch));
      await _settle(tester);

      expect(find.byKey(_searchKey), findsNothing);
      expect(_titleText(), findsOneWidget);
      expect(find.byType(SegmentedSwitcher), findsOneWidget);
      expect(find.byTooltip(_search), findsOneWidget);
      expect(harness.notifier.clears, 1);
      expect(harness.created, hasLength(1));
    });

    testWidgets('system back closes the search, not Favorites', (tester) async {
      final harness = await _pumpScreen(tester);
      await _openSearch(tester);

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(find.byType(FavoritesTabScreen), findsOneWidget);
      expect(find.byKey(_searchKey), findsNothing);
      expect(_titleText(), findsOneWidget);
      expect(harness.notifier.clears, 1);
    });

    testWidgets('Classical in the search turns the server filter to '
        'classical and back', (tester) async {
      final harness = await _pumpScreen(tester);
      await _openSearch(tester);

      await tester.tap(find.byTooltip(_classicalOff));
      await tester.pump();

      expect(
        harness.notifier.applied.last.timeControl,
        GameTimeControlFilter.classical,
      );
      expect(
        harness.container
            .read(favoritesCombinedGamesProvider)
            .filter
            .timeControl,
        GameTimeControlFilter.classical,
      );
      expect(find.byTooltip(_classicalOn), findsOneWidget);
      expect(_toggledState(tester, _classicalOn), isTrue);
      // It is a real filter, so the Filters badge counts it.
      expect(
        find.descendant(of: find.byKey(_filterKey), matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip(_classicalOn));
      await tester.pump();

      expect(
        harness.notifier.applied.last.timeControl,
        GameTimeControlFilter.all,
      );
      expect(find.byTooltip(_classicalOff), findsOneWidget);
      expect(_toggledState(tester, _classicalOff), isFalse);
      expect(
        find.descendant(of: find.byKey(_filterKey), matching: find.text('1')),
        findsNothing,
      );
    });

    testWidgets('Classical stays applied once the search closes, counted on '
        'the floating search', (tester) async {
      final harness = await _pumpScreen(tester);
      Finder searchBadge(String count) => find.descendant(
        of: find.byTooltip(_search),
        matching: find.text(count),
      );
      expect(searchBadge('1'), findsNothing);

      await _openSearch(tester);
      await tester.tap(find.byTooltip(_classicalOff));
      await tester.pump();
      await tester.tap(find.byTooltip(_closeSearch));
      await _settle(tester);

      // Only the query goes with the search; the filter keeps its sign.
      expect(
        harness.container
            .read(favoritesCombinedGamesProvider)
            .filter
            .timeControl,
        GameTimeControlFilter.classical,
      );
      expect(searchBadge('1'), findsOneWidget);

      await _openSearch(tester);
      await tester.tap(find.byTooltip(_classicalOn));
      await tester.pump();
      await tester.tap(find.byTooltip(_closeSearch));
      await _settle(tester);
      expect(searchBadge('1'), findsNothing);
    });

    testWidgets('Filters in the search opens the dialog and Apply lands on '
        'the same notifier with its badge', (tester) async {
      final harness = await _pumpScreen(tester);
      await _openSearch(tester);

      await tester.tap(find.byKey(_filterKey));
      await _settle(tester);
      final whiteWins = find.text('1-0');
      await tester.ensureVisible(whiteWins);
      await tester.tap(whiteWins);
      await tester.tap(find.text('Apply Filters'));
      await _settle(tester);

      expect(harness.created, hasLength(1));
      expect(
        harness.notifier.applied.single.result,
        GameResultFilter.whiteWins,
      );
      expect(
        find.descendant(of: find.byKey(_filterKey), matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('Live first pressed with nothing in play says so and stays '
        'off', (tester) async {
      // Floated by a game that has since finished: the press finds none.
      final harness = await _pumpScreen(tester, anyLive: true);

      await tester.tap(find.byTooltip(_liveFirstOff));
      await tester.pump();

      expect(find.text(kNoLiveGamesRightNowMessage), findsOneWidget);
      expect(kNoLiveGamesRightNowMessage, 'No live games right now');
      expect(
        harness.container.read(
          gameListLiveFirstProvider(GameListLiveFirstSurface.favorites),
        ),
        isFalse,
      );
      expect(_toggledState(tester, _liveFirstOff), isFalse);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('with nothing live there is no Live first, even left on', (
      tester,
    ) async {
      // Left on from earlier, with no game in play now: the button has
      // nothing to do on this list, so it is not on screen (Trello #1420).
      await _pumpScreen(tester, liveFirst: true);

      expect(find.byTooltip(_liveFirstOn), findsNothing);
      expect(find.byTooltip(_liveFirstOff), findsNothing);
      // The search still floats where the thumb rests.
      expect(find.byTooltip(_search), findsOneWidget);
    });

    testWidgets('fits a 320pt phone at the largest text size', (tester) async {
      await _pumpScreen(tester, size: const Size(320, 640), textScale: 1.5);

      expect(tester.takeException(), isNull);
      final board = tester.getRect(find.byTooltip(_boardView));
      expect(board.right, lessThanOrEqualTo(320));
      expect(tester.getRect(_titleText()).right, lessThanOrEqualTo(board.left));

      await _openSearch(tester);
      expect(tester.takeException(), isNull);
      for (final target in [
        find.byTooltip(_closeSearch),
        find.byTooltip(_classicalOff),
        find.byKey(_filterKey),
      ]) {
        final rect = tester.getRect(target);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
      expect(
        tester.getSize(find.byKey(_searchKey)).width,
        greaterThanOrEqualTo(80),
      );
    });
  });

  group('Favorites Live first button with games', () {
    testWidgets('floats only while a game is in play, and turns on and off', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          favoritesCombinedGamesProvider.overrideWith(
            (ref) => _FakeFavoritesGames(
              FavoritesCombinedGamesState(
                hasMore: false,
                games: [
                  _game(
                    'done',
                    status: GameStatus.whiteWins,
                    gameDay: DateTime.now(),
                  ),
                  _game(
                    'live',
                    status: GameStatus.ongoing,
                    lastMoveTime: DateTime.now(),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      var searches = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  floatingActionButton: FavoritesGamesFabs(
                    onSearch: () => searches++,
                  ),
                );
              },
            ),
          ),
        ),
      );
      final provider = gameListLiveFirstProvider(
        GameListLiveFirstSurface.favorites,
      );

      expect(find.byTooltip(_liveFirstOff), findsOneWidget);
      await tester.tap(find.byTooltip(_liveFirstOff));
      await tester.pump();
      expect(container.read(provider), isTrue);
      expect(find.text(kNoLiveGamesRightNowMessage), findsNothing);
      expect(_toggledState(tester, _liveFirstOn), isTrue);

      await tester.tap(find.byTooltip(_liveFirstOn));
      await tester.pump();
      expect(container.read(provider), isFalse);
      // Still a game in play, so it stays to be pressed again.
      expect(find.byTooltip(_liveFirstOff), findsOneWidget);

      await tester.tap(find.byTooltip(_search));
      expect(searches, 1);
    });

    testWidgets('the list keeps clear of the whole button stack over the '
        'home indicator', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          favoritesCombinedGamesProvider.overrideWith(
            (ref) => _FakeFavoritesGames(
              FavoritesCombinedGamesState(hasMore: false),
            ),
          ),
          favoritesGamesAnyLiveProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  // Where the Games list sits: the Scaffold's body.
                  body: const SizedBox.expand(key: ValueKey('list')),
                  floatingActionButton: FavoritesGamesFabs(onSearch: () {}),
                );
              },
            ),
          ),
        ),
      );

      final top = tester.getRect(find.byTooltip(_liveFirstOff)).top;
      final reach = FavoritesGamesFabs.reach(
        tester.element(find.byKey(const ValueKey('list'))),
      );
      expect(852 - top, closeTo(reach, 0.01));
    });
  });

  group('groupFavoriteGamesByDay', () {
    final now = DateTime.utc(2026, 11, 17, 15);
    final today = DateTime.utc(2026, 11, 17);
    final yesterday = DateTime.utc(2026, 11, 16);
    final games = [
      _game('t-done', status: GameStatus.draw, gameDay: today),
      _game('y-done', status: GameStatus.blackWins, gameDay: yesterday),
      _game(
        't-live',
        status: GameStatus.ongoing,
        gameDay: today,
        lastMoveTime: now,
      ),
      _game('t-done-2', status: GameStatus.whiteWins, gameDay: today),
      _game('undated', status: GameStatus.draw),
    ];

    test('keeps the server order inside each day when off', () {
      final grouped = groupFavoriteGamesByDay(games, now: now);
      expect(grouped.keys, ['2026-11-17', '2026-11-16', '0000-00-00']);
      expect(_ids(grouped['2026-11-17']!), ['t-done', 't-live', 't-done-2']);
    });

    test('brings live games to the top of their day when on', () {
      final grouped = groupFavoriteGamesByDay(games, liveFirst: true, now: now);
      expect(grouped.keys, ['2026-11-17', '2026-11-16', '0000-00-00']);
      expect(_ids(grouped['2026-11-17']!), ['t-live', 't-done', 't-done-2']);
      expect(_ids(grouped['2026-11-16']!), ['y-done']);
      expect(_ids(grouped['0000-00-00']!), ['undated']);
    });
  });
}

/// Opens the Games page's full-page search from its floating button.
Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_search));
  await _settle(tester);
}

/// Lets springs and routes finish without waiting on a caret's blink, which
/// never settles while the search field has focus.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The heart and "Favorites" sit dead centre across the screen.
void _expectTitleCentred(WidgetTester tester) {
  final screenWidth = tester.getSize(find.byType(FavoritesTabScreen)).width;
  final heartAndTitle = tester.getRect(
    find.ancestor(of: _titleText(), matching: find.byType(Row)).first,
  );
  expect(heartAndTitle.center.dx, closeTo(screenWidth / 2, 1));
}

Finder _titleText() => find.descendant(
  of: find.byType(FavoritesTabScreen),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data == 'Favorites' &&
        widget.softWrap == false,
  ),
);

bool? _toggledState(WidgetTester tester, String label) {
  final semantics = tester.widget<Semantics>(
    find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  );
  return semantics.properties.toggled;
}

List<String> _ids(List<GamesTourModel> games) => [
  for (final game in games) game.gameId,
];

class _Harness {
  _Harness(this.container, this.created);

  final ProviderContainer container;
  final List<_FakeFavoritesGames> created;

  _FakeFavoritesGames get notifier => created.last;
}

Future<_Harness> _pumpScreen(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double textScale = 1,
  FavoritesScreenMode? initialMode,
  bool liveFirst = false,
  bool? anyLive,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final created = <_FakeFavoritesGames>[];
  final container = ProviderContainer(
    overrides: [
      discoveryDotsSourceProvider.overrideWithValue(_NoDiscoveryDots()),
      favoritePlayersNotifierProvider.overrideWith(_NoFavoritePlayers.new),
      gamesListViewModeProvider.overrideWithValue(GamesListViewMode.gamesCard),
      favoritesCombinedGamesProvider.overrideWith((ref) {
        final notifier = _FakeFavoritesGames(
          FavoritesCombinedGamesState(hasMore: false),
        );
        created.add(notifier);
        return notifier;
      }),
      if (anyLive != null)
        favoritesGamesAnyLiveProvider.overrideWith((ref) => anyLive),
    ],
  );
  addTearDown(container.dispose);
  if (liveFirst) {
    container
            .read(
              gameListLiveFirstProvider(
                GameListLiveFirstSurface.favorites,
              ).notifier,
            )
            .state =
        true;
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        navigatorObservers: [routeObserver],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return FavoritesTabScreen(initialMode: initialMode);
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(container, created);
}

class _FakeFavoritesGames extends StateNotifier<FavoritesCombinedGamesState>
    implements FavoritesCombinedGamesNotifier {
  _FakeFavoritesGames(super.state);

  final List<GameFilter> applied = [];
  final List<String> searches = [];
  int clears = 0;

  @override
  Future<void> applyFilter(GameFilter newFilter) async {
    applied.add(newFilter);
    state = state.copyWith(filter: newFilter);
  }

  @override
  Future<void> searchGames(String query) async {
    searches.add(query);
    state = state.copyWith(searchQuery: query.trim());
  }

  @override
  Future<void> clearSearch() async {
    clears++;
    state = state.copyWith(searchQuery: '');
  }

  @override
  Future<void> refreshGames() async {}

  @override
  Future<void> loadMoreGames() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoFavoritePlayers extends FavoritePlayersNotifier {
  @override
  Future<FavoritePlayersState> build() async =>
      const FavoritePlayersState(players: []);
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
  required GameStatus status,
  DateTime? gameDay,
  DateTime? lastMoveTime,
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player('White'),
    blackPlayer: _player('Black'),
    whiteTimeDisplay: '10:00',
    blackTimeDisplay: '10:00',
    whiteClockCentiseconds: 60000,
    blackClockCentiseconds: 60000,
    whiteClockSeconds: 600,
    blackClockSeconds: 600,
    gameStatus: status,
    roundId: 'round-1',
    tourId: 'tour-1',
    gameDay: gameDay,
    lastMoveTime: lastMoveTime,
    lastMove: lastMoveTime == null ? null : 'e4',
  );
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: '',
    rating: 2500,
    countryCode: 'USA',
    team: null,
  );
}
