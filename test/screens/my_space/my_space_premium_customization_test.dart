import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_game.dart';
import 'package:chessever2/screens/my_space/data/my_space_layout_repository.dart';
import 'package:chessever2/screens/my_space/domain/my_space_layout.dart';
import 'package:chessever2/screens/my_space/domain/my_space_shelf_state.dart';
import 'package:chessever2/screens/my_space/my_space_screen.dart';
import 'package:chessever2/screens/my_space/providers/my_space_content_providers.dart';
import 'package:chessever2/screens/my_space/providers/my_space_layout_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  testWidgets('disabled rollout is useful and makes no layout request', (
    tester,
  ) async {
    final backend = _LayoutBackend();

    await _pumpMySpace(tester, backend: backend, persistenceEnabled: false);

    expect(backend.fetchCalls, 0);
    expect(backend.saveCalls, 0);
    expect(find.text('Miniatures'), findsWidgets);
    expect(find.text('Study Discovery'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey<String>('my-space-add-shelf-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Saved customization is staged'),
      findsOneWidget,
    );
    expect(
      find.textContaining('makes no layout-network request'),
      findsOneWidget,
    );
    expect(backend.fetchCalls, 0);
    expect(backend.saveCalls, 0);
  });

  testWidgets('enabled catalog add saves through the revision-aware notifier', (
    tester,
  ) async {
    final initial = _layoutWithout(MySpaceShelfType.miniatures);
    final backend = _LayoutBackend(fetchRow: _storedRow(initial, revision: 4));

    await _pumpMySpace(
      tester,
      backend: backend,
      persistenceEnabled: true,
      subscribed: true,
    );

    await _tapCatalogAdd(tester, MySpaceShelfType.miniatures);

    expect(backend.fetchCalls, 1);
    expect(backend.saveCalls, 1);
    expect(backend.expectedRevisions, [4]);
    expect(_savedTypes(backend), contains('miniatures'));
    expect(find.text('Miniatures added.'), findsOneWidget);
  });

  for (final failureCase in <
    ({
      String name,
      MySpaceLayoutException failure,
      String visibleMessage,
      bool conflict,
    })
  >[
    (
      name: 'entitlement rejection',
      failure: const MySpaceLayoutException(
        kind: MySpaceLayoutFailureKind.premiumRequired,
        message: 'premium required',
      ),
      visibleMessage: 'The server did not confirm Premium',
      conflict: false,
    ),
    (
      name: 'revision conflict',
      failure: const MySpaceLayoutException(
        kind: MySpaceLayoutFailureKind.revisionConflict,
        message: 'conflict',
      ),
      visibleMessage: 'latest server layout was reloaded',
      conflict: true,
    ),
    (
      name: 'service unavailability',
      failure: const MySpaceLayoutException(
        kind: MySpaceLayoutFailureKind.unavailable,
        message: 'unavailable',
      ),
      visibleMessage: 'layout service is unavailable',
      conflict: false,
    ),
  ]) {
    testWidgets('${failureCase.name} never pretends the shelf was saved', (
      tester,
    ) async {
      final initial = _layoutWithout(MySpaceShelfType.miniatures);
      final initialRow = _storedRow(initial, revision: 2);
      final backend = _LayoutBackend(
        fetchRow: initialRow,
        saveFailure: failureCase.failure,
        conflictFetchRow: failureCase.conflict ? initialRow : null,
      );

      await _pumpMySpace(
        tester,
        backend: backend,
        persistenceEnabled: true,
        subscribed: true,
      );
      await _tapCatalogAdd(tester, MySpaceShelfType.miniatures);

      expect(backend.saveCalls, 1);
      expect(_savedTypes(backend), isNot(contains('miniatures')));
      expect(find.text('Miniatures added.'), findsNothing);
      expect(find.textContaining(failureCase.visibleMessage), findsWidgets);
    });
  }

  testWidgets('Study and Miniature cards preserve canonical open identities', (
    tester,
  ) async {
    final study = _study();
    final miniature = _miniature();
    GamebaseStudySummary? openedStudy;
    GamebaseMiniature? openedMiniature;

    await _pumpMySpace(
      tester,
      backend: _LayoutBackend(),
      persistenceEnabled: false,
      miniatureState: MySpaceShelfState<List<MySpaceContentItem>>.data([
        _miniatureItem(miniature),
      ]),
      studyState: MySpaceShelfState<List<MySpaceContentItem>>.data([
        _studyItem(study),
      ]),
      screen: MySpaceScreen(
        onOpenStudy: (value) => openedStudy = value,
        onOpenMiniature: (value) => openedMiniature = value,
      ),
    );

    final miniatureCard = find.byKey(
      ValueKey<String>('my-space-card-miniature:${miniature.canonicalGameId}'),
    );
    await _scrollFeedTo(tester, miniatureCard);
    await tester.tap(miniatureCard);
    await tester.pump();
    await _scrollFeedTo(
      tester,
      find.byKey(
        ValueKey<String>('my-space-card-study:${study.canonicalStudyId}'),
      ),
    );
    await tester.tap(
      find.byKey(
        ValueKey<String>('my-space-card-study:${study.canonicalStudyId}'),
      ),
    );
    await tester.pump();

    expect(openedMiniature?.canonicalGameId, 'game-42');
    expect(openedStudy?.canonicalStudyId, 'study-42');
    expect(
      openedStudy?.canonicalSourceUrl.toString(),
      'https://lichess.org/study/study-42',
    );
    expect(openedStudy?.canOpenMirroredChapterInApp, isFalse);
  });

  testWidgets('Miniature card refuses to invent a game when hydration fails', (
    tester,
  ) async {
    final miniature = _miniature();
    final repository = _NullGamebaseRepository();

    await _pumpMySpace(
      tester,
      backend: _LayoutBackend(),
      persistenceEnabled: false,
      gamebaseRepository: repository,
      miniatureState: MySpaceShelfState<List<MySpaceContentItem>>.data([
        _miniatureItem(miniature),
      ]),
    );

    final miniatureCard = find.byKey(
      ValueKey<String>('my-space-card-miniature:${miniature.canonicalGameId}'),
    );
    await _scrollFeedTo(tester, miniatureCard);
    await tester.tap(miniatureCard);
    await tester.pumpAndSettle();

    expect(repository.requestedIds, ['game-42']);
    expect(find.textContaining('complete game is unavailable'), findsOneWidget);
  });

  testWidgets(
    'enabled dark layout and catalog support large text on a small phone',
    (tester) async {
      final backend = _LayoutBackend(
        fetchRow: _storedRow(MySpaceLayout.curatedDefault, revision: 1),
      );

      await _pumpMySpace(
        tester,
        backend: backend,
        persistenceEnabled: true,
        subscribed: true,
        size: const Size(320, 1200),
        theme: AppTheme.darkTheme,
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('my-space-edit-layout-button')),
            )
            .shortestSide,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('my-space-add-shelf-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Build your own My Space'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _tapCatalogAdd(
  WidgetTester tester,
  MySpaceSupportedShelfType type,
) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('my-space-add-shelf-button')),
  );
  await tester.pumpAndSettle();
  final add = find.byKey(
    ValueKey<String>('my-space-catalog-add-${type.rawType}'),
  );
  await tester.scrollUntilVisible(
    add,
    180,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(add);
  await tester.pumpAndSettle();
}

Future<void> _scrollFeedTo(WidgetTester tester, Finder target) {
  return tester.scrollUntilVisible(
    target,
    260,
    scrollable:
        find
            .descendant(
              of: find.byKey(
                const PageStorageKey<String>('my-space-vertical-feed'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
  );
}

Future<void> _pumpMySpace(
  WidgetTester tester, {
  required _LayoutBackend backend,
  required bool persistenceEnabled,
  bool subscribed = false,
  GamebaseRepository? gamebaseRepository,
  MySpaceContentShelfState? studyState,
  MySpaceContentShelfState? miniatureState,
  MySpaceScreen screen = const MySpaceScreen(),
  Size size = const Size(393, 1100),
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  const empty = MySpaceShelfState<List<MySpaceContentItem>>.empty();
  final overrides = <Override>[
    mySpacePersistenceEnabledProvider.overrideWithValue(persistenceEnabled),
    mySpaceLayoutRepositoryProvider.overrideWithValue(
      MySpaceLayoutRepository(backend),
    ),
    mySpaceSubscriptionStateProvider.overrideWithValue(
      SubscriptionState(isSubscribed: subscribed),
    ),
    mySpaceContinueShelfProvider.overrideWithValue(empty),
    mySpaceLikesShelfProvider.overrideWithValue(empty),
    mySpaceSavedEventsShelfProvider.overrideWithValue(empty),
    mySpaceDatabasesShelfProvider.overrideWithValue(empty),
    mySpaceSavedStudiesShelfProvider.overrideWithValue(empty),
    mySpaceFavoritePlayersShelfProvider.overrideWithValue(empty),
    mySpaceStudyDiscoveryShelfProvider.overrideWithValue(studyState ?? empty),
    mySpaceMiniaturesShelfProvider.overrideWithValue(miniatureState ?? empty),
    if (gamebaseRepository != null)
      gamebaseRepositoryProvider.overrideWithValue(gamebaseRepository),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: true, textScaler: textScaler),
                child: screen,
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MySpaceLayout _layoutWithout(MySpaceShelfType type) {
  return MySpaceLayout(
    shelves: MySpaceLayout.curatedDefault.shelves.where(
      (shelf) => shelf.type != type,
    ),
  );
}

List<String> _savedTypes(_LayoutBackend backend) {
  final rows = backend.fetchRow?['shelves'];
  if (rows is! List) return const [];
  return rows
      .whereType<Map>()
      .map((row) => row['type'])
      .whereType<String>()
      .toList(growable: false);
}

Map<String, dynamic> _storedRow(MySpaceLayout layout, {required int revision}) {
  return {
    'user_id': 'user-1',
    'schema_version': layout.schemaVersion,
    'revision': revision,
    'shelves': layout.toJson()['shelves'],
    'created_at': '2026-07-10T08:00:00.000Z',
    'updated_at': '2026-07-10T09:00:00.000Z',
  };
}

final class _LayoutBackend implements MySpaceLayoutBackend {
  _LayoutBackend({this.fetchRow, this.saveFailure, this.conflictFetchRow});

  Map<String, dynamic>? fetchRow;
  final Object? saveFailure;
  final Map<String, dynamic>? conflictFetchRow;
  int fetchCalls = 0;
  int saveCalls = 0;
  final List<int> expectedRevisions = [];

  @override
  Future<Map<String, dynamic>?> fetchCurrentUserLayout() async {
    fetchCalls += 1;
    if (fetchCalls > 1 && conflictFetchRow != null) return conflictFetchRow;
    return fetchRow;
  }

  @override
  Future<Map<String, dynamic>> saveCurrentUserLayout({
    required Map<String, dynamic> layout,
    required int expectedRevision,
  }) async {
    saveCalls += 1;
    expectedRevisions.add(expectedRevision);
    final failure = saveFailure;
    if (failure != null) throw failure;
    fetchRow = {
      'user_id': 'user-1',
      'schema_version': layout['schema_version'],
      'revision': expectedRevision + 1,
      'shelves': layout['shelves'],
      'created_at': '2026-07-10T08:00:00.000Z',
      'updated_at': '2026-07-10T09:00:00.000Z',
    };
    return fetchRow!;
  }
}

final class _NullGamebaseRepository extends GamebaseRepository {
  _NullGamebaseRepository() : super(Dio(), apiKey: 'test-key');

  final List<String> requestedIds = [];

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async {
    requestedIds.add(id);
    return null;
  }
}

GamebaseStudySummary _study() {
  final now = DateTime.utc(2026, 7, 10);
  return GamebaseStudySummary(
    lichessStudyId: 'study-42',
    authorUsername: 'quality-author',
    name: 'Practical rook endings',
    views: 4200,
    lichessCreatedAt: now.subtract(const Duration(days: 30)),
    lichessUpdatedAt: now,
    chapterCount: 8,
    plyTotal: 640,
    hasAnnotations: true,
    ecos: const ['C65'],
    ecoCategories: const ['C'],
    openings: const ['Ruy Lopez'],
    variants: const ['standard'],
    chapterModes: const ['normal'],
    players: const ['Capablanca'],
    isGamebook: false,
    hasCustomPositions: false,
    credibilityScore: 0.96,
    passedGate: true,
    status: GamebaseStudyStatus.active,
    syncedAt: now,
  );
}

MySpaceStudyItem _studyItem(GamebaseStudySummary study) {
  return MySpaceStudyItem(
    id: 'study:${study.canonicalStudyId}',
    title: study.name,
    subtitle: 'Ruy Lopez',
    status: '8 chapters · 4200 views',
    actionLabel: 'View Study',
    study: study,
  );
}

GamebaseMiniature _miniature() {
  return GamebaseMiniature(
    gameId: 'game-42',
    avgRating: 2450,
    plyCount: 34,
    finalMoveNumber: 17,
    result: MiniatureGameResult.whiteWins,
    timeControl: MiniatureGameTimeControl.rapid,
    onlineStatus: MiniatureGameOnlineStatus.offline,
    date: DateTime.utc(2026, 7, 9),
    event: 'Tactical Masters',
    eco: 'B12',
    opening: 'Caro-Kann Defense',
    whiteName: 'Alpha',
    blackName: 'Beta',
  );
}

MySpaceMiniatureItem _miniatureItem(GamebaseMiniature miniature) {
  return MySpaceMiniatureItem(
    id: 'miniature:${miniature.canonicalGameId}',
    title: 'Alpha vs Beta',
    subtitle: 'Caro-Kann Defense',
    status: '17 moves · Rapid',
    actionLabel: 'Open game',
    miniature: miniature,
  );
}
