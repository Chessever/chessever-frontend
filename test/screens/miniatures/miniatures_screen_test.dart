import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_game.dart';
import 'package:chessever2/screens/miniatures/miniatures_screen.dart';
import 'package:chessever2/screens/miniatures/widgets/miniature_game_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

typedef _PageHandler =
    Future<GamebaseMiniaturesPage> Function(_MiniaturesRequest request);

class _MiniaturesRequest {
  const _MiniaturesRequest({
    required this.filter,
    required this.limit,
    required this.offset,
  });

  final MiniatureGamesFilter filter;
  final int limit;
  final int offset;
}

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository(this._handler, {this.fullGame})
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final _PageHandler _handler;
  final GamebaseGameWithPgn? fullGame;
  final List<_MiniaturesRequest> requests = <_MiniaturesRequest>[];
  final List<String> fullGameRequests = <String>[];

  @override
  Future<GamebaseMiniaturesPage> getMiniatures({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) {
    final request = _MiniaturesRequest(
      filter: filter,
      limit: limit,
      offset: offset,
    );
    requests.add(request);
    return _handler(request);
  }

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async {
    fullGameRequests.add(id);
    return fullGame;
  }
}

void main() {
  testWidgets(
    'renders full-screen floating chrome, semantic cards, and 48px controls',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = _repositoryWith(<GamebaseMiniature>[
        _miniature('game-1'),
      ]);
      String? opened;

      await _pumpScreen(
        tester,
        repository: repository,
        screen: MiniaturesScreen(
          onOpenMiniature: (miniature) => opened = miniature.gameId,
          onRequirePremiumFeature: () => true,
        ),
      );

      expect(find.byType(GlassFullScreenPage), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SliverAppBar), findsNothing);
      expect(find.byType(SliverPersistentHeader), findsNothing);
      expect(find.text('Decisive by move 25'), findsOneWidget);
      expect(find.text('Tata Steel Masters'), findsOneWidget);
      expect(find.text('B90 · Sicilian Defense · Najdorf'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Miniature game, Alpha versus Beta, White won 1-0, ended in 18 moves.*open complete game',
          ),
        ),
        findsOneWidget,
      );

      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('miniatures-filter-button')),
            )
            .shortestSide,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('miniatures-window-today')),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSize(find.bySemanticsLabel('Back from miniatures'))
            .shortestSide,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('miniature-card-game-1')),
      );
      await tester.pump();
      expect(opened, 'game-1');
      semantics.dispose();
    },
  );

  testWidgets('shows honest loading, empty, and cold error states', (
    tester,
  ) async {
    final pending = Completer<GamebaseMiniaturesPage>();
    final loadingRepository = _FakeGamebaseRepository((_) => pending.future);
    await _pumpScreen(tester, repository: loadingRepository);

    expect(
      find.byKey(const ValueKey<String>('miniatures-loading-state')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('miniatures-skeleton-0')),
      findsOneWidget,
    );

    pending.complete(_page(const <GamebaseMiniature>[], total: 0));
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey<String>('miniatures-empty-state')),
      findsOneWidget,
    );
    expect(find.text('No miniatures here'), findsOneWidget);

    final errorRepository = _FakeGamebaseRepository(
      (_) => Future<GamebaseMiniaturesPage>.error(
        StateError('network unavailable'),
      ),
    );
    await _pumpScreen(tester, repository: errorRepository);

    expect(
      find.byKey(const ValueKey<String>('miniatures-cold-error-state')),
      findsOneWidget,
    );
    expect(find.text('Miniatures could not load'), findsOneWidget);
    expect(find.textContaining('placeholder games'), findsOneWidget);
  });

  testWidgets('cold error retry replaces the error with canonical data', (
    tester,
  ) async {
    var attempt = 0;
    final repository = _FakeGamebaseRepository((request) {
      attempt += 1;
      if (attempt == 1) {
        return Future<GamebaseMiniaturesPage>.error(
          StateError('temporary outage'),
        );
      }
      return Future<GamebaseMiniaturesPage>.value(
        _page(<GamebaseMiniature>[_miniature('recovered')], total: 1),
      );
    });
    await _pumpScreen(tester, repository: repository);

    await tester.tap(
      find.byKey(const ValueKey<String>('miniatures-state-action')),
    );
    await _pumpFrames(tester);

    expect(repository.requests, hasLength(2));
    expect(
      find.byKey(const ValueKey<String>('miniature-card-recovered')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('miniatures-cold-error-state')),
      findsNothing,
    );
  });

  testWidgets('retains rows on pagination error and retries the same page', (
    tester,
  ) async {
    var laterAttempts = 0;
    final repository = _FakeGamebaseRepository((request) {
      if (request.offset == 0) {
        return Future<GamebaseMiniaturesPage>.value(
          _page(<GamebaseMiniature>[
            _miniature('first'),
            _miniature('second'),
          ], total: 4),
        );
      }
      laterAttempts += 1;
      if (laterAttempts == 1) {
        return Future<GamebaseMiniaturesPage>.error(StateError('page failed'));
      }
      return Future<GamebaseMiniaturesPage>.value(
        _page(
          <GamebaseMiniature>[_miniature('third'), _miniature('fourth')],
          total: 4,
          offset: 2,
        ),
      );
    });
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(393, 1200),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('miniatures-load-more')),
    );
    await _pumpFrames(tester);

    expect(find.byType(MiniatureGameCard), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('miniatures-pagination-error')),
      findsOneWidget,
    );
    expect(
      find.text('Your loaded miniatures are still available.'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('miniatures-pagination-retry')),
    );
    await _pumpFrames(tester);

    expect(repository.requests.map((request) => request.offset), <int>[
      0,
      2,
      2,
    ]);
    expect(find.byType(MiniatureGameCard), findsNWidgets(4));
    expect(
      find.byKey(const ValueKey<String>('miniatures-pagination-error')),
      findsNothing,
    );
  });

  testWidgets('search is premium-gated, debounced, and sent to Gamebase', (
    tester,
  ) async {
    var premiumChecks = 0;
    final repository = _repositoryWith(<GamebaseMiniature>[
      _miniature('searchable'),
    ]);
    await _pumpScreen(
      tester,
      repository: repository,
      screen: MiniaturesScreen(
        onRequirePremiumFeature: () {
          premiumChecks += 1;
          return true;
        },
        onOpenMiniature: (_) {},
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('miniatures-search-control')),
    );
    await tester.pump();
    final editable = find.descendant(
      of: find.byKey(const ValueKey<String>('miniatures-search-control')),
      matching: find.byType(EditableText),
    );
    expect(editable, findsOneWidget);

    await tester.enterText(editable, 'Najdorf');
    await tester.pump(const Duration(milliseconds: 349));
    expect(repository.requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    await _pumpFrames(tester);

    expect(premiumChecks, 1);
    expect(repository.requests.last.filter.search, 'Najdorf');
    expect(repository.requests.last.offset, 0);
  });

  testWidgets('window controls are free and reset pagination', (tester) async {
    var premiumChecks = 0;
    final repository = _repositoryWith(<GamebaseMiniature>[
      _miniature('windowed'),
    ]);
    await _pumpScreen(
      tester,
      repository: repository,
      screen: MiniaturesScreen(
        onRequirePremiumFeature: () {
          premiumChecks += 1;
          return true;
        },
        onOpenMiniature: (_) {},
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('miniatures-window-today')),
    );
    await _pumpFrames(tester);

    expect(premiumChecks, 0);
    expect(repository.requests.last.filter.window, MiniatureGamesWindow.today);
    expect(repository.requests.last.offset, 0);
  });

  testWidgets('filter sheet applies typed sort, range, and player filters', (
    tester,
  ) async {
    var premiumChecks = 0;
    final repository = _repositoryWith(<GamebaseMiniature>[
      _miniature('filtered'),
    ]);
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(393, 1000),
      screen: MiniaturesScreen(
        onRequirePremiumFeature: () {
          premiumChecks += 1;
          return true;
        },
        onOpenMiniature: (_) {},
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('miniatures-filter-button')),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Filter miniatures'), findsOneWidget);

    final filterScroll = find.descendant(
      of: find.byKey(const ValueKey<String>('miniatures-filter-scroll')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    final ratingSort = find.widgetWithText(FilterChip, 'Rating');
    await tester.scrollUntilVisible(ratingSort, 180, scrollable: filterScroll);
    await tester.tap(ratingSort);
    final minRating = find.byKey(
      const ValueKey<String>('miniatures-min-rating'),
    );
    await tester.scrollUntilVisible(minRating, 220, scrollable: filterScroll);
    await tester.enterText(minRating, '2200');
    final playerField = find.byKey(
      const ValueKey<String>('miniatures-player-field'),
    );
    await tester.scrollUntilVisible(playerField, 260, scrollable: filterScroll);
    await tester.enterText(playerField, 'Carlsen');
    await tester.tap(
      find.byKey(const ValueKey<String>('miniatures-filter-apply')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await _pumpFrames(tester);

    expect(premiumChecks, 1);
    final applied = repository.requests.last.filter;
    expect(applied.sort, MiniatureGamesSort.rating);
    expect(applied.minRating, 2200);
    expect(applied.player, 'Carlsen');
    expect(repository.requests.last.offset, 0);
    expect(
      find.byKey(const ValueKey<String>('miniatures-filter-active-count')),
      findsOneWidget,
    );
  });

  testWidgets('phone stacks cards while tablet lays them out in columns', (
    tester,
  ) async {
    final items = <GamebaseMiniature>[
      _miniature('layout-1'),
      _miniature('layout-2'),
      _miniature('layout-3'),
      _miniature('layout-4'),
    ];
    final repository = _repositoryWith(items);
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(393, 1200),
    );

    final first = find.byKey(const ValueKey<String>('miniature-card-layout-1'));
    final second = find.byKey(
      const ValueKey<String>('miniature-card-layout-2'),
    );
    final phoneFirst = tester.getTopLeft(first);
    final phoneSecond = tester.getTopLeft(second);
    expect(phoneSecond.dy, greaterThan(phoneFirst.dy));
    expect(phoneSecond.dx, phoneFirst.dx);

    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(900, 1200),
    );
    final tabletFirst = tester.getTopLeft(first);
    final tabletSecond = tester.getTopLeft(second);
    expect(tabletSecond.dy, tabletFirst.dy);
    expect(tabletSecond.dx, greaterThan(tabletFirst.dx));
  });

  testWidgets('light and dark large-text layouts do not overflow', (
    tester,
  ) async {
    final repository = _repositoryWith(<GamebaseMiniature>[
      _miniature(
        'long-copy',
        event: 'A deliberately long international championship event title',
        opening:
            'A very long opening name that must remain readable on a narrow phone',
      ),
    ]);

    for (final theme in <ThemeData>[AppTheme.lightTheme, AppTheme.darkTheme]) {
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(320, 1200),
        theme: theme,
        textScaler: const TextScaler.linear(2),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(MiniatureGameCard), findsOneWidget);
    }
  });

  testWidgets('Reduce Motion removes the page state transition duration', (
    tester,
  ) async {
    final repository = _repositoryWith(<GamebaseMiniature>[
      _miniature('motion'),
    ]);
    await _pumpScreen(tester, repository: repository, disableAnimations: true);

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byKey(const ValueKey<String>('miniatures-state-switcher')),
    );
    expect(switcher.duration, Duration.zero);
  });

  testWidgets(
    'default open path refuses header-only PGN instead of faking moves',
    (tester) async {
      final item = _miniature('no-moves');
      final repository = _FakeGamebaseRepository(
        (_) => Future<GamebaseMiniaturesPage>.value(
          _page(<GamebaseMiniature>[item], total: 1),
        ),
        fullGame: GamebaseGameWithPgn(
          id: item.gameId,
          date: item.date!,
          result: GameResult.whiteWins,
          timeControl: TimeControl.rapid,
          pgn:
              '[Event "Tata Steel Masters"]\n[White "Alpha"]\n[Black "Beta"]\n[Result "1-0"]\n\n1-0',
        ),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(
        find.byKey(const ValueKey<String>('miniature-card-no-moves')),
      );
      await _pumpFrames(tester);

      expect(repository.fullGameRequests, <String>['no-moves']);
      expect(
        find.text(
          'This miniature has no complete move record, so it cannot be opened.',
        ),
        findsOneWidget,
      );
    },
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeGamebaseRepository repository,
  MiniaturesScreen screen = const MiniaturesScreen(),
  Size size = const Size(393, 900),
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      key: ValueKey<int>(identityHashCode(repository)),
      overrides: <Override>[
        gamebaseRepositoryProvider.overrideWithValue(repository),
      ],
      child: LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: textScaler,
                  disableAnimations: disableAnimations,
                ),
                child: screen,
              );
            },
          ),
        ),
      ),
    ),
  );
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

_FakeGamebaseRepository _repositoryWith(List<GamebaseMiniature> items) {
  return _FakeGamebaseRepository((request) {
    return Future<GamebaseMiniaturesPage>.value(
      _page(items, total: items.length, offset: request.offset),
    );
  });
}

GamebaseMiniaturesPage _page(
  List<GamebaseMiniature> items, {
  required int total,
  int offset = 0,
}) {
  return GamebaseMiniaturesPage(
    items: items,
    total: total,
    limit: 30,
    offset: offset,
  );
}

GamebaseMiniature _miniature(
  String id, {
  String event = 'Tata Steel Masters',
  String opening = 'Sicilian Defense',
}) {
  return GamebaseMiniature(
    gameId: id,
    avgRating: 2475,
    plyCount: 36,
    finalMoveNumber: 18,
    result: MiniatureGameResult.whiteWins,
    timeControl: MiniatureGameTimeControl.rapid,
    onlineStatus: MiniatureGameOnlineStatus.offline,
    date: DateTime.utc(2026, 7, 10),
    event: event,
    eco: 'B90',
    opening: opening,
    variation: 'Najdorf',
    whiteName: 'Alpha',
    blackName: 'Beta',
    whiteElo: 2500,
    blackElo: 2450,
    whitePlayerId: 'white-$id',
    blackPlayerId: 'black-$id',
    whiteFed: 'NOR',
    blackFed: 'USA',
  );
}
