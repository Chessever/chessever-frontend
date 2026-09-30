import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/screens/collections/collection_catalog_list.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
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
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
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
    this.players = const [],
    this.list,
    this.publishedLoader,
  }) : super(GamebaseRepository(Dio(), apiKey: 'test'));

  final Collection detail;
  final List<CollectionGame> games;
  final List<CollectionOpening> openings;
  final List<CollectionPlayer> players;
  final List<Collection>? list;
  final Future<PublishedGamesBatch> Function(int offset)? publishedLoader;
  @override
  Future<List<String>> fetchAuthors() async => ['Bobby Fischer'];

  final List<String> scopedCalls = [];
  final List<int> publishedOffsets = [];
  final List<CollectionSearchQuery> searchQueries = [];
  final List<CollectionSearchQuery> bookQueries = [];

  @override
  Future<CollectionsPage> searchBooks(
    CollectionSearchQuery query,
    int offset,
  ) async {
    bookQueries.add(query);
    return CollectionsPage(
      items: (list ?? [detail])
          .where(
            (c) =>
                query.text.isEmpty ||
                '${c.title} ${c.author ?? ''}'.toLowerCase().contains(
                  query.text.toLowerCase(),
                ),
          )
          .toList(),
      total: (list ?? [detail]).length,
      limit: 40,
      offset: offset,
    );
  }

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
  Future<List<Collection>> fetchCollections() async => list ?? [detail];

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

  final openingSlugs = <String?>[];
  @override
  Future<List<CollectionOpening>> fetchOpenings({String? slug}) async {
    openingSlugs.add(slug);
    return openings;
  }

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

  final filteredQueries = <({CollectionSearchQuery query, String? player})>[];
  final filteredSlugs = <String>[];
  @override
  Future<List<CollectionGame>> searchGames(
    String slug,
    CollectionSearchQuery search, {
    String? playerKey,
  }) async {
    filteredQueries.add((query: search, player: playerKey));
    filteredSlugs.add(slug);
    return games
        .where(
          (g) =>
              (playerKey == null ||
                  g.card.involves(playerKey) ||
                  players
                      .where((p) => p.key == playerKey)
                      .any((p) => p.aliasKeys.any(g.card.involves))) &&
              (search.eco.isEmpty || g.card.eco == search.eco) &&
              (search.text.isEmpty ||
                  '${g.card.white.name} ${g.card.black.name}'
                      .toLowerCase()
                      .contains(search.text.toLowerCase())),
        )
        .toList();
  }

  @override
  Future<({List<CollectionAuthor> items, int total})> searchAuthors(
    CollectionSearchQuery query,
    int offset,
  ) async => (
    items: const [
      CollectionAuthor(
        id: 'credit:author',
        name: 'Bobby Fischer',
        avatarUrl: 'https://example.com/author.jpg',
        bookCount: 1,
      ),
    ],
    total: 1,
  );

  @override
  Future<List<CollectionPlayer>> fetchPlayers(String slug) async => players;
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

CollectionGame _game(
  String id, {
  String? sectionId,
  int orderIndex = 0,
  DateTime? playedOn,
  String? eco,
}) {
  return CollectionGame.fromCard(
    CollectionGameCard(
      id: id,
      sectionId: sectionId,
      playedOn: playedOn,
      eco: eco,
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
    'book search stays usable for empty results and clearing restores games',
    (tester) async {
      final repo = _FakeCollections(
        detail: const Collection(
          id: 'search',
          slug: 'search',
          kind: CollectionKind.book,
          title: 'Search book',
          access: CollectionAccess.free,
        ),
        games: [
          _game('a', eco: 'B20'),
          _game('b', eco: 'C60'),
        ],
      );
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final referenceText = TextEditingController();
      final referenceFocus = FocusNode();
      addTearDown(referenceText.dispose);
      addTearDown(referenceFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: ResponsiveHelper.isTablet
                          ? ResponsiveHelper.contentMaxWidth
                          : double.infinity,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EventSearchBarFrame(
                          horizontalPadding: ResponsiveHelper.adaptive(
                            phone: 20.sp,
                            tablet: 32.sp,
                          ),
                          child: SimpleSearchBar(
                            controller: referenceText,
                            focusNode: referenceFocus,
                            onCloseTap: () {},
                            onOpenFilter: null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tournamentSearchSize = tester.getSize(find.byType(SimpleSearchBar));
      await _pump(tester, repo);
      final input = find.byKey(const ValueKey('collection_games_search'));
      expect(
        tester.getSize(find.byType(SimpleSearchBar)).width,
        closeTo(tournamentSearchSize.width, 0.01),
      );
      expect(
        tester.getSize(find.byType(SimpleSearchBar)).height,
        closeTo(tournamentSearchSize.height, 0.01),
      );
      final tabs = find.byKey(
        const ValueKey('event_view_tabs_About_Openings_Games_Players'),
      );
      expect(input, findsOneWidget);
      expect(tester.getRect(input).bottom, lessThan(tester.getRect(tabs).top));
      expect(
        find.byKey(const ValueKey('collection_games_filters')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('collection_games_filters')));
      await tester.pumpAndSettle();
      expect(find.text('Apply Filters'), findsOneWidget);
      expect(find.text('Sort'), findsNothing);
      expect(find.text('Annotations'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.enterText(input, 'missing');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(repo.filteredQueries.last.query.text, 'missing');
      expect(find.byType(GameCard), findsNothing);
      expect(find.text('No games match this search.'), findsOneWidget);
      expect(input, findsOneWidget);
      await tester.drag(tabs, const Offset(300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('About').first);
      await tester.pumpAndSettle();
      expect(input, findsOneWidget);
      expect(tester.getRect(input).bottom, lessThan(tester.getRect(tabs).top));
      await tester.tap(find.text('Games').first);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, 'missing');
      expect(tester.getRect(input).bottom, lessThan(tester.getRect(tabs).top));
      await tester.enterText(input, 'Nimzowitsch');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsNWidgets(2));
      await tester.enterText(input, '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    },
  );

  testWidgets('book search is fixed across tabs and combines existing cards', (
    tester,
  ) async {
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'book',
        slug: 'book',
        kind: CollectionKind.book,
        title: 'Search book',
        access: CollectionAccess.free,
      ),
      games: [_game('match', eco: 'B00')],
      openings: const [
        CollectionOpening(
          eco: 'B00',
          name: 'Nimzowitsch defence',
          gameCount: 1,
        ),
      ],
      players: const [
        CollectionPlayer(
          key: 'name:nimzowitsch, aron',
          name: 'Nimzowitsch, Aron',
          games: 1,
        ),
      ],
    );
    await _pump(tester, repo, size: const Size(390, 844));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('collection_games_search'));
    final searchBar = find.byType(SimpleSearchBar);
    final initialRect = tester.getRect(searchBar);
    for (final tab in ['Players', 'Openings', 'About', 'Games']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(tester.getRect(searchBar), initialRect);
    }
    await tester.enterText(input, 'Nimzowitsch');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final results = find.byKey(const ValueKey('book_search_results'));
    expect(results, findsOneWidget);
    expect(
      find.byKey(const ValueKey('book_search_opening_B00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: results, matching: find.byType(GameCard)),
      findsOneWidget,
    );
    expect(repo.filteredSlugs.toSet(), {'book'});
    await tester.scrollUntilVisible(
      find.byType(FigmaPlayerCard),
      100,
      scrollable: find.descendant(
        of: results,
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.descendant(of: results, matching: find.byType(FigmaPlayerCard)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('collection_games_filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1-0'));
    await tester.tap(find.text('1-0'));
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(
      repo.filteredQueries.any(
        (q) => q.query.text == 'Nimzowitsch' && q.query.result == '1-0',
      ),
      isTrue,
    );
    expect(
      repo.filteredQueries.any(
        (q) => q.query.text.isEmpty && q.query.result == '1-0',
      ),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('collection_games_filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reset'));
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();
    expect(tester.getRect(searchBar), initialRect);
    expect(results, findsOneWidget);
    await tester.enterText(input, '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(results, findsNothing);
    expect(
      tester
          .widget<SegmentedSwitcher>(find.byType(SegmentedSwitcher))
          .currentSelection,
      3,
    );
    expect(find.byType(FigmaPlayerCard), findsOneWidget);
    final playerCard = tester.widget<FigmaPlayerCard>(
      find.byType(FigmaPlayerCard),
    );
    expect(playerCard.rank, 1);
    expect(playerCard.showRank, isTrue);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets(
    'book tabs slide to About and opening taps show only that book opening games',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _FakeCollections(
        detail: const Collection(
          id: 'book',
          slug: 'book',
          kind: CollectionKind.book,
          title: 'Opening book',
          access: CollectionAccess.free,
        ),
        games: [
          _game('sicilian', eco: 'B20', playedOn: DateTime(2026, 8, 29)),
          _game('ruy', eco: 'C60', playedOn: DateTime(2026, 8, 30)),
        ],
        openings: const [
          CollectionOpening(eco: 'B20', gameCount: 1),
          CollectionOpening(eco: 'C60', gameCount: 1),
        ],
      );
      await _pump(tester, repo, size: const Size(390, 844));
      await tester.pumpAndSettle();
      final strip = find.byType(SegmentedSwitcher);
      final switcher = tester.widget<SegmentedSwitcher>(strip);
      expect(switcher.options, ['About', 'Openings', 'Games', 'Players']);
      expect(switcher.isScrollable, isTrue);
      expect(switcher.currentSelection, 2);
      final tabScroller = find.descendant(
        of: strip,
        matching: find.byType(SingleChildScrollView),
      );
      ScrollController tabScroll() =>
          tester.widget<SingleChildScrollView>(tabScroller).controller!;
      expect(
        tabScroll().offset,
        closeTo(tabScroll().position.maxScrollExtent, 0.01),
      );
      await tester.tap(find.text('Openings').first);
      await tester.pumpAndSettle();
      expect(tabScroll().offset, closeTo(0, 0.01));
      expect(repo.openingSlugs, contains('book'));
      expect(
        find.byKey(const ValueKey('collection_opening_all')),
        findsNothing,
      );
      for (final category in ['A', 'D', 'E']) {
        expect(
          find.byKey(ValueKey('collection_opening_category_$category')),
          findsNothing,
        );
      }
      for (final category in ['B', 'C']) {
        expect(
          find.byKey(ValueKey('collection_opening_category_$category')),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('About').first);
      await tester.pumpAndSettle();
      expect(tester.widget<SegmentedSwitcher>(strip).currentSelection, 0);
      await tester.tap(find.text('Games').first);
      await tester.pumpAndSettle();
      expect(
        tabScroll().offset,
        closeTo(tabScroll().position.maxScrollExtent, 0.01),
      );
      await tester.tap(find.text('Players').first);
      await tester.pumpAndSettle();
      expect(
        tabScroll().offset,
        closeTo(tabScroll().position.maxScrollExtent, 0.01),
      );
      await tester.tap(find.text('Openings').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('collection_opening_category_B')),
      );
      await tester.pumpAndSettle();
      final opening = find.byKey(const ValueKey('collection_opening_B20'));
      for (var depth = 0; depth < 8 && opening.evaluate().isEmpty; depth++) {
        final closed = find.byWidgetPredicate(
          (w) =>
              w is TournamentRoundHeader &&
              w.key.toString().contains('collection_opening_family_') &&
              !w.isExpanded,
        );
        await tester.ensureVisible(closed.first);
        await tester.tap(closed.first);
        await tester.pumpAndSettle();
      }
      expect(opening, findsOneWidget);
      expect(
        find.descendant(of: opening, matching: find.text('1 game')),
        findsOneWidget,
      );
      await tester.ensureVisible(opening);
      await tester.tap(opening);
      await tester.pumpAndSettle();
      expect(repo.filteredSlugs.last, 'book');
      expect(repo.filteredQueries.last.query.eco, 'B20');
      expect(repo.filteredQueries.last.player, isNull);
      expect(find.byType(GameCard), findsOneWidget);
      expect(find.text('29 Aug 2026'), findsOneWidget);
      final dateHeader = find.byWidgetPredicate(
        (w) => w is TournamentRoundHeader && w.subtitle == '29 Aug 2026',
      );
      await tester.tap(dateHeader);
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(opening, findsOneWidget);
      expect(tester.widget<SegmentedSwitcher>(strip).currentSelection, 1);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    },
  );

  testWidgets(
    'root openings disclose families and authors open only their books',
    (tester) async {
      final repo = _FakeCollections(
        detail: const Collection(
          id: 'root',
          slug: 'root',
          kind: CollectionKind.book,
          title: 'Published book',
          access: CollectionAccess.free,
        ),
        games: [],
        openings: const [
          CollectionOpening(
            eco: 'B20',
            gameCount: 2,
            bookCount: 1,
            fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
          ),
        ],
      );
      await _pump(tester, repo, home: const CollectionsScreen());
      await tester.tap(find.text('Openings').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('collection_opening_category_B')),
        findsOneWidget,
      );
      expect(find.text('All Openings'), findsOneWidget);
      for (final category in ['A', 'B', 'C', 'D', 'E']) {
        expect(
          find.byKey(ValueKey('collection_opening_category_$category')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey('collection_opening_B20')),
        findsNothing,
      );
      final categoryRect = tester.getRect(
        find.byKey(const ValueKey('collection_opening_category_B')),
      );
      await tester.tap(
        find.byKey(const ValueKey('collection_opening_category_B')),
      );
      await tester.pumpAndSettle();
      final family = find.byWidgetPredicate(
        (w) =>
            w is TournamentRoundHeader &&
            w.key.toString().contains('collection_opening_family_'),
      );
      expect(family, findsWidgets);
      final familyRect = tester.getRect(family.first);
      expect(familyRect.left, greaterThan(categoryRect.left));
      expect(familyRect.right, closeTo(categoryRect.right, 0.01));
      expect(familyRect.height, closeTo(categoryRect.height, 0.01));
      for (
        var depth = 0;
        depth < 8 &&
            find
                .byKey(const ValueKey('collection_opening_B20'))
                .evaluate()
                .isEmpty;
        depth++
      ) {
        final closed = find.byWidgetPredicate(
          (w) =>
              w is TournamentRoundHeader &&
              w.key.toString().contains('collection_opening_family_') &&
              !w.isExpanded,
        );
        await tester.ensureVisible(closed.first);
        await tester.tap(closed.first);
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const ValueKey('collection_opening_B20')),
        findsOneWidget,
      );
      final opening = find.byKey(const ValueKey('collection_opening_B20'));
      final openingRect = tester.getRect(opening);
      expect(openingRect.left, greaterThan(familyRect.left));
      expect(openingRect.right, closeTo(categoryRect.right, 0.01));
      expect(
        find.descendant(of: opening, matching: find.text('1 book')),
        findsOneWidget,
      );
      final miniBoard = tester.widget<GameCardChessboard>(
        find.descendant(of: opening, matching: find.byType(GameCardChessboard)),
      );
      expect(miniBoard.fen, repo.openings.single.fen);
      expect(miniBoard.boardSize, CollectionPlateRow.eventPlate.height);
      final positionRow = tester.widget<CollectionPlateRow>(
        find.descendant(of: opening, matching: find.byType(CollectionPlateRow)),
      );
      expect(positionRow.plateSize, CollectionPlateRow.eventPlate);
      await tester.ensureVisible(
        find.byKey(const ValueKey('collection_opening_category_B')),
      );
      await tester.tap(
        find.byKey(const ValueKey('collection_opening_category_B')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('collection_opening_B20')),
        findsNothing,
      );
      await tester.tap(find.text('Authors').first);
      await tester.pumpAndSettle();
      expect(find.byType(FigmaPlayerCard), findsOneWidget);
      final authorCard = tester.widget<FigmaPlayerCard>(
        find.byType(FigmaPlayerCard),
      );
      expect(authorCard.rank, 1);
      expect(authorCard.showRank, isTrue);
      expect(
        find.descendant(
          of: find.byType(FigmaPlayerCard),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        (authorCard.avatar as PlayerInitialsAvatar).photoUrl,
        'https://example.com/author.jpg',
      );
      final authorList = tester.widget<CollectionCatalogList<CollectionAuthor>>(
        find.byType(CollectionCatalogList<CollectionAuthor>),
      );
      expect(authorList.padding.top, 8.sp);
      await tester.tap(find.byType(FigmaPlayerCard));
      await tester.pumpAndSettle();
      expect(find.text('Bobby Fischer'), findsOneWidget);
      expect(find.byType(CollectionCard), findsOneWidget);
      expect(repo.bookQueries.last.author, 'Bobby Fischer');
      expect(repo.bookQueries.last.authorId, isEmpty);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    },
  );

  testWidgets(
    'players use the shared card and legacy aliases filter every game',
    (tester) async {
      final players = CollectionPlayer.listFromJson({
        'items': [
          {
            'key': 'fide:1',
            'name': 'Nimzowitsch, Aron',
            'fideId': '1',
            'games': 1,
          },
          {
            'key': 'name:nimzowitsch, aron',
            'name': 'Aron Nimzowitsch',
            'games': 1,
          },
        ],
      });
      final repo = _FakeCollections(
        detail: const Collection(
          id: 'players',
          slug: 'players',
          kind: CollectionKind.event,
          title: 'Player study',
        ),
        games: [
          _game('a', playedOn: DateTime(2026, 8, 29)),
          _game('b', playedOn: DateTime(2026, 8, 29)),
        ],
        players: players,
      );
      await _pump(tester, repo, textScale: 1.4);
      await tester.tap(find.text('Players').first);
      await tester.pumpAndSettle();
      expect(find.byType(FigmaPlayerCard), findsOneWidget);
      expect(find.text('2 games'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      await tester.tap(find.byType(FigmaPlayerCard));
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsNWidgets(2));
      expect(find.text('29 Aug 2026'), findsOneWidget);
      expect(repo.filteredQueries.last.player, 'fide:1');
      expect(
        find.byKey(const ValueKey('collection_games_search')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(FigmaPlayerCard), findsOneWidget);
      expect(find.byType(GameCard), findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    },
  );

  testWidgets(
    'shared round cards collapse and the selector opens the chosen round',
    (tester) async {
      final repo = _FakeCollections(
        detail: const Collection(
          id: 'fold',
          slug: 'fold',
          kind: CollectionKind.event,
          title: 'Study',
          sections: [
            CollectionSection(
              id: 'r1',
              kind: CollectionSectionKind.round,
              label: 'Round 1',
            ),
            CollectionSection(
              id: 'r2',
              kind: CollectionSectionKind.round,
              label: 'Round 2',
            ),
          ],
        ),
        games: [
          _game('a', sectionId: 'r1'),
          _game('b', sectionId: 'r2'),
        ],
      );
      await _pump(tester, repo);
      expect(find.byType(GameCard), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('collection_round_r1')));
      await tester.pump();
      expect(find.byType(GameCard), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Round 1').last);
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsOneWidget);
      expect(find.byKey(const ValueKey('collection_round_r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('collection_round_r2')), findsNothing);
      await _teardown(tester);
    },
  );

  testWidgets(
    'the search field debounces, filters the unified list and clears',
    (tester) async {
      const zurich = Collection(
        id: 'zurich',
        slug: 'zurich',
        kind: CollectionKind.event,
        title: 'Zurich 1953',
        location: 'Zurich',
      );
      const endgames = Collection(
        id: 'endgames',
        slug: 'endgames',
        kind: CollectionKind.book,
        title: 'Carlsen Endgames',
        author: 'Magnus Carlsen',
      );
      final repo = _FakeCollections(
        detail: zurich,
        games: const [],
        list: const [zurich, endgames],
      );
      await _pump(
        tester,
        repo,
        size: const Size(393, 852),
        home: const CollectionsScreen(embedded: true),
      );
      expect(find.byType(CollectionCard), findsNWidgets(2));
      final field = find.byKey(const ValueKey('collections_search'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Carlsen');
      // Inside the debounce window the list has not filtered yet.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CollectionCard), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Zurich 1953'), findsNothing);
      expect(find.text('Carlsen Endgames'), findsOneWidget);
      await tester.enterText(field, '');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.byType(CollectionCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
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
      // Three tabs use the same switcher and shared main-route geometry.
      expect(find.byType(SegmentedSwitcher), findsOneWidget);

      final context = tester.element(find.byType(HomeTopBarFrame));
      final row = tester.getRect(find.byType(HomeTopBarRow));
      final pages = tester.getRect(find.byType(PageView));
      expect(row.top, closeTo(HomeTopBarMetrics.topInset(context), 0.5));
      expect(
        pages.top - row.bottom,
        closeTo(
          16.h + 12.h + tester.getSize(find.byType(SegmentedSwitcher)).height,
          0.5,
        ),
      );
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

        await tester.tap(find.bySemanticsLabel('Toggle chessboard view'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(GameCard), findsNothing);
        expect(find.byType(GridChessBoardFromFENNew), findsNWidgets(2));

        await tester.tap(find.bySemanticsLabel('Toggle chessboard view'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(GridChessBoardFromFENNew), findsNothing);
        expect(find.byType(ChessBoardFromFENNew), findsNWidgets(2));

        await tester.tap(find.bySemanticsLabel('Toggle chessboard view'));
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

  testWidgets('analysis keeps editorial credits in About with a Players tab', (
    tester,
  ) async {
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
    await _pump(tester, _FakeCollections(detail: collection, games: const []));
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Games'), findsOneWidget);
    expect(find.text('Players'), findsOneWidget);
    await tester.ensureVisible(find.text('About'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('by Test Author'), findsOneWidget);
    expect(find.text('Annotated by Test Annotator'), findsOneWidget);
    expect(find.text('An editorial biography.'), findsOneWidget);
    expect(find.text('An editorial annotator biography.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets(
    'primary Collections shows three tabs and re-tap returns the current list to the top',
    (tester) async {
      final books = [
        for (var i = 0; i < 25; i++)
          Collection(
            id: 'study-$i',
            slug: 'study-$i',
            kind: CollectionKind.book,
            title: 'Opening studies $i',
            access: CollectionAccess.free,
          ),
      ];
      final repo = _FakeCollections(
        detail: books.first,
        games: [_game('one')],
        list: books,
      );
      await _pump(
        tester,
        repo,
        size: const Size(390, 844),
        home: const CollectionsScreen(embedded: true),
      );
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.text('Openings'), findsOneWidget);
      expect(find.text('Authors'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
      expect(find.byType(CollectionCard), findsWidgets);
      final list = find.descendant(
        of: find.byType(PageView),
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
    'a book opened on an opening requests games scoped to the book and ECO',
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
        games: [
          _game('one', eco: 'B20'),
          _game('two', eco: 'C60'),
        ],
        openings: [opening],
      );
      await _pump(
        tester,
        repo,
        home: CollectionScreen(collection: book, opening: opening),
      );
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
      final repo = _FakeCollections(
        detail: book,
        games: [_game('one', eco: 'C60')],
      );
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

    expect(find.textContaining('Round 1'), findsOneWidget);
    expect(find.textContaining('2 Oct 2025'), findsOneWidget);
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text('Casual'), findsOneWidget);
    final y = [
      for (final t in ['Round 1', 'Round 2', 'Casual'])
        tester.getTopLeft(find.textContaining(t)).dy,
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
    expect(_rich('Chapter 7: The Pin'), findsOneWidget);
    expect(find.text('A pinned piece cannot move.'), findsOneWidget);
    expect(find.text('Exploit it.'), findsOneWidget);
    expect(_rich('Nothing here yet'), findsNothing);
    expect(find.text('Casual'), findsNothing);
    await _teardown(tester);
  });

  testWidgets(
    'a collection without sections uses the tournament round header',
    (tester) async {
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
      expect(find.byType(TournamentRoundHeader), findsOneWidget);
      expect(find.text('Casual'), findsOneWidget);
      await _teardown(tester);
    },
  );
}
