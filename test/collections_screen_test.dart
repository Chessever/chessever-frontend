import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/collections/collection_explore.dart';
import 'package:chessever2/screens/collections/opening_event_card.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The collection screen's Games tab: games under the section tree's
/// headers (a round and its date; a book's parts, chapters and intros).

class _FakeCollections extends CollectionsRepository {
  _FakeCollections({
    required this.detail,
    required this.games,
    this.openings = const [],
    this.publishedLoader,
  }) : super(GamebaseRepository(Dio(), apiKey: 'test'));

  final Collection detail;
  final List<CollectionGame> games;
  final List<CollectionOpening> openings;
  final Future<PublishedGamesBatch> Function(int offset)? publishedLoader;
  @override
  Future<List<String>> fetchAuthors() async => ['Bobby Fischer'];

  final List<String> scopedCalls = [];
  final List<int> publishedOffsets = [];
  final List<CollectionSearchQuery> searchQueries = [];

  @override
  Future<CollectionsPage> searchBooks(
    CollectionSearchQuery query,
    int offset,
  ) async =>
      CollectionsPage(items: [detail], total: 1, limit: 40, offset: offset);
  @override
  Future<CollectionOpeningsPage> searchOpenings(
    CollectionSearchQuery query,
    int offset,
  ) async => CollectionOpeningsPage(
    items: openings,
    total: openings.length,
    limit: 40,
    offset: offset,
  );
  @override
  Future<List<Collection>> fetchCollections() async => [detail];

  @override
  Future<PublishedGamesBatch> fetchPublishedGames({
    int offset = 0,
    CollectionSearchQuery search = const CollectionSearchQuery(),
  }) async {
    searchQueries.add(search);
    publishedOffsets.add(offset);
    if (publishedLoader != null) return publishedLoader!(offset);
    return PublishedGamesBatch(
      games: games,
      total: games.length,
      nextOffset: games.length,
      hasMore: false,
    );
  }

  @override
  Future<List<CollectionOpening>> fetchOpenings({String? slug}) async =>
      openings;

  @override
  Future<List<CollectionGame>> fetchGamesForOpening(
    String slug,
    String eco,
  ) async {
    scopedCalls.add('$slug:$eco');
    return games.take(1).toList();
  }

  @override
  Future<List<Collection>> fetchBooksForOpening(String eco) async => [detail];

  @override
  Future<Collection> fetchCollection(String slug) async => detail;

  @override
  Future<List<CollectionGame>> fetchGames(String slug) async => games;

  @override
  Future<List<CollectionPlayer>> fetchPlayers(String slug) async => const [];
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _EngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

CloudEval _eval(String fen) => CloudEval(
  fen: fen,
  knodes: 0,
  depth: 20,
  pvs: [Pv(moves: 'e2e4', cp: 40)],
  requestedMultiPv: 1,
);

const _pgn = '''[Event "Casual"]
[White "Nimzowitsch, Aron"]
[Black "Systemsson, Max"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 1-0''';

CollectionGame _game(String id, {String? sectionId, int orderIndex = 0}) {
  return CollectionGame.fromCard(
    CollectionGameCard(
      id: id,
      sectionId: sectionId,
      orderIndex: orderIndex,
      white: const CollectionPlayerSide(
        name: 'Nimzowitsch, Aron',
        key: 'name:nimzowitsch, aron',
      ),
      black: const CollectionPlayerSide(
        name: 'Systemsson, Max',
        key: 'name:systemsson, max',
      ),
      pgn: _pgn,
    ),
  )!;
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

Future<void> _pump(
  WidgetTester tester,
  _FakeCollections repo, {
  GamesListViewMode viewMode = GamesListViewMode.gamesCard,
  Size size = const Size(390, 4000),
  bool light = false,
  double textScale = 1,
  Widget? home,
  CollectionsRepository Function()? repositoryFactory,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(null),
      collectionsRepositoryProvider.overrideWith(
        (_) => repositoryFactory?.call() ?? repo,
      ),
      subscriptionProvider.overrideWith((ref) => _Subscription()),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      gamesListViewModeProvider.overrideWithValue(viewMode),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
      ),
      gameCardEvalWithStockfishFallbackProvider.overrideWith(
        (ref, fen) async => _eval(fen),
      ),
      gameCardEvalCacheOnlyProvider.overrideWith(
        (ref, fen) async => _eval(fen),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return home ?? CollectionScreen(collection: repo.detail);
          },
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Game cards leave short timers behind; take the tree down and let them run.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Finder _rich(String text) => find.textContaining(text, findRichText: true);

void main() {
  testWidgets(
    'the shared search field debounces, carries filters across tabs and clears',
    (tester) async {
      final repo = _FakeCollections(
        detail: const Collection(
          id: 'book',
          slug: 'book',
          kind: CollectionKind.book,
          title: 'Book',
        ),
        games: const [],
      );
      await _pump(
        tester,
        repo,
        size: const Size(393, 852),
        home: const CollectionsScreen(embedded: true),
      );
      await tester.tap(find.text('Games'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.searchQueries.last.parameters, isEmpty);
      await tester.tap(find.byKey(const ValueKey('collections_filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close filters'));
      await tester.pumpAndSettle();
      expect(repo.searchQueries.last.parameters, isEmpty);
      final field = find.byKey(const ValueKey('collections_search'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Games'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(repo.searchQueries.last.text, 'Carlsen');
      await tester.tap(find.byKey(const ValueKey('collections_filters')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('eco-dropdown-header')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.descendant(
          of: find.byType(EcoFilterDropdown),
          matching: find.byType(TextField),
        ),
        'B20',
      );
      await tester.pump();
      final opening = find
          .byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label?.endsWith(', ECO B20') ?? false),
          )
          .first;
      await tester.ensureVisible(opening);
      await tester.pump();
      await tester.tap(opening);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.tap(find.text('Apply filters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(repo.searchQueries.last.eco, 'B20');
      expect(repo.searchQueries.last.text, 'Carlsen');
      await tester.enterText(field, '');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(repo.searchQueries.last.text, '');
      expect(repo.searchQueries.last.eco, 'B20');
      await _teardown(tester);
    },
  );

  for (final (size, textScale) in [
    (const Size(393, 852), 1.0),
    (const Size(360, 780), 1.4),
    (const Size(360, 780), 2.0),
  ]) {
    testWidgets('embedded Collections keeps home header geometry at '
        '${size.width.toInt()}dp and ${textScale}x text', (tester) async {
      final repo = _FakeCollections(
        detail: const Collection(
          id: 'header-book',
          slug: 'header-book',
          kind: CollectionKind.book,
          title: 'Header book',
          contentLocked: false,
        ),
        games: const [],
      );
      await _pump(
        tester,
        repo,
        size: size,
        textScale: textScale,
        home: const Scaffold(
          drawer: Drawer(child: Text('Sidebar')),
          body: CollectionsScreen(embedded: true),
        ),
      );

      expect(find.byType(HomeTopBarFrame), findsOneWidget);
      expect(find.byType(HomeTopBarAvatar), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);

      final context = tester.element(find.byType(HomeTopBarFrame));
      final row = tester.getRect(find.byType(HomeTopBarRow));
      final segments = tester.getRect(find.byType(SegmentedSwitcher));
      final pages = tester.getRect(find.byType(PageView));
      expect(row.top, closeTo(HomeTopBarMetrics.topInset(context), 0.5));
      expect(segments.top - row.bottom, closeTo(16.h, 0.5));
      expect(pages.top - segments.bottom, closeTo(12.h, 0.5));
      final label = tester.getRect(find.text('Openings'));
      expect(label.top, greaterThanOrEqualTo(segments.top));
      expect(label.bottom, lessThanOrEqualTo(segments.bottom));
      expect(tester.takeException(), isNull);

      await tester.tap(find.bySemanticsLabel('Open sidebar'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sidebar'), findsOneWidget);
      await _teardown(tester);
    });
  }

  testWidgets('a large book mounts visible rows instead of a whole chapter', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeCollections(
        detail: const Collection(
          id: 'long-book',
          slug: 'long-book',
          kind: CollectionKind.book,
          title: 'Collected games',
          contentLocked: false,
        ),
        games: [for (var i = 0; i < 200; i++) _game('game-$i')],
      ),
      size: const Size(390, 844),
    );
    final mounted = find.byType(GameCard).evaluate().length;
    expect(mounted, greaterThan(0));
    expect(mounted, lessThan(20));
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(GameCard), findsWidgets);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  for (final kind in CollectionKind.values) {
    for (final light in [false, true]) {
      testWidgets('${kind.name} uses tournament list, grid and board cards in '
          '${light ? 'light' : 'dark'} mode', (tester) async {
        await _pump(
          tester,
          _FakeCollections(
            detail: Collection(
              id: 'book',
              slug: 'book',
              kind: kind,
              title: 'Advanced',
              contentLocked: false,
            ),
            games: [_game('a'), _game('b')],
          ),
          viewMode: GamesListViewMode.chessBoardGrid,
          light: light,
          textScale: 1.3,
        );
        expect(find.byType(GameCard), findsNWidgets(2));
        expect(find.byType(GridChessBoardFromFENNew), findsNothing);

        await tester.tap(find.byTooltip('Change games view'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(GameCard), findsNothing);
        expect(find.byType(GridChessBoardFromFENNew), findsNWidgets(2));

        await tester.tap(find.byTooltip('Change games view'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(GridChessBoardFromFENNew), findsNothing);
        expect(find.byType(ChessBoardFromFENNew), findsNWidgets(2));

        await tester.tap(find.byTooltip('Change games view'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(GameCard), findsNWidgets(2));
        final container = ProviderScope.containerOf(
          tester.element(find.byType(CollectionScreen)),
        );
        expect(
          container.read(gamesListViewModeProvider),
          GamesListViewMode.chessBoardGrid,
          reason: 'A collection view change keeps other screens\' preference.',
        );
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    }
  }

  test('analysis metadata preserves kind, credit and biographies', () {
    final collection = Collection.fromJson({
      'id': 'analysis',
      'kind': 'analysis',
      'title': 'Endgame notes',
      'author': 'Test Author',
      'annotator': 'Test Annotator',
      'authorBio': 'Author biography supplied by the editor.',
      'annotatorBio': 'Annotator biography supplied by the editor.',
    });
    expect(collection.kind, CollectionKind.analysis);
    expect(collection.kind.apiValue, 'analysis');
    expect(collection.authorBio, 'Author biography supplied by the editor.');
    expect(
      collection.annotatorBio,
      'Annotator biography supplied by the editor.',
    );
    expect(collection.access, CollectionAccess.free);
    expect(
      collectionContentsSummary(collection),
      'Selected game analysis from Endgame notes.',
    );
  });

  testWidgets(
    'analysis keeps editorial credits in About with an Openings tab',
    (tester) async {
      const collection = Collection(
        id: 'analysis',
        slug: 'analysis',
        kind: CollectionKind.analysis,
        title: 'Endgame notes',
        author: 'Test Author',
        authorBio: 'An editorial biography.',
        annotator: 'Test Annotator',
        annotatorBio: 'An editorial annotator biography.',
      );
      await _pump(
        tester,
        _FakeCollections(detail: collection, games: const []),
      );
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Games'), findsOneWidget);
      expect(find.text('Openings'), findsOneWidget);
      await tester.tap(find.text('About'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('by Test Author'), findsOneWidget);
      expect(find.text('Annotated by Test Annotator'), findsOneWidget);
      expect(find.text('An editorial biography.'), findsOneWidget);
      expect(find.text('An editorial annotator biography.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    },
  );

  testWidgets(
    'primary Collections has Openings Games Books and re-tap returns its active list to the top',
    (tester) async {
      const book = Collection(
        id: 'study',
        slug: 'study',
        kind: CollectionKind.book,
        title: 'Opening studies',
        access: CollectionAccess.free,
      );
      final repo = _FakeCollections(
        detail: book,
        games: [_game('one')],
        openings: [
          for (var i = 0; i < 25; i++)
            CollectionOpening(
              eco: 'A${i.toString().padLeft(2, '0')}',
              name: 'Opening $i',
              gameCount: i + 1,
              bookCount: 1,
            ),
        ],
      );
      await _pump(
        tester,
        repo,
        size: const Size(390, 844),
        home: const CollectionsScreen(embedded: true),
      );
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.text('Openings'), findsOneWidget);
      expect(find.text('Games'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
      final list = find.descendant(
        of: find.byType(CollectionOpeningsView),
        matching: find.byType(ListView),
      );
      await tester.drag(list, const Offset(0, -600));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      expect(scroll.pixels, greaterThan(200));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CollectionsScreen)),
      );
      container
          .read(bottomNavBarReTapRequestProvider.notifier)
          .request(BottomNavBarItem.collections);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(scroll.pixels, closeTo(0, 0.5));
      await tester.tap(find.text('Games'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byType(DiscoveryGameList), findsOneWidget);
      await tester.tap(find.text('Books'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byType(CollectionCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    },
  );

  testWidgets(
    'publication changes replace the open games feed and ignore an old pending page',
    (tester) async {
      const book = Collection(
        id: 'study',
        slug: 'study',
        kind: CollectionKind.book,
        title: 'Opening studies',
        access: CollectionAccess.free,
      );
      final latePage = Completer<PublishedGamesBatch>();
      final original = _FakeCollections(
        detail: book,
        games: const [],
        publishedLoader: (offset) async {
          if (offset > 0) return latePage.future;
          return PublishedGamesBatch(
            games: [_game('old')],
            total: 2,
            nextOffset: 1,
            hasMore: true,
          );
        },
      );
      final replacement = _FakeCollections(
        detail: book,
        games: [_game('updated')],
      );
      CollectionsRepository current = original;
      await _pump(
        tester,
        original,
        repositoryFactory: () => current,
        home: const Scaffold(body: PublishedCollectionGamesView()),
      );
      List<String> shownIds() => tester
          .widgetList<DiscoveryGameList>(find.byType(DiscoveryGameList))
          .expand((list) => list.games)
          .map((game) => game.gameId)
          .toList();
      expect(shownIds(), ['old']);
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pump();
      expect(original.publishedOffsets, [0, 1]);

      // Save, unpublish and source deletion all invalidate this provider.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PublishedCollectionGamesView)),
      );
      current = replacement;
      container.invalidate(collectionsRepositoryProvider);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(replacement.publishedOffsets, [0]);
      expect(shownIds(), ['updated']);

      latePage.complete(
        PublishedGamesBatch(
          games: [_game('stale')],
          total: 2,
          nextOffset: 2,
          hasMore: false,
        ),
      );
      await tester.pump();
      expect(shownIds(), ['updated']);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    },
  );

  testWidgets(
    'book opening selection requests games scoped to the book and ECO',
    (tester) async {
      const book = Collection(
        id: 'study',
        slug: 'study',
        kind: CollectionKind.book,
        title: 'Sicilian studies',
        access: CollectionAccess.free,
        gameCount: 2,
      );
      const opening = CollectionOpening(
        eco: 'B20',
        name: 'Sicilian Defence',
        gameCount: 1,
        bookCount: 1,
      );
      final repo = _FakeCollections(
        detail: book,
        games: [_game('one'), _game('two')],
        openings: [opening],
      );
      await _pump(tester, repo);
      await tester.tap(find.text('Openings'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byType(OpeningEventCard), findsOneWidget);
      expect(find.text('1 game'), findsOneWidget);
      final board = tester.widget<GameCardChessboard>(
        find.descendant(
          of: find.byType(OpeningEventCard),
          matching: find.byType(GameCardChessboard),
        ),
      );
      expect(board.fen, contains('2p5'));
      await tester.tap(find.byType(OpeningEventCard));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(repo.scopedCalls, ['study:B20']);
      expect(find.text('B20 · Sicilian Defence'), findsOneWidget);
      final shown = tester.widget<DiscoveryGameList>(
        find.byType(DiscoveryGameList),
      );
      expect(shown.games.map((game) => game.gameId), ['one']);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    },
  );

  testWidgets(
    'an opening lists related books with its matching count and preserves scope on open',
    (tester) async {
      const opening = CollectionOpening(
        eco: 'C60',
        name: 'Ruy Lopez',
        gameCount: 3,
        bookCount: 1,
      );
      const book = Collection(
        id: 'study',
        slug: 'study',
        kind: CollectionKind.book,
        title: 'Spanish studies',
        access: CollectionAccess.free,
        gameCount: 20,
        matchedGameCount: 3,
      );
      final repo = _FakeCollections(detail: book, games: [_game('one')]);
      await _pump(
        tester,
        repo,
        home: const OpeningBooksScreen(opening: opening),
      );
      expect(find.text('3 games · C60'), findsOneWidget);
      await tester.tap(find.byType(CollectionCard));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(repo.scopedCalls, ['study:C60']);
      expect(find.text('C60 · Ruy Lopez'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    },
  );

  testWidgets('holding a collection card offers Open and Add to My Space, '
      'with the collection itself as the draft', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const collection = Collection(
      id: 'c9',
      slug: 'zurich-1953',
      kind: CollectionKind.book,
      title: 'Zurich 1953',
      gameCount: 210,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [spaceShortcutsProvider.overrideWith(_NoShortcuts.new)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: CollectionCard(collection: collection),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final draft = collectionSpaceDraft(collection);
    expect(draft.kind, SpaceShortcutKind.collection);
    expect(draft.targetId, 'c9');
    expect(draft.section, SpaceSection.library);

    await tester.longPress(find.byType(CollectionCard));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Add to My Space'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an event lists its games under dated rounds, in order', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeCollections(
        detail: Collection(
          id: 'c1',
          slug: 'us-championship-2025',
          kind: CollectionKind.event,
          title: 'US Championship 2025',
          gameCount: 3,
          sections: [
            CollectionSection(
              id: 'r1',
              kind: CollectionSectionKind.round,
              label: 'Round 1',
              startsOn: DateTime(2025, 10, 2),
              orderIndex: 1,
            ),
            const CollectionSection(
              id: 'r2',
              kind: CollectionSectionKind.round,
              label: 'Round 2',
              orderIndex: 2,
            ),
          ],
        ),
        games: [
          _game('a', sectionId: 'r1'),
          _game('b', sectionId: 'r2'),
          _game('u'),
        ],
      ),
    );

    expect(find.text('Round 1'), findsOneWidget);
    expect(find.text('Oct 2, 2025'), findsOneWidget);
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text('Other games'), findsOneWidget);
    final y = [
      for (final t in ['Round 1', 'Round 2', 'Other games'])
        tester.getTopLeft(find.text(t)).dy,
    ];
    expect(y, orderedEquals([...y]..sort()));
    await _teardown(tester);
  });

  testWidgets('a book shows parts, numbered chapters and their intros', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeCollections(
        detail: const Collection(
          id: 'c2',
          slug: 'my-system',
          kind: CollectionKind.book,
          title: 'My System',
          gameCount: 2,
          // The server's verdict: this viewer reads the book.
          contentLocked: false,
          sections: [
            CollectionSection(
              id: 'p1',
              kind: CollectionSectionKind.part,
              label: 'Part I',
              number: 'I',
              title: 'The Elements',
              orderIndex: 1,
              children: [
                CollectionSection(
                  id: 'ch7',
                  parentId: 'p1',
                  kind: CollectionSectionKind.chapter,
                  label: 'Chapter 7',
                  number: '7',
                  title: 'The Pin',
                  intro: 'A pinned piece cannot move.\n\nExploit it.',
                  orderIndex: 1,
                ),
              ],
            ),
            CollectionSection(
              id: 'empty',
              kind: CollectionSectionKind.chapter,
              label: 'Chapter 8',
              title: 'Nothing here yet',
              orderIndex: 2,
            ),
          ],
        ),
        games: [
          _game('a', sectionId: 'ch7'),
          _game('b', sectionId: 'ch7'),
        ],
      ),
    );

    expect(_rich('The Elements'), findsOneWidget);
    expect(_rich('Part I'), findsOneWidget);
    expect(_rich('7  The Pin'), findsOneWidget);
    expect(find.text('A pinned piece cannot move.'), findsOneWidget);
    expect(find.text('Exploit it.'), findsOneWidget);
    expect(_rich('Nothing here yet'), findsNothing);
    expect(find.text('Other games'), findsNothing);
    await _teardown(tester);
  });

  testWidgets('a collection without sections lists games with no headers', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeCollections(
        detail: const Collection(
          id: 'c3',
          slug: 'flat',
          kind: CollectionKind.event,
          title: 'Flat',
        ),
        games: [_game('a'), _game('b')],
      ),
    );
    expect(find.text('Other games'), findsNothing);
    await _teardown(tester);
  });
}
