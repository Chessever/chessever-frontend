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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _liveFirstOff = 'Show live games first';
const _liveFirstOn = 'Live games are shown first';
const _classicalOff = 'Show classical games only';
const _classicalOn = 'Showing classical games only';
const _filters = 'Filters';
const _boardView = 'Change board view';
const _filterKey = ValueKey<String>(E2eIds.favoritesGamesFilterButton);
const _searchKey = ValueKey<String>(E2eIds.favoritesGamesSearchField);

void main() {
  group('Favorites title row (Trello #1420)', () {
    testWidgets('Games mode carries the controls beside the title, above '
        'a search row that holds only the search field', (tester) async {
      final harness = await _pumpScreen(tester);

      final back = tester.getCenter(find.byTooltip('Back'));
      for (final label in [
        _liveFirstOff,
        _classicalOff,
        _filters,
        _boardView,
      ]) {
        final control = find.byTooltip(label);
        expect(control, findsOneWidget, reason: label);
        // Same row as back and the title.
        expect(
          tester.getCenter(control).dy,
          closeTo(back.dy, 1),
          reason: label,
        );
      }

      final searchTop = tester.getTopLeft(find.byKey(_searchKey)).dy;
      expect(
        tester.getBottomLeft(find.byKey(_filterKey)).dy,
        lessThan(searchTop),
      );
      // The title sits left, right after back, before every control.
      final title = tester.getRect(_titleText());
      expect(title.left, greaterThan(back.dx));
      expect(
        title.right,
        lessThanOrEqualTo(tester.getTopLeft(find.byTooltip(_liveFirstOff)).dx),
      );

      // The one Filters glyph is the title row's: nothing is left beside the
      // search field.
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FavoritesGamesTab),
          matching: find.byIcon(Icons.tune_rounded),
        ),
        findsNothing,
      );
      // The same board-view mark as Countrymen.
      expect(
        find.descendant(
          of: find.byTooltip(_boardView),
          matching: find.byType(BoardViewGlyph),
        ),
        findsOneWidget,
      );
      expect(harness.created, hasLength(1));
    });

    testWidgets('opening on another page never mounts the Games controls', (
      tester,
    ) async {
      final harness = await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.favorites,
      );

      expect(find.byTooltip(_filters), findsNothing);
      // Nothing watched the games list, so no games fetch started.
      expect(harness.created, isEmpty);
    });

    testWidgets('other modes keep the centred title without game controls', (
      tester,
    ) async {
      final harness = await _pumpScreen(tester);

      harness.container.read(selectedFavoritesModeProvider.notifier).state =
          FavoritesScreenMode.players;
      await tester.pump();

      for (final label in [
        _liveFirstOff,
        _classicalOff,
        _filters,
        _boardView,
      ]) {
        expect(find.byTooltip(label), findsNothing, reason: label);
      }
      final screenWidth = tester.getSize(find.byType(FavoritesTabScreen)).width;
      final heartAndTitle = tester.getRect(
        find.ancestor(of: _titleText(), matching: find.byType(Row)).first,
      );
      expect(heartAndTitle.center.dx, closeTo(screenWidth / 2, 1));
    });

    testWidgets('Classical turns the server filter to classical and back', (
      tester,
    ) async {
      final harness = await _pumpScreen(tester);

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

    testWidgets('Live first with no live game says so and stays off', (
      tester,
    ) async {
      final harness = await _pumpScreen(tester);

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
      expect(find.byTooltip(_liveFirstOff), findsOneWidget);
      expect(_toggledState(tester, _liveFirstOff), isFalse);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('Filters opens the dialog and Apply lands on the same notifier '
        'with its badge', (tester) async {
      final harness = await _pumpScreen(tester);

      await tester.tap(find.byKey(_filterKey));
      await tester.pumpAndSettle();
      final whiteWins = find.text('1-0');
      await tester.ensureVisible(whiteWins);
      await tester.tap(whiteWins);
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

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

    testWidgets('fits a 320pt phone at the largest text size', (tester) async {
      await _pumpScreen(tester, size: const Size(320, 640), textScale: 1.5);

      expect(tester.takeException(), isNull);
      for (final label in [
        _liveFirstOff,
        _classicalOff,
        _filters,
        _boardView,
      ]) {
        final rect = tester.getRect(find.byTooltip(label));
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
        expect(rect.right, lessThanOrEqualTo(320), reason: label);
      }
      expect(
        tester.getRect(_titleText()).right,
        lessThanOrEqualTo(tester.getTopLeft(find.byTooltip(_liveFirstOff)).dx),
      );
    });
  });

  group('Favorites title controls with games', () {
    testWidgets('Live first turns on when a game is live, and off again', (
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
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  body: Center(child: FavoritesGamesTitleControls()),
                );
              },
            ),
          ),
        ),
      );
      final provider = gameListLiveFirstProvider(
        GameListLiveFirstSurface.favorites,
      );

      await tester.tap(find.byTooltip(_liveFirstOff));
      await tester.pump();
      expect(container.read(provider), isTrue);
      expect(find.text(kNoLiveGamesRightNowMessage), findsNothing);
      expect(_toggledState(tester, _liveFirstOn), isTrue);

      await tester.tap(find.byTooltip(_liveFirstOn));
      await tester.pump();
      expect(container.read(provider), isFalse);
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
    ],
  );
  addTearDown(container.dispose);

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

  @override
  Future<void> applyFilter(GameFilter newFilter) async {
    applied.add(newFilter);
    state = state.copyWith(filter: newFilter);
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
