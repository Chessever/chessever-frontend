import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryPadlock;
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/for_you/discovery/reports_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_date_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ---------------------------------------------------------------- doubles

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

/// Engine settings without SharedPreferences: the game cards read them.
class _EngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  _EngineSettings(this._settings);

  final EngineSettings _settings;

  @override
  Future<EngineSettings> build() async => _settings;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// No Spoilers off, without a Supabase read.
class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _ReportsRepository implements DiscoveryRepository {
  final requests =
      <
        ({
          AnalyzedGamesCursor? after,
          ReportGameType? gameType,
          Completer<AnalyzedGamesPage> result,
        })
      >[];

  @override
  Future<AnalyzedGamesPage> fetchAnalyzedGamesPage({
    int pageSize = 30,
    AnalyzedGamesCursor? after,
    DateTime? since,
    ReportGameType? gameType,
  }) {
    final result = Completer<AnalyzedGamesPage>();
    requests.add((after: after, gameType: gameType, result: result));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected call');
}

CloudEval _eval(String fen) => CloudEval(
  fen: fen,
  knodes: 0,
  depth: 20,
  pvs: [Pv(moves: 'e2e4', cp: 40)],
  requestedMultiPv: 1,
);

const _fen = '6k1/5pp1/7p/3P4/1r6/6P1/5PKP/3R4 w - - 0 38';

/// A finished broadcast game with a position to draw, unless [position] is
/// false (no FEN, no last move: the grid keeps it a list row).
GamesTourModel _game(
  String id, {
  bool position = true,
  GameSource source = GameSource.supabase,
  GameStatus status = GameStatus.whiteWins,
  DateTime? lastMoveTime,
}) {
  PlayerCard player(String name) => PlayerCard(
    name: name,
    federation: 'IND',
    title: 'GM',
    rating: 2700,
    countryCode: 'IN',
    team: null,
  );
  return GamesTourModel(
    gameId: id,
    source: source,
    whitePlayer: player('White, Player'),
    blackPlayer: player('Black, Player'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: status,
    roundId: 'round-1',
    tourId: 'tour-1',
    fen: position ? _fen : null,
    lastMove: position ? 'e2e4' : null,
    lastMoveTime: lastMoveTime,
  );
}

List<GamesTourModel> _games(int n) => [
  for (var i = 0; i < n; i++) _game('g$i'),
];

// ---------------------------------------------------------------- pump

const _phone = Size(393, 852);
const _tablet = Size(1024, 1366);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  GamesListViewMode mode = GamesListViewMode.chessBoardGrid,
  Size screen = _phone,
  double textScale = 1,
  EngineSettings engine = const EngineSettings(),
  bool tickers = true,
  bool scrollingPage = false,
  List<Override> extraOverrides = const [],
}) async {
  // Tall enough that every card builds; the page believes it is [screen].
  tester.view.physicalSize = scrollingPage ? screen : Size(screen.width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      gamesListViewModeProvider.overrideWithValue(mode),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      engineSettingsProviderNew.overrideWith(() => _EngineSettings(engine)),
      playerPhotoProvider.overrideWith((ref, fideId) async => null),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
      ),
      gameCardEvalWithStockfishFallbackProvider.overrideWith(
        (ref, fen) async => _eval(fen),
      ),
      gameCardEvalCacheOnlyProvider.overrideWith(
        (ref, fen) async => _eval(fen),
      ),
      ...extraOverrides,
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale), size: screen),
          child: app!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: TickerMode(
                enabled: tickers,
                child: scrollingPage
                    ? child
                    : SingleChildScrollView(child: child),
              ),
            );
          },
        ),
      ),
    ),
  );
  await _settle(tester);
  return container;
}

/// The skeleton shimmers forever, so never pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Game cards leave a short timer behind, and the event-video cache they
/// start keeps a periodic one for as long as its container lives.
Future<void> _teardown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
  container.dispose();
}

Finder get _gridCards => find.byType(GridGameCardWrapperWidget);
Finder get _listCards => find.byType(GameCardWrapperWidget);

double _height(WidgetTester tester, Type type) =>
    tester.getSize(find.byType(type)).height;

void main() {
  group('Reports infinite scrolling', () {
    final scrollView = find.byKey(const PageStorageKey('reports_scroll'));

    ScrollPosition position(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(of: scrollView, matching: find.byType(Scrollable))
              .first,
        )
        .position;

    Future<ProviderContainer> open(
      WidgetTester tester,
      _ReportsRepository repository, {
      GamesListViewMode mode = GamesListViewMode.chessBoardGrid,
      Size screen = _phone,
      double textScale = 1,
      bool hasAccess = false,
    }) => _pump(
      tester,
      const ReportsScreen(),
      mode: mode,
      screen: screen,
      textScale: textScale,
      scrollingPage: true,
      extraOverrides: [
        discoveryRepositoryProvider.overrideWithValue(repository),
        premiumAccessProvider.overrideWithValue(hasAccess),
      ],
    );

    Future<void> complete(
      WidgetTester tester,
      _ReportsRepository repository,
      int request,
      List<GamesTourModel> items, {
      String? next,
    }) async {
      repository.requests[request].result.complete(
        AnalyzedGamesPage(
          items: items,
          nextCursor: next == null
              ? null
              : (lastMoveTime: '2026-09-28T12:00:00Z', gameId: next),
        ),
      );
      await _settle(tester);
    }

    for (final mode in GamesListViewMode.values) {
      testWidgets('Reports cards are the same with and without access in '
          '$mode', (tester) async {
        Size? cardSize;
        for (final hasAccess in [false, true]) {
          final repository = _ReportsRepository();
          final container = await open(
            tester,
            repository,
            mode: mode,
            hasAccess: hasAccess,
          );
          await complete(tester, repository, 0, [_game('report')]);
          expect(find.byType(DiscoveryPadlock), findsNothing);
          final cardFinder = find.byType(DiscoveryGameCard).first;
          final card = tester.widget<DiscoveryGameCard>(cardFinder);
          // The tap is the only gate, and the long-press rows are the
          // card's own for both tiers.
          expect(card.onOpen, isNotNull);
          final menus = [
            ...tester
                .widgetList<GridGameCardWrapperWidget>(_gridCards)
                .map((c) => c.menuActions),
            ...tester
                .widgetList<GameCardWrapperWidget>(_listCards)
                .map((c) => c.menuActions),
          ];
          expect(menus, [null]);
          // No label slot for either tier: one card height.
          final size = tester.getSize(cardFinder);
          expect(size, cardSize ?? size);
          cardSize = size;
          expect(tester.takeException(), isNull);
          await _teardown(tester, container);
        }
      });
    }

    testWidgets(
      'chips scroll as one row, switch queries, and ignore late prior results',
      (tester) async {
        final repository = _ReportsRepository();
        final container = await open(
          tester,
          repository,
          mode: GamesListViewMode.gamesCard,
          screen: const Size(320, 852),
          textScale: 1.6,
        );
        await complete(tester, repository, 0, [_game('all')]);
        final upside = find.byKey(const ValueKey('report_type_upside_down'));
        await tester.ensureVisible(upside);
        await tester.tap(upside);
        await _settle(tester);
        expect(repository.requests.last.gameType, ReportGameType.upsideDown);
        final comeback = find.byKey(const ValueKey('report_type_comeback'));
        await tester.ensureVisible(comeback);
        await tester.tap(comeback);
        await _settle(tester);
        expect(repository.requests.last.gameType, ReportGameType.comeback);
        await complete(tester, repository, 2, [_game('comeback')]);
        await complete(tester, repository, 1, [_game('late-upside')]);
        expect(
          container.read(reportsPaginationProvider).items.single.gameId,
          'comeback',
        );
        final marathon = find.byKey(const ValueKey('report_type_marathon'));
        await tester.ensureVisible(marathon);
        await tester.tap(marathon);
        await _settle(tester);
        expect(repository.requests.last.gameType, ReportGameType.marathon);
        await complete(tester, repository, 3, []);
        expect(find.text('No Marathon reports yet.'), findsOneWidget);
        final all = find.byKey(const ValueKey('report_type_all'));
        await tester.ensureVisible(all);
        await tester.tap(all);
        await _settle(tester);
        expect(
          container.read(reportsPaginationProvider).items.single.gameId,
          'all',
        );
        expect(
          repository.requests,
          hasLength(4),
          reason: 'All reuses only its own first-page cache',
        );
        // Exercise every actual chip through a pointer, including ones which
        // begin off-screen at this narrow width and large text size.
        for (final type in ReportGameType.values) {
          final chip = find.byKey(ValueKey('report_type_${type.key}'));
          await tester.ensureVisible(chip);
          await tester.tap(chip);
          await _settle(tester);
          expect(repository.requests.last.gameType, type);
          await complete(
            tester,
            repository,
            repository.requests.length - 1,
            [],
          );
          expect(find.text('No ${type.label} reports yet.'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await _teardown(tester, container);
      },
    );

    for (final mode in GamesListViewMode.values) {
      testWidgets(
        'prefetches near the bottom and builds only visible cards: ${mode.name}',
        (tester) async {
          final repository = _ReportsRepository();
          final container = await open(tester, repository, mode: mode);
          await complete(tester, repository, 0, _games(30), next: 'g29');
          expect(repository.requests, hasLength(1));
          expect(
            find.byType(DiscoveryGameCard).evaluate().length,
            lessThan(30),
          );

          final scroll = position(tester);
          // Lazy lists revise their extent estimate when a distant row lays
          // out. Reach the actual threshold after that correction, just as
          // continued scrolling does, without requiring eager board layout.
          for (
            var attempt = 0;
            attempt < 3 && scroll.extentAfter > 600;
            attempt++
          ) {
            scroll.jumpTo(scroll.maxScrollExtent - 400);
            await _settle(tester);
          }
          expect(
            repository.requests,
            hasLength(2),
            reason: 'Remaining extent after layout: ${scroll.extentAfter}',
          );
          expect(scroll.extentAfter, greaterThan(0));
          expect(
            container.read(reportsPaginationProvider).items,
            hasLength(30),
          );
          await _settle(tester);
          expect(repository.requests, hasLength(2));

          final offset = scroll.pixels;
          await complete(
            tester,
            repository,
            1,
            List.generate(30, (i) => _game('g${i + 30}')),
          );
          expect(
            container.read(reportsPaginationProvider).items,
            hasLength(60),
          );
          expect(scroll.pixels, moreOrLessEquals(offset));
          scroll.jumpTo(scroll.maxScrollExtent);
          await _settle(tester);
          expect(repository.requests, hasLength(2));
          expect(
            find.byType(DiscoveryGameCard).evaluate().length,
            lessThan(30),
          );
          final visible = tester.widgetList<DiscoveryGameCard>(
            find.byType(DiscoveryGameCard),
          );
          expect(visible.any((card) => card.index >= 30), isTrue);
          expect(visible.every((list) => list.games.length == 60), isTrue);
          expect(tester.takeException(), isNull);
          await _teardown(tester, container);
        },
      );
    }

    testWidgets(
      'Miniatures day headers collapse and keep paging into older days',
      (tester) async {
        final now = DateTime.now();
        final today = DateTime.utc(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final repository = _ReportsRepository();
        final container = await open(tester, repository);
        await complete(
          tester,
          repository,
          0,
          _games(30).map((g) => g.copyWith(lastMoveTime: today)).toList(),
          next: 'g29',
        );
        expect(find.byType(GameDateHeader), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        await tester.tap(find.text('Today'));
        await _settle(tester);
        expect(find.byType(DiscoveryGameCard), findsNothing);
        expect(repository.requests, hasLength(2));

        await complete(tester, repository, 1, [
          _game('same-day', lastMoveTime: today),
        ], next: 'same-day');
        expect(find.byType(DiscoveryGameCard), findsNothing);
        expect(repository.requests, hasLength(3));
        await complete(tester, repository, 2, [
          _game('older-day', lastMoveTime: yesterday),
        ]);
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Yesterday'), findsOneWidget);
        final card = tester.widget<DiscoveryGameCard>(
          find.byType(DiscoveryGameCard),
        );
        expect(card.index, 31);
        expect(card.games, hasLength(32));

        await tester.tap(find.text('Today'));
        await _settle(tester);
        expect(
          tester
              .widgetList<DiscoveryGameCard>(find.byType(DiscoveryGameCard))
              .any((card) => card.index == 0),
          isTrue,
        );
        expect(repository.requests, hasLength(3));
        expect(tester.takeException(), isNull);
        await _teardown(tester, container);
      },
    );

    for (final screen in [_phone, const Size(1366, 1024)]) {
      testWidgets(
        'matches Miniatures grid columns at $screen with large text',
        (tester) async {
          final repository = _ReportsRepository();
          final container = await open(
            tester,
            repository,
            screen: screen,
            textScale: 1.3,
          );
          await complete(tester, repository, 0, _games(8));
          final columns = screen.width > 1000 ? 4 : 2;
          final top = tester.getTopLeft(
            find.byKey(const ValueKey('discovery_grid_g0')),
          );
          for (var i = 1; i < columns; i++) {
            final cell = tester.getTopLeft(
              find.byKey(ValueKey('discovery_grid_g$i')),
            );
            expect(cell.dy, top.dy);
            expect(cell.dx, greaterThan(top.dx));
          }
          final nextRow = tester.getTopLeft(
            find.byKey(ValueKey('discovery_grid_g$columns')),
          );
          expect(nextRow.dy, greaterThan(top.dy));
          expect(nextRow.dx, top.dx);
          expect(tester.takeException(), isNull);
          await _teardown(tester, container);
        },
      );
    }

    testWidgets(
      'continues through empty candidate pages and fills a short viewport',
      (tester) async {
        final repository = _ReportsRepository();
        final container = await open(
          tester,
          repository,
          mode: GamesListViewMode.chessBoard,
        );
        await complete(tester, repository, 0, [], next: 'filtered');
        expect(repository.requests, hasLength(2));
        await complete(tester, repository, 1, [_game('a')], next: 'a');
        expect(repository.requests, hasLength(3));
        await complete(tester, repository, 2, [_game('b'), _game('c')]);
        expect(container.read(reportsPaginationProvider).items, hasLength(3));
        expect(container.read(reportsPaginationProvider).hasMore, isFalse);
        expect(tester.takeException(), isNull);
        await _teardown(tester, container);
      },
    );

    testWidgets(
      'footer Retry keeps the loaded collection and resumes the failed page',
      (tester) async {
        final repository = _ReportsRepository();
        final container = await open(tester, repository);
        await complete(tester, repository, 0, _games(30), next: 'g29');
        final scroll = position(tester);
        scroll.jumpTo(scroll.maxScrollExtent);
        await _settle(tester);
        repository.requests[1].result.completeError(StateError('offline'));
        await _settle(tester);
        scroll.jumpTo(scroll.maxScrollExtent);
        await _settle(tester);
        expect(container.read(reportsPaginationProvider).items, hasLength(30));
        expect(repository.requests, hasLength(2));
        expect(find.text("Couldn't load more reports"), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await _settle(tester);
        expect(repository.requests, hasLength(3));
        expect(repository.requests[2].after, repository.requests[1].after);
        await complete(tester, repository, 2, [_game('last')]);
        expect(container.read(reportsPaginationProvider).items, hasLength(31));
        expect(find.text('Retry'), findsNothing);
        expect(tester.takeException(), isNull);
        await _teardown(tester, container);
      },
    );

    testWidgets('pull to refresh starts from the newest page', (tester) async {
      final repository = _ReportsRepository();
      final container = await open(tester, repository);
      await complete(tester, repository, 0, _games(30), next: 'g29');
      await tester.drag(scrollView, const Offset(0, 400));
      await _settle(tester);
      expect(repository.requests, hasLength(2));
      expect(repository.requests[1].after, isNull);
      await complete(tester, repository, 1, [_game('fresh')]);
      expect(
        container.read(reportsPaginationProvider).items.single.gameId,
        'fresh',
      );
      expect(tester.takeException(), isNull);
      await _teardown(tester, container);
    });
  });

  group('limit', () {
    testWidgets('grid: draws 4 of 12, and opening the 4th hands the board '
        'all 12', (tester) async {
      final games = _games(12);
      List<GamesTourModel>? opened;
      int? openedAt;
      final container = await _pump(
        tester,
        DiscoveryGameList(
          games: games,
          limit: 4,
          boardLimit: 2,
          streamEnabled: false,
          onOpen: (list, index) {
            opened = list;
            openedAt = index;
          },
        ),
      );

      expect(_gridCards, findsNWidgets(4));
      for (final card in tester.widgetList<GridGameCardWrapperWidget>(
        _gridCards,
      )) {
        expect(card.orderedGames, hasLength(12));
      }

      await tester.tap(find.byKey(const ValueKey('discovery_grid_g3')));
      await tester.pump();
      expect(openedAt, 3);
      expect(opened, hasLength(12));
      expect(opened!.map((g) => g.gameId), games.map((g) => g.gameId));
      expect(tester.takeException(), isNull);
      await _teardown(tester, container);
    });

    testWidgets('list: draws 4 rows, each walking all 12', (tester) async {
      List<GamesTourModel>? opened;
      final container = await _pump(
        tester,
        DiscoveryGameList(
          games: _games(12),
          limit: 4,
          boardLimit: 2,
          streamEnabled: false,
          onOpen: (list, index) => opened = list,
        ),
        mode: GamesListViewMode.gamesCard,
      );

      expect(_listCards, findsNWidgets(4));
      for (final card in tester.widgetList<GameCardWrapperWidget>(_listCards)) {
        expect(card.gamesData.gamesTourModels, hasLength(12));
      }
      await tester.tap(find.byKey(const ValueKey('discovery_row_g2')));
      await tester.pump();
      expect(opened, hasLength(12));
      await _teardown(tester, container);
    });

    testWidgets('board view takes boardLimit', (tester) async {
      final container = await _pump(
        tester,
        DiscoveryGameList(
          games: _games(12),
          limit: 4,
          boardLimit: 2,
          streamEnabled: false,
        ),
        mode: GamesListViewMode.chessBoard,
      );

      expect(_listCards, findsNWidgets(2));
      expect(find.byKey(const ValueKey('discovery_board_g1')), findsOneWidget);
      expect(find.byKey(const ValueKey('discovery_board_g2')), findsNothing);
      await _teardown(tester, container);
    });

    testWidgets('grid: a game without a position is still a grid card '
        '(the user\'s chosen type), and counts toward the limit', (
      tester,
    ) async {
      final games = [
        _game('a'),
        _game('b', position: false),
        _game('c'),
        _game('d'),
        _game('e'),
        _game('f'),
      ];
      final container = await _pump(
        tester,
        DiscoveryGameList(games: games, limit: 4, streamEnabled: false),
      );

      expect(_gridCards, findsNWidgets(4));
      expect(find.byKey(const ValueKey('discovery_grid_b')), findsOneWidget);
      expect(find.byKey(const ValueKey('discovery_row_b')), findsNothing);
      expect(find.byKey(const ValueKey('discovery_grid_e')), findsNothing);
      await _teardown(tester, container);
    });

    testWidgets('board and list views draw every game as the chosen type, '
        'positions or not', (tester) async {
      final games = [_game('a'), _game('b', position: false), _game('c')];
      for (final (mode, boards) in [
        (GamesListViewMode.chessBoard, true),
        (GamesListViewMode.gamesCard, false),
      ]) {
        final container = await _pump(
          tester,
          DiscoveryGameList(games: games, streamEnabled: false),
          mode: mode,
        );
        final cards = tester
            .widgetList<GameCardWrapperWidget>(
              find.byType(GameCardWrapperWidget),
            )
            .toList();
        expect(cards, hasLength(3), reason: '$mode');
        expect(
          cards.every((c) => c.isChessBoardVisible == boards),
          isTrue,
          reason: '$mode: one card type for every game',
        );
        expect(_gridCards, findsNothing);
        await _teardown(tester, container);
      }
    });

    testWidgets('without a limit every game is drawn', (tester) async {
      final container = await _pump(
        tester,
        DiscoveryGameList(games: _games(5), streamEnabled: false),
      );
      expect(_gridCards, findsNWidgets(5));
      await _teardown(tester, container);
    });
  });

  group('labels', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('hold one line, so paired cards keep one top edge '
          '(text x$scale)', (tester) async {
        final container = await _pump(
          tester,
          DiscoveryGameList(
            games: _games(4),
            limit: 4,
            streamEnabled: false,
            labelFor: (i) => switch (i) {
              0 => DiscoveryCardMeta(
                parts: const [
                  DiscoveryMetaPart.figure('19', unit: ' moves'),
                  DiscoveryMetaPart.figure('2751', prefix: 'Ø '),
                  DiscoveryMetaPart.text(
                    'FIDE World Rapid & Blitz Championships 2026',
                  ),
                ],
                semanticsLabel: '19 moves',
              ),
              // A card with no label keeps the slot.
              1 => null,
              _ => const DiscoveryCardMeta(
                parts: [DiscoveryMetaPart.figure('24', unit: ' moves')],
                semanticsLabel: '24 moves',
              ),
            },
          ),
          textScale: scale,
        );

        double top(String id) =>
            tester.getTopLeft(find.byKey(ValueKey('discovery_grid_$id'))).dy;
        expect(top('g0'), top('g1'));
        expect(top('g2'), top('g3'));
        expect(top('g0'), greaterThan(0));
        // Each label is exactly one line.
        final lines = tester.widgetList<DiscoveryCardMeta>(
          find.byType(DiscoveryCardMeta),
        );
        expect(lines, hasLength(3));
        final heights = find
            .byType(DiscoveryCardMeta)
            .evaluate()
            .map((e) => (e.renderObject! as RenderBox).size.height)
            .toSet();
        expect(heights, hasLength(1));
        expect(tester.takeException(), isNull);
        await _teardown(tester, container);
      });
    }

    testWidgets('sit over a board card on the board\'s own edge, and not '
        'over a list row', (tester) async {
      Widget label(int i) => DiscoveryCardMeta(
        key: ValueKey('label_$i'),
        parts: const [DiscoveryMetaPart.figure('19', unit: ' moves')],
        semanticsLabel: '19 moves',
      );
      var container = await _pump(
        tester,
        DiscoveryGameList(
          games: _games(2),
          streamEnabled: false,
          labelFor: label,
        ),
        mode: GamesListViewMode.chessBoard,
      );
      final card = tester.getTopLeft(
        find.byKey(const ValueKey('discovery_board_g0')),
      );
      final line = tester.getTopLeft(find.byKey(const ValueKey('label_0')));
      expect(line.dx, card.dx + 24);
      expect(line.dy, lessThan(card.dy));
      await _teardown(tester, container);

      container = await _pump(
        tester,
        DiscoveryGameList(
          games: _games(2),
          streamEnabled: false,
          labelFor: label,
        ),
        mode: GamesListViewMode.gamesCard,
      );
      expect(find.byType(DiscoveryCardMeta), findsNothing);
      await _teardown(tester, container);
    });
  });

  group('row labels, rows from an offset and menus', () {
    Widget label(int i) => DiscoveryCardMeta(
      key: ValueKey('row_label_$i'),
      parts: [DiscoveryMetaPart.figure('${19 + i}', unit: ' moves')],
      semanticsLabel: '${19 + i} moves',
    );

    testWidgets('a row label sits over each list row on the names\' edge, '
        'and the strip keeps a line of its own', (tester) async {
      final games = [
        for (final g in _games(2))
          g.copyWith(eco: 'B90', openingName: 'Sicilian Najdorf'),
      ];
      final container = await _pump(
        tester,
        DiscoveryGameList(
          games: games,
          streamEnabled: false,
          rowLabelFor: label,
        ),
        mode: GamesListViewMode.gamesCard,
      );
      final row = tester.getTopLeft(
        find.byKey(const ValueKey('discovery_row_g0')),
      );
      final line = tester.getTopLeft(find.byKey(const ValueKey('row_label_0')));
      expect(line.dx, row.dx + 16);
      expect(line.dy, lessThan(row.dy));
      final cards = tester.widgetList<GameCardWrapperWidget>(_listCards);
      for (final card in cards) {
        expect(card.footerDetail, startsWith('Sicilian Najdorf'));
      }
      await _teardown(tester, container);
    });

    testWidgets('start draws from its offset, yet each card walks the whole '
        'list', (tester) async {
      final container = await _pump(
        tester,
        DiscoveryGameList(
          games: _games(9),
          start: 4,
          limit: 2,
          streamEnabled: false,
        ),
      );
      expect(find.byKey(const ValueKey('discovery_grid_g4')), findsOneWidget);
      expect(find.byKey(const ValueKey('discovery_grid_g5')), findsOneWidget);
      expect(_gridCards, findsNWidgets(2));
      for (final card in tester.widgetList<GridGameCardWrapperWidget>(
        _gridCards,
      )) {
        expect(card.orderedGames, hasLength(9));
      }
      expect(
        DiscoveryGameList.shownFor(
          GamesListViewMode.chessBoard,
          9,
          limit: 4,
          boardLimit: 2,
          start: 8,
        ),
        1,
      );
      await _teardown(tester, container);
    });

    for (final mode in GamesListViewMode.values) {
      testWidgets('a host\'s own menu reaches every card ($mode)', (
        tester,
      ) async {
        final container = await _pump(
          tester,
          DiscoveryGameList(
            games: _games(2),
            streamEnabled: false,
            menuActionsFor: (context, i) => const [],
          ),
          mode: mode,
        );
        final grid = tester
            .widgetList<GridGameCardWrapperWidget>(_gridCards)
            .map((c) => c.menuActions);
        final list = tester
            .widgetList<GameCardWrapperWidget>(_listCards)
            .map((c) => c.menuActions);
        final all = [...grid, ...list];
        expect(all, hasLength(2));
        expect(all.every((m) => m != null), isTrue);
        await _teardown(tester, container);
      });
    }
  });

  group('streams and engine', () {
    final live = _game('live', status: GameStatus.ongoing);
    final finished = _game('done');
    final archive = _game('archive', source: GameSource.gamebase);
    final key = LiveGamesBatchKey(scopeId: 'my_space:games', gameIds: ['live']);

    for (final mode in [
      GamesListViewMode.chessBoardGrid,
      GamesListViewMode.gamesCard,
    ]) {
      testWidgets('liveBatchKeyFor reaches only the games that can stream '
          '($mode)', (tester) async {
        final asked = <int>[];
        final container = await _pump(
          tester,
          DiscoveryGameList(
            games: [live, finished, archive],
            liveBatchKeyFor: (i) {
              asked.add(i);
              return key;
            },
          ),
          mode: mode,
          // No live channel in a test: the cards read their game as is.
          tickers: false,
        );

        expect(asked.toSet(), {0});
        if (mode == GamesListViewMode.chessBoardGrid) {
          final cards = {
            for (final c in tester.widgetList<GridGameCardWrapperWidget>(
              _gridCards,
            ))
              c.game.gameId: c,
          };
          expect(cards['live']!.liveBatchKey, key);
          expect(cards['live']!.streamEnabled, isTrue);
          for (final id in ['done', 'archive']) {
            expect(cards[id]!.liveBatchKey, isNull, reason: id);
            expect(cards[id]!.streamEnabled, isFalse, reason: id);
          }
        } else {
          final cards = {
            for (final c in tester.widgetList<GameCardWrapperWidget>(
              _listCards,
            ))
              c.game.gameId: c,
          };
          expect(cards['live']!.liveBatchKey, key);
          expect(cards['live']!.streamEnabled, isTrue);
          for (final id in ['done', 'archive']) {
            expect(cards[id]!.liveBatchKey, isNull, reason: id);
            expect(cards[id]!.streamEnabled, isFalse, reason: id);
          }
        }
        await _teardown(tester, container);
      });
    }

    testWidgets('an archive list never streams, even with a batch', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        DiscoveryGameList(
          games: [live, finished],
          streamEnabled: false,
          liveBatchKeyFor: (_) => key,
        ),
        tickers: false,
      );
      for (final c in tester.widgetList<GridGameCardWrapperWidget>(
        _gridCards,
      )) {
        expect(c.streamEnabled, isFalse);
        expect(c.liveBatchKey, isNull);
      }
      await _teardown(tester, container);
    });

    testWidgets('no card runs the engine unless asked', (tester) async {
      var container = await _pump(
        tester,
        DiscoveryGameList(games: _games(2), streamEnabled: false),
      );
      for (final c in tester.widgetList<GridGameCardWrapperWidget>(
        _gridCards,
      )) {
        expect(c.allowStockfishFallback, isFalse);
      }
      await _teardown(tester, container);

      container = await _pump(
        tester,
        DiscoveryGameList(
          games: _games(2),
          streamEnabled: false,
          allowStockfishFallback: true,
        ),
        mode: GamesListViewMode.gamesCard,
      );
      for (final c in tester.widgetList<GameCardWrapperWidget>(_listCards)) {
        expect(c.allowStockfishFallback, isTrue);
      }
      await _teardown(tester, container);
    });
  });

  group('padding', () {
    testWidgets('padded sets the gutter; unpadded fills its parent', (
      tester,
    ) async {
      var container = await _pump(
        tester,
        DiscoveryGameList(games: _games(1), streamEnabled: false),
        mode: GamesListViewMode.gamesCard,
      );
      expect(tester.getTopLeft(_listCards).dx, 16);
      await _teardown(tester, container);

      container = await _pump(
        tester,
        DiscoveryGameList(
          games: _games(1),
          streamEnabled: false,
          padded: false,
        ),
        mode: GamesListViewMode.gamesCard,
      );
      expect(tester.getTopLeft(_listCards).dx, 0);
      await _teardown(tester, container);
    });
  });

  group('skeleton', () {
    // Every view, labelled or not, padded or not, gauge on or off, phone
    // and tablet: the skeleton stands exactly as tall as the cards that
    // replace it, so nothing below it moves when the games land.
    final cases = [
      for (final mode in GamesListViewMode.values)
        for (final labels in [false, true])
          (
            mode: mode,
            labels: labels,
            padded: true,
            gauge: true,
            screen: _phone,
            scale: 1.0,
          ),
      (
        mode: GamesListViewMode.chessBoardGrid,
        labels: false,
        padded: false,
        gauge: true,
        screen: _phone,
        scale: 1.0,
      ),
      (
        mode: GamesListViewMode.gamesCard,
        labels: true,
        padded: true,
        gauge: true,
        screen: _phone,
        scale: 1.3,
      ),
      (
        mode: GamesListViewMode.chessBoardGrid,
        labels: false,
        padded: true,
        gauge: false,
        screen: _phone,
        scale: 1.0,
      ),
      (
        mode: GamesListViewMode.chessBoard,
        labels: false,
        padded: true,
        gauge: false,
        screen: _phone,
        scale: 1.0,
      ),
      (
        mode: GamesListViewMode.chessBoardGrid,
        labels: true,
        padded: true,
        gauge: true,
        screen: _tablet,
        scale: 1.0,
      ),
      (
        mode: GamesListViewMode.chessBoard,
        labels: false,
        padded: true,
        gauge: true,
        screen: _tablet,
        scale: 1.0,
      ),
      (
        mode: GamesListViewMode.chessBoardGrid,
        labels: true,
        padded: true,
        gauge: true,
        screen: _phone,
        scale: 1.3,
      ),
      (
        mode: GamesListViewMode.chessBoard,
        labels: true,
        padded: true,
        gauge: true,
        screen: _phone,
        scale: 1.3,
      ),
    ];

    for (final c in cases) {
      testWidgets('is as tall as the loaded list: ${c.mode.name}'
          '${c.labels ? ', labelled' : ''}'
          '${c.padded ? '' : ', unpadded'}'
          '${c.gauge ? '' : ', no eval bar'}'
          '${c.screen == _tablet ? ', tablet' : ''}'
          '${c.scale == 1 ? '' : ', text x${c.scale}'}', (tester) async {
        final engine = EngineSettings(showEngineGaugeInGrid: c.gauge);
        var container = await _pump(
          tester,
          DiscoveryGameList(
            games: _games(12),
            limit: 4,
            boardLimit: 2,
            padded: c.padded,
            streamEnabled: false,
            labelFor: c.labels
                ? (i) => DiscoveryCardMeta(
                    parts: [DiscoveryMetaPart.figure('${19 + i}')],
                    semanticsLabel: '${19 + i}',
                  )
                : null,
            rowLabelFor: c.labels
                ? (i) => DiscoveryCardMeta(
                    parts: [DiscoveryMetaPart.figure('${19 + i}')],
                    semanticsLabel: '${19 + i}',
                  )
                : null,
          ),
          mode: c.mode,
          screen: c.screen,
          engine: engine,
          textScale: c.scale,
        );
        final loaded = _height(tester, DiscoveryGameList);
        final loadedWidth = tester
            .getSize(find.byType(DiscoveryGameList))
            .width;
        await _teardown(tester, container);

        container = await _pump(
          tester,
          DiscoveryGameListSkeleton(
            count: 4,
            boardCount: 2,
            labels: c.labels,
            rowLabels: c.labels,
            padded: c.padded,
          ),
          mode: c.mode,
          screen: c.screen,
          engine: engine,
          textScale: c.scale,
        );
        final skeleton = _height(tester, DiscoveryGameListSkeleton);
        expect(
          tester.getSize(find.byType(DiscoveryGameListSkeleton)).width,
          loadedWidth,
        );
        expect(skeleton, moreOrLessEquals(loaded, epsilon: 0.01));
        expect(tester.takeException(), isNull);
        await _teardown(tester, container);
      });
    }
  });
}
