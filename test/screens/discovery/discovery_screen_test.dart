import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/discovery/discovery_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class _DiscoveryRepository extends GamebaseRepository {
  _DiscoveryRepository({
    this.studyFailure,
    this.miniatureFailure,
    List<GamebaseStudySummary>? studies,
    List<GamebaseMiniature>? miniatures,
  }) : studies = studies ?? <GamebaseStudySummary>[_study()],
       miniatures = miniatures ?? <GamebaseMiniature>[_miniature()],
       super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final Object? studyFailure;
  final Object? miniatureFailure;
  final List<GamebaseStudySummary> studies;
  final List<GamebaseMiniature> miniatures;
  int studyRequests = 0;
  int miniatureRequests = 0;

  @override
  Future<GamebaseStudiesPage> getStudies({
    GamebaseStudiesFilter filter = GamebaseStudiesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    studyRequests += 1;
    if (studyFailure case final failure?) throw failure;
    return GamebaseStudiesPage(
      items: studies,
      total: studies.length,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<GamebaseMiniaturesPage> getMiniatures({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    miniatureRequests += 1;
    if (miniatureFailure case final failure?) throw failure;
    return GamebaseMiniaturesPage(
      items: miniatures,
      total: miniatures.length,
      limit: limit,
      offset: offset,
    );
  }
}

void main() {
  testWidgets(
    'composes Studies and Miniatures on one full-screen accessible canvas',
    (tester) async {
      final repository = _DiscoveryRepository();
      GamebaseStudySummary? openedStudy;
      GamebaseMiniature? openedMiniature;
      var openedStudies = 0;
      var openedMiniatures = 0;
      final semantics = tester.ensureSemantics();

      await _pumpDiscovery(
        tester,
        repository: repository,
        screen: DiscoveryScreen(
          onOpenStudy: (study) => openedStudy = study,
          onOpenMiniature: (miniature) => openedMiniature = miniature,
          onOpenStudies: () => openedStudies += 1,
          onOpenMiniatures: () => openedMiniatures += 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('discovery-full-screen-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('discovery-floating-controls')),
        findsOneWidget,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SliverAppBar), findsNothing);
      expect(find.byType(SliverPersistentHeader), findsNothing);
      expect(find.text('Studies worth your time'), findsOneWidget);
      expect(find.text('Annotated Sicilian Model Games'), findsOneWidget);
      expect(find.text('Alpha — Beta'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'Study, Annotated Sicilian Model Games.*Open Study details'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Miniature game, Alpha versus Beta.*Open Miniatures'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('discovery-account-button')),
            )
            .shortestSide,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('discovery-refresh-button')),
            )
            .shortestSide,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('discovery-hero-studies')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('discovery-hero-miniatures')),
      );
      await tester.pump();
      expect(openedStudies, 1);
      expect(openedMiniatures, 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('discovery-study-AbCd1234')),
      );
      await tester.pump();
      expect(openedStudy?.canonicalStudyId, 'AbCd1234');

      final miniatureCard = find.byKey(
        const ValueKey<String>('discovery-miniature-game-1'),
      );
      await tester.ensureVisible(miniatureCard);
      await tester.pump();
      await tester.tap(miniatureCard);
      await tester.pump();
      expect(openedMiniature?.canonicalGameId, 'game-1');
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('keeps shelf failures independent and preserves honest content', (
    tester,
  ) async {
    final repository = _DiscoveryRepository(
      studyFailure: StateError('studies unavailable'),
    );

    await _pumpDiscovery(tester, repository: repository);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('discovery-studies-error')),
      findsOneWidget,
    );
    expect(find.text('Study previews could not load.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('discovery-miniatures-data')),
      findsOneWidget,
    );
    expect(find.text('Alpha — Beta'), findsOneWidget);
    expect(find.textContaining('placeholder'), findsNothing);
  });

  testWidgets('a Miniatures failure does not hide quality Study previews', (
    tester,
  ) async {
    final repository = _DiscoveryRepository(
      miniatureFailure: StateError('miniatures unavailable'),
    );

    await _pumpDiscovery(tester, repository: repository);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('discovery-miniatures-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('discovery-studies-data')),
      findsOneWidget,
    );
    expect(find.text('Annotated Sicilian Model Games'), findsOneWidget);
  });

  for (final entry in <(String, ThemeData)>[
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('supports ${entry.$1} mode, large text, and reduced motion', (
      tester,
    ) async {
      final repository = _DiscoveryRepository();
      await _pumpDiscovery(
        tester,
        repository: repository,
        theme: entry.$2,
        textScaler: const TextScaler.linear(1.45),
        size: const Size(320, 1000),
        disableAnimations: true,
      );
      await tester.pumpAndSettle();

      final heroButtons = tester.widgetList<FilledButton>(
        find.byType(FilledButton),
      );
      expect(heroButtons, isNotEmpty);
      expect(
        heroButtons.any(
          (button) => button.style?.animationDuration == Duration.zero,
        ),
        isTrue,
      );
      expect(find.text('Short games. Deep ideas.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('refreshes both content contracts without coupling their state', (
    tester,
  ) async {
    final repository = _DiscoveryRepository();
    await _pumpDiscovery(tester, repository: repository);
    await tester.pumpAndSettle();

    expect(repository.studyRequests, 1);
    expect(repository.miniatureRequests, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('discovery-refresh-button')),
    );
    await tester.pumpAndSettle();

    expect(repository.studyRequests, 2);
    expect(repository.miniatureRequests, 2);
    expect(find.text('Annotated Sicilian Model Games'), findsOneWidget);
    expect(find.text('Alpha — Beta'), findsOneWidget);
  });

  testWidgets('tool cards remain immediate and meet the 48 point contract', (
    tester,
  ) async {
    var explorer = 0;
    var board = 0;
    var players = 0;
    await _pumpDiscovery(
      tester,
      repository: _DiscoveryRepository(),
      size: const Size(393, 1200),
      screen: DiscoveryScreen(
        onOpenExplorer: () => explorer += 1,
        onOpenAnalysisBoard: () => board += 1,
        onOpenPlayers: () => players += 1,
      ),
    );
    await tester.pumpAndSettle();

    final scrollable =
        find
            .descendant(
              of: find.byKey(
                const PageStorageKey<String>('discovery-scroll-view'),
              ),
              matching: find.byType(Scrollable),
            )
            .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('discovery-tool-opening-explorer')),
      300,
      scrollable: scrollable,
    );

    for (final key in <String>[
      'discovery-tool-opening-explorer',
      'discovery-tool-analysis-board',
      'discovery-tool-players',
    ]) {
      final finder = find.byKey(ValueKey<String>(key));
      expect(finder, findsOneWidget);
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
      await tester.tap(finder);
      await tester.pump();
    }

    expect(explorer, 1);
    expect(board, 1);
    expect(players, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDiscovery(
  WidgetTester tester, {
  required GamebaseRepository repository,
  ThemeData? theme,
  DiscoveryScreen screen = const DiscoveryScreen(),
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(393, 1000),
  bool disableAnimations = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
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
  await tester.pump();
}

GamebaseStudySummary _study() {
  return GamebaseStudySummary(
    lichessStudyId: 'AbCd1234',
    authorUsername: 'example_author',
    name: 'Annotated Sicilian Model Games',
    views: 840,
    lichessCreatedAt: DateTime.utc(2026, 1, 15),
    lichessUpdatedAt: DateTime.utc(2026, 7, 1),
    chapterCount: 2,
    plyTotal: 112,
    hasAnnotations: true,
    ecos: const <String>['B90', 'B91'],
    ecoCategories: const <String>['B'],
    openings: const <String>['Sicilian Defense'],
    variants: const <String>['Standard'],
    chapterModes: const <String>['normal', 'gamebook'],
    players: const <String>['Example White', 'Example Black'],
    isGamebook: true,
    hasCustomPositions: false,
    credibilityScore: 76.4,
    passedGate: true,
    status: GamebaseStudyStatus.active,
    syncedAt: DateTime.utc(2026, 7, 10),
  );
}

GamebaseMiniature _miniature() {
  return GamebaseMiniature(
    gameId: 'game-1',
    avgRating: 2475,
    plyCount: 36,
    finalMoveNumber: 18,
    result: MiniatureGameResult.whiteWins,
    timeControl: MiniatureGameTimeControl.rapid,
    onlineStatus: MiniatureGameOnlineStatus.offline,
    date: DateTime.utc(2026, 7, 10),
    event: 'Tata Steel Masters',
    eco: 'B90',
    opening: 'Sicilian Defense',
    variation: 'Najdorf',
    whiteName: 'Alpha',
    blackName: 'Beta',
    whiteElo: 2500,
    blackElo: 2450,
    whitePlayerId: 'white-game-1',
    blackPlayerId: 'black-game-1',
    whiteFed: 'NOR',
    blackFed: 'USA',
  );
}
