import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/screens/collections/collection_author_screen.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/screens/collections/collection_catalog_list.dart';
import 'package:chessever2/screens/collections/collection_catalog_views.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_root.dart';
import 'package:chessever2/screens/collections/collections_tab_provider.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/home/home_screen.dart' show BottomNavBarView;
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart'
    show ForYouPageTabs;
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/collections/collection_explore.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/widget/text_dropdown_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:dio/dio.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/duo_window_matrix.dart';
import 'support/signed_in_auth.dart';

/// Books use a flat Games list; event collections retain section headers.

class _FakeCollections extends CollectionsRepository {
  _FakeCollections({
    required this.detail,
    required this.games,
    this.openings = const [],
    this.players = const [],
    this.list,
    this.publishedLoader,
    this.searchResult,
    this.authors,
    this.booksByAuthor = const {},
  }) : super(GamebaseRepository(Dio(), apiKey: 'test'));

  final Collection detail;
  final List<CollectionGame> games;
  final List<CollectionOpening> openings;
  final List<CollectionPlayer> players;
  final List<Collection>? list;
  final List<CollectionAuthor>? authors;
  final Map<String, List<Collection>> booksByAuthor;
  final List<CollectionGame> Function(CollectionSearchQuery)? searchResult;
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
      items: (booksByAuthor[query.authorId] ?? list ?? [detail])
          .where(
            (c) =>
                query.text.isEmpty ||
                '${c.title} ${c.author ?? ''}'.toLowerCase().contains(
                  query.text.toLowerCase(),
                ),
          )
          .toList(),
      total: (booksByAuthor[query.authorId] ?? list ?? [detail]).length,
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

  @override
  Future<List<CollectionGame>> fetchPlayableGames(String slug) async => games;

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
    if (searchResult != null) return searchResult!(search);
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

  final authorQueries = <CollectionSearchQuery>[];
  @override
  Future<({List<CollectionAuthor> items, int total})> searchAuthors(
    CollectionSearchQuery query,
    int offset,
  ) async {
    authorQueries.add(query);
    final items =
        authors ??
        const [
          CollectionAuthor(
            id: 'credit:author',
            name: 'Bobby Fischer',
            avatarUrl: 'https://example.com/author.jpg',
            bookCount: 1,
          ),
        ];
    return (items: items, total: items.length);
  }

  @override
  Future<List<CollectionPlayer>> fetchPlayers(String slug) async => players;
}

/// A collection whose searches answer only when [release]d, so a test can
/// look at the list while the next results are on their way.
class _SlowSearch extends _FakeCollections {
  _SlowSearch({required super.detail, required super.games});

  final pending = <Completer<void>>[];

  void release() {
    for (final wait in pending) {
      if (!wait.isCompleted) wait.complete();
    }
  }

  @override
  Future<List<CollectionGame>> searchGames(
    String slug,
    CollectionSearchQuery search, {
    String? playerKey,
  }) async {
    final wait = Completer<void>();
    pending.add(wait);
    await wait.future;
    return super.searchGames(slug, search, playerKey: playerKey);
  }
}

/// A catalog whose book searches (words typed) answer only when
/// [release]d; browsing answers at once.
class _SlowBooks extends _FakeCollections {
  _SlowBooks({required super.detail, required super.games, super.list});

  final pending = <Completer<void>>[];

  void release() {
    for (final wait in pending) {
      if (!wait.isCompleted) wait.complete();
    }
  }

  @override
  Future<CollectionsPage> searchBooks(
    CollectionSearchQuery query,
    int offset,
  ) async {
    if (query.text.isNotEmpty) {
      final wait = Completer<void>();
      pending.add(wait);
      await wait.future;
    }
    final page = await super.searchBooks(query, offset);
    // One page holds every match.
    return CollectionsPage(
      items: page.items,
      total: page.items.length,
      limit: page.limit,
      offset: offset,
    );
  }
}

class _BookNavigationObserver extends NavigatorObserver {
  MaterialPageRoute<void>? lastPage;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute<void>) lastPage = route;
  }
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

/// A collection unpublished since its push: the read fails.
class _UnreadableCollection extends _FakeCollections {
  _UnreadableCollection({
    required super.detail,
    required super.games,
    this.failures = -1,
  });

  /// Reads that fail before one succeeds; negative never succeeds.
  int failures;

  @override
  Future<Collection> fetchCollection(String slug) async {
    if (failures == 0) return super.fetchCollection(slug);
    if (failures > 0) failures--;
    throw StateError('not published');
  }
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
  DuoWindowCase? duoWindow,
  bool light = false,
  double textScale = 1,
  Widget? home,
  CollectionsRepository Function()? repositoryFactory,
  NavigatorObserver? navigationObserver,
  bool? premium,
  GlobalKey<NavigatorState>? navigatorKey,
  RouteFactory? onGenerateRoute,
  ValueChanged<WidgetRef>? rootRef,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  if (duoWindow != null) {
    applyDuoWindow(tester, duoWindow);
    addTearDown(tester.view.reset);
  }
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(null),
      collectionsRepositoryProvider.overrideWith(
        (_) => repositoryFactory?.call() ?? repo,
      ),
      subscriptionProvider.overrideWith((ref) => _Subscription()),
      if (premium != null) premiumAccessProvider.overrideWithValue(premium),
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
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  final app = MaterialApp(
    navigatorKey: navigatorKey,
    onGenerateRoute: onGenerateRoute,
    navigatorObservers: [if (navigationObserver != null) navigationObserver],
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: AdaptiveWindowScope(child: child!),
    ),
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return home ?? CollectionScreen(collection: repo.detail);
      },
    ),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // The app's own ref, above every route, as main.dart hands the
      // notification router.
      child: rootRef == null
          ? app
          : Consumer(
              builder: (_, ref, child) {
                rootRef(ref);
                return child!;
              },
              child: app,
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

/// Opens the page's full-page search from its floating button: the field
/// takes the header's place.
Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('event_view_search_fab')));
  await tester.pumpAndSettle();
}

void main() {
  _FakeCollections duoRepository() => _FakeCollections(
    detail: const Collection(
      id: 'duo-book',
      slug: 'duo-book',
      kind: CollectionKind.book,
      title: 'European Championship Opening Studies',
      about: 'Opening studies from the championship.',
      access: CollectionAccess.free,
    ),
    games: [_game('duo-one')],
    players: const [
      CollectionPlayer(
        key: 'name:nimzowitsch, aron',
        name: 'Nimzowitsch, Aron',
        games: 1,
      ),
    ],
  );

  for (final window in duoWindowCases) {
    for (final light in [false, true]) {
      testWidgets('Duo collection tabs fit ${window.name}, '
          '${light ? 'light' : 'dark'}', (tester) async {
        await _pump(
          tester,
          duoRepository(),
          size: window.size,
          duoWindow: window,
          textScale: 1.3,
          light: light,
          premium: true,
        );
        expect(tester.takeException(), isNull);
        for (final tab in ['About', 'Players', 'Games']) {
          await tester.tap(find.text(tab).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.byType(GameCard), findsOneWidget);
        await _openSearch(tester);
        final search = tester.getRect(find.byType(SimpleSearchBar));
        expect(search.left, greaterThanOrEqualTo(0));
        expect(search.right, lessThanOrEqualTo(window.size.width));
        expect(search.bottom, lessThanOrEqualTo(window.size.height));
        await _teardown(tester);
      });
    }
  }
  for (final transition in duoWindowTransitions) {
    testWidgets('Duo collection retains selected tab and search: '
        '${transition.from.name} to ${transition.to.name}', (tester) async {
      await _pump(
        tester,
        duoRepository(),
        size: transition.from.size,
        duoWindow: transition.from,
        textScale: 1.3,
        premium: true,
      );
      await tester.tap(find.text('Players').first);
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(CollectionScreen));
      final selection = tester
          .widget<SegmentedSwitcher>(find.byType(SegmentedSwitcher))
          .currentSelection;
      // A book searches its players too: the search opens over Players.
      await _openSearch(tester);
      final input = find.byKey(const ValueKey('collection_games_search'));
      final searchController = tester.widget<TextField>(input).controller;

      applyDuoWindow(tester, transition.to, mirrorInsets: true);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.state(find.byType(CollectionScreen)), same(state));
      expect(
        tester.widget<TextField>(input).controller,
        same(searchController),
      );
      expect(find.byType(FigmaPlayerCard), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event_view_search_close')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedSwitcher>(find.byType(SegmentedSwitcher))
            .currentSelection,
        selection,
      );
      expect(find.byType(FigmaPlayerCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });
  }

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
      final tabs = find.byKey(
        const ValueKey('event_view_tabs_About_Games_Players'),
      );
      // The search waits behind its floating button, off the list's top.
      expect(input, findsNothing);
      expect(tabs, findsOneWidget);
      await _openSearch(tester);
      // The field stands as tall as the event screen's, in the header's
      // place: the tabs give way to it.
      expect(
        tester.getSize(find.byType(SimpleSearchBar)).height,
        closeTo(tournamentSearchSize.height, 0.01),
      );
      expect(input, findsOneWidget);
      // The tabs wait under the field, as they were left, out of reach.
      expect(tabs.hitTestable(), findsNothing);
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
      expect(
        find.text(SearchNoMatches.titleFor(query: 'missing')),
        findsOneWidget,
      );
      expect(input, findsOneWidget);
      // Its way back empties the words, the search still open over every
      // game.
      await tester.tap(find.byKey(const ValueKey('search_no_matches_clear')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(find.byType(GameCard), findsNWidgets(2));
      await tester.enterText(input, 'missing');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsNothing);
      await tester.enterText(input, 'Nimzowitsch');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsNWidgets(2));
      await tester.enterText(input, '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsNWidgets(2));
      // Back closes the search and clears it: the tabs return, and the
      // games with them.
      await tester.enterText(input, 'missing');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsNothing);
      await tester.tap(find.byKey(const ValueKey('event_view_search_close')));
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(tabs, findsOneWidget);
      expect(find.byType(GameCard), findsNWidgets(2));
      await _openSearch(tester);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    },
  );

  testWidgets('a trailing space does not reload the Collections search', (
    tester,
  ) async {
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'book',
        slug: 'book',
        kind: CollectionKind.book,
        title: 'Sicilian lines',
        access: CollectionAccess.free,
      ),
      games: [],
    );
    await _pump(
      tester,
      repo,
      size: const Size(390, 844),
      home: const CollectionsScreen(),
    );
    await tester.pumpAndSettle();
    await _openSearch(tester);
    final input = find.byKey(const ValueKey('collections_search'));

    await tester.enterText(input, 'sicilian');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final searched = repo.bookQueries.length + repo.searchQueries.length;
    expect(
      [...repo.bookQueries, ...repo.searchQueries].map((q) => q.text),
      contains('sicilian'),
    );

    await tester.enterText(input, 'sicilian ');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repo.bookQueries.length + repo.searchQueries.length, searched);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('book search keeps the server subset and order on the board', (
    tester,
  ) async {
    final first = _game('first', sectionId: 'chapter-a', orderIndex: 0);
    final second = _game('second', sectionId: 'chapter-b', orderIndex: 0);
    final third = _game('third', sectionId: 'chapter-a', orderIndex: 1);
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'book',
        slug: 'book',
        kind: CollectionKind.book,
        title: 'Filtered book',
        access: CollectionAccess.free,
        sections: [
          CollectionSection(
            id: 'chapter-a',
            kind: CollectionSectionKind.chapter,
            label: 'Chapter A',
          ),
          CollectionSection(
            id: 'chapter-b',
            kind: CollectionSectionKind.round,
            label: 'Round B',
          ),
        ],
      ),
      games: [first, second, third],
      // The endpoint's filtered/ranked response is authoritative, including
      // order that crosses chapters and differs from local orderIndex.
      searchResult: (_) => [third, first],
    );
    final observer = _BookNavigationObserver();
    // Rewarded access admits these archived games without a paid subscription.
    await _pump(tester, repo, navigationObserver: observer, premium: true);
    await _openSearch(tester);
    await tester.enterText(
      find.byKey(const ValueKey('collection_games_search')),
      '[White "Nimzowitsch"]',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repo.filteredQueries.last.query.text, '[White "Nimzowitsch"]');
    expect(find.byType(TournamentRoundHeader), findsNothing);
    expect(find.byType(GameCard), findsNWidgets(2));
    final rows = tester
        .widgetList<DiscoveryGameList>(find.byType(DiscoveryGameList))
        .toList();
    expect(
      [for (final row in rows) row.games[row.start].gameId],
      ['third', 'first'],
    );
    await tester.tap(find.byType(GameCard).last);
    // Inspect the pushed route's widget without mounting the live board.
    final board =
        observer.lastPage!.builder(
              tester.element(find.byType(CollectionScreen)),
            )
            as ChessBoardScreenNew;
    expect(board.games.map((game) => game.gameId), ['third', 'first']);
    expect(board.currentIndex, 1);
    expect(board.allowGameExport, isFalse);
    await _teardown(tester);
  });

  testWidgets('a book search narrows the tab it opens on, in place, with '
      "that tab's own cards", (tester) async {
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'book',
        slug: 'book',
        kind: CollectionKind.book,
        title: 'Search book',
        access: CollectionAccess.free,
      ),
      games: [_game('match', eco: 'B00')],
      players: const [
        CollectionPlayer(
          key: 'name:nimzowitsch, aron',
          name: 'Nimzowitsch, Aron',
          games: 1,
        ),
        CollectionPlayer(
          key: 'name:tarrasch, siegbert',
          name: 'Tarrasch, Siegbert',
          games: 0,
        ),
      ],
    );
    await _pump(tester, repo, size: const Size(390, 844), premium: true);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('collection_games_search'));
    final fab = find.byKey(const ValueKey('event_view_search_fab'));
    final close = find.byKey(const ValueKey('event_view_search_close'));
    final gamesList = find.byKey(const PageStorageKey('collection_games'));
    // The button floats over the lists the search covers, not over About.
    for (final (tab, shown) in [('About', false), ('Players', true)]) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(fab, shown ? findsOneWidget : findsNothing, reason: tab);
    }

    // Players: the Players list itself, narrowed by name, each player
    // keeping the rank they hold in the full list.
    await _openSearch(tester);
    await tester.enterText(input, 'Tarr');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('book_search_results')), findsNothing);
    final tarrasch = tester.widget<FigmaPlayerCard>(
      find.byType(FigmaPlayerCard),
    );
    expect(tarrasch.player.name, 'Tarrasch, Siegbert');
    expect(tarrasch.rank, 2);
    await tester.enterText(input, 'nobody');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.byType(FigmaPlayerCard), findsNothing);
    expect(
      find.text(SearchNoMatches.titleFor(query: 'nobody', subject: 'players')),
      findsOneWidget,
    );
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(FigmaPlayerCard), findsNWidgets(2));

    // Games: the same list, filtered as the reader types.
    await tester.tap(find.text('Games').first);
    await tester.pumpAndSettle();
    final list = tester.state<ScrollableState>(
      find.descendant(of: gamesList, matching: find.byType(Scrollable)),
    );
    await _openSearch(tester);
    await tester.enterText(input, 'Nimzowitsch');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(
        find.descendant(of: gamesList, matching: find.byType(Scrollable)),
      ),
      same(list),
    );
    expect(
      find.descendant(of: gamesList, matching: find.byType(GameCard)),
      findsOneWidget,
    );
    expect(repo.filteredQueries.last.query.text, 'Nimzowitsch');
    expect(repo.filteredSlugs.toSet(), {'book'});

    // Its filters stand beside the field.
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

    // Closed, the words go and the filter stays on the list it narrows,
    // counted on the Filters glyph in the header (not twice, on the
    // button too).
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(input, findsNothing);
    final headerFilters = find.byKey(const ValueKey('event_view_filters'));
    expect(headerFilters.hitTestable(), findsOneWidget);
    expect(tester.widget<SearchModeFilterButton>(headerFilters).count, 1);
    expect(tester.widget<SearchInkFab>(fab).badgeCount, 0);
    expect(repo.filteredQueries.last.query.text, isEmpty);
    expect(repo.filteredQueries.last.query.result, '1-0');
    expect(find.byType(GameCard), findsOneWidget);

    // The filter narrows Players too, to the players of the games it
    // keeps: Tarrasch plays none of them.
    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();
    expect(
      repo.filteredQueries.any(
        (q) => q.query.text.isEmpty && q.query.result == '1-0',
      ),
      isTrue,
    );
    expect(find.byType(FigmaPlayerCard), findsOneWidget);
    final kept = tester.widget<FigmaPlayerCard>(find.byType(FigmaPlayerCard));
    expect(kept.player.name, 'Nimzowitsch, Aron');
    expect(kept.rank, 1);
    expect(kept.showRank, isTrue);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  // 38.17 listed a book search's matching openings above its games; the
  // overhaul's in-place search lost them (found 2026-11-22).
  testWidgets('a book search names its openings again: they head the Games '
      'hits, an ECO code finds one too, and a tap opens its games', (
    tester,
  ) async {
    final najdorf = _game('najdorf-game', eco: 'B90');
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'book',
        slug: 'book',
        kind: CollectionKind.book,
        title: 'Search book',
        access: CollectionAccess.free,
      ),
      games: [
        najdorf,
        _game('petrov-game', eco: 'C42'),
      ],
      openings: const [
        CollectionOpening(eco: 'B90', name: 'Sicilian, Najdorf', gameCount: 1),
        CollectionOpening(eco: 'B33', name: 'Sicilian, Sveshnikov'),
        CollectionOpening(eco: 'C42', name: 'Petrov Defence', gameCount: 1),
      ],
      // The server matches the opening's name in the games' PGN.
      searchResult: (query) =>
          query.text.toLowerCase().contains('sicilian') ? [najdorf] : const [],
    );
    await _pump(tester, repo, size: const Size(390, 844), premium: true);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('collection_games_search'));
    final gamesList = find.byKey(const PageStorageKey('collection_games'));
    Finder opening(String eco) =>
        find.byKey(ValueKey('book_search_opening_$eco'));
    // Nothing of it before a search.
    expect(find.byKey(const ValueKey('book_search_openings')), findsNothing);

    await _openSearch(tester);
    await tester.enterText(input, 'sicilian');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(opening('B90'), findsOneWidget);
    expect(opening('B33'), findsOneWidget);
    expect(opening('C42'), findsNothing);
    // Above the games the words found, in the same list.
    expect(
      find.descendant(of: gamesList, matching: find.byType(GameCard)),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(opening('B33')).dy,
      lessThan(tester.getTopLeft(find.byType(GameCard)).dy),
    );

    // An ECO code names its opening; no game matched the words.
    await tester.enterText(input, 'c42');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(opening('C42'), findsOneWidget);
    expect(opening('B90'), findsNothing);
    expect(find.byType(GameCard), findsNothing);
    expect(find.text(SearchNoMatches.titleFor(query: 'c42')), findsOneWidget);

    await tester.tap(opening('C42'));
    await tester.pumpAndSettle();
    // That opening's games in the book, on a page of their own.
    expect(find.text('Petrov Defence'), findsWidgets);
    expect(repo.filteredQueries.any((q) => q.query.eco == 'C42'), isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Back on the search as it was left; closed, the openings go with it.
    expect(opening('C42'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('event_view_search_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('book_search_openings')), findsNothing);
    expect(find.byType(GameCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('the filters are in reach with the search closed, and only '
      'on the tabs it covers', (tester) async {
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'book',
        slug: 'book',
        kind: CollectionKind.book,
        title: 'Search book',
        about: 'A collection of opening studies.',
        access: CollectionAccess.free,
      ),
      games: [_game('match', eco: 'B00')],
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
    final headerFilters = find.byKey(const ValueKey('event_view_filters'));
    final title = find.text('Search book').first;
    final titleCentre = tester.getCenter(title).dx;
    expect(headerFilters.hitTestable(), findsOneWidget);
    expect(tester.widget<SearchModeFilterButton>(headerFilters).count, 0);

    // About has nothing to filter: the glyph keeps its place unseen, so
    // the title holds still.
    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    expect(headerFilters.hitTestable(), findsNothing);
    expect(tester.getCenter(title).dx, closeTo(titleCentre, 0.01));
    expect(find.text('A collection of opening studies.'), findsOneWidget);

    await tester.tap(find.text('Games').first);
    await tester.pumpAndSettle();
    await tester.tap(headerFilters);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1-0'));
    await tester.tap(find.text('1-0'));
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(repo.filteredQueries.last.query.result, '1-0');
    expect(tester.widget<SearchModeFilterButton>(headerFilters).count, 1);
    expect(find.byType(GameCard), findsOneWidget);

    // Opened, the search starts empty over the filtered list, the same
    // count beside its field.
    await _openSearch(tester);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('collection_games_search')),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<SearchModeFilterButton>(
            find.byKey(const ValueKey('collection_games_filters')),
          )
          .count,
      1,
    );
    expect(find.byType(GameCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('the chevron and the Filters glyph hold their places as the '
      'search opens and closes', (tester) async {
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'book',
        slug: 'book',
        kind: CollectionKind.book,
        title: 'Search book',
        access: CollectionAccess.free,
      ),
      games: [_game('match')],
    );
    await _pump(tester, repo, size: const Size(390, 844));
    await tester.pumpAndSettle();
    Rect glyph(Finder button) => tester.getRect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.arrow_back_ios_new_outlined),
      ),
    );
    Rect tune(Finder button) => tester.getRect(
      find.descendant(of: button, matching: find.byIcon(Icons.tune_rounded)),
    );
    final back = glyph(find.byTooltip('Back'));
    final filters = tune(find.byKey(const ValueKey('event_view_filters')));
    await _openSearch(tester);
    final close = glyph(find.byKey(const ValueKey('event_view_search_close')));
    expect(close.center.dx, closeTo(back.center.dx, 0.01));
    expect(close.center.dy, closeTo(back.center.dy, 0.01));
    expect(close.size, back.size);
    // Filters come last in both headers, their glyph on the gutter.
    final besideField = tune(
      find.byKey(const ValueKey('collection_games_filters')),
    );
    expect(besideField.center.dx, closeTo(filters.center.dx, 0.01));
    expect(besideField.center.dy, closeTo(filters.center.dy, 0.01));
    expect(390 - besideField.right, closeTo(SearchHeaderMetrics.gutter, 0.5));
    await tester.tap(find.byKey(const ValueKey('event_view_search_close')));
    await tester.pumpAndSettle();
    expect(glyph(find.byTooltip('Back')), back);
    expect(tune(find.byKey(const ValueKey('event_view_filters'))), filters);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('opening and closing the search keeps the list: no skeleton, '
      'no remount, its place kept', (tester) async {
    final repo = _SlowSearch(
      detail: const Collection(
        id: 'long-book',
        slug: 'long-book',
        kind: CollectionKind.book,
        title: 'Long book',
        access: CollectionAccess.free,
      ),
      games: [for (var i = 0; i < 30; i++) _game('g$i')],
    );
    await _pump(tester, repo, size: const Size(390, 844), premium: true);
    await tester.pumpAndSettle();
    final gamesList = find.byKey(const PageStorageKey('collection_games'));
    final scrollable = find.descendant(
      of: gamesList,
      matching: find.byType(Scrollable),
    );
    ScrollableState list() => tester.state<ScrollableState>(scrollable);
    await tester.drag(scrollable, const Offset(0, -700));
    await tester.pumpAndSettle();
    // A little back up brings the header and the search button back.
    await tester.drag(scrollable, const Offset(0, 120));
    await tester.pumpAndSettle();
    final state = list();
    final place = state.position.pixels;
    expect(place, greaterThan(300));

    // Opened: the same list where it was, nothing loading.
    await tester.tap(find.byKey(const ValueKey('event_view_search_fab')));
    await tester.pump();
    expect(list(), same(state));
    expect(list().position.pixels, place);
    await tester.pumpAndSettle();
    expect(list(), same(state));
    expect(list().position.pixels, place);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // Typed: while the results load, the last list stays (no skeleton, no
    // spinner) under a quiet progress line.
    await tester.enterText(
      find.byKey(const ValueKey('collection_games_search')),
      'Nimzowitsch',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.pending, hasLength(1));
    expect(list(), same(state));
    expect(list().position.pixels, place);
    expect(find.byType(GameCard), findsWidgets);
    expect(find.byType(SkeletonWidget), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // The hits land at the top of the same list.
    repo.release();
    await tester.pumpAndSettle();
    expect(list(), same(state));
    expect(list().position.pixels, 0);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // Closed: the full list again, back where the reader left it, from the
    // first frame (never a frame of its top first).
    await tester.tap(find.byKey(const ValueKey('event_view_search_close')));
    await tester.pump();
    expect(list(), same(state));
    expect(list().position.pixels, closeTo(place, 0.5));
    await tester.pumpAndSettle();
    expect(list(), same(state));
    expect(list().position.pixels, closeTo(place, 0.5));
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('the Collections catalog keeps its list through a search: no '
      'spinner, no remount, its place kept', (tester) async {
    final books = [
      for (var i = 0; i < 40; i++)
        Collection(
          id: 'book-$i',
          slug: 'book-$i',
          kind: CollectionKind.book,
          title: 'Book number $i',
          access: CollectionAccess.free,
        ),
    ];
    final repo = _SlowBooks(detail: books.first, games: const [], list: books);
    await _pump(
      tester,
      repo,
      size: const Size(390, 844),
      home: const CollectionsScreen(),
    );
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(CollectionCatalogList<Collection>),
      matching: find.byType(Scrollable),
    );
    ScrollableState list() => tester.state<ScrollableState>(scrollable);
    final spinner = find.byType(CircularProgressIndicator);
    final line = find.byKey(const ValueKey('games_list_refetch_line'));
    await tester.drag(scrollable, const Offset(0, -900));
    await tester.pumpAndSettle();
    // A little back up brings the header and the search button back.
    await tester.drag(scrollable, const Offset(0, 120));
    await tester.pumpAndSettle();
    final state = list();
    final place = state.position.pixels;
    expect(place, greaterThan(500));
    final browsed = repo.bookQueries.length;

    await _openSearch(tester);
    expect(list(), same(state));
    expect(list().position.pixels, place);

    // Typed: the rows stay where they are under the quiet line while the
    // hits are on their way.
    await tester.enterText(
      find.byKey(const ValueKey('collections_search')),
      'number 1',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 120));
    expect(repo.pending, hasLength(1));
    expect(list(), same(state));
    expect(list().position.pixels, place);
    expect(find.byType(CollectionCard), findsWidgets);
    expect(spinner, findsNothing);
    expect(line, findsOneWidget);

    // The hits land at the top of the same list.
    repo.release();
    await tester.pump();
    expect(list(), same(state));
    expect(list().position.pixels, 0);
    await tester.pumpAndSettle();
    expect(line, findsNothing);
    expect(find.text('Book number 2'), findsNothing);
    expect(find.text('Book number 1'), findsOneWidget);

    // Closed: every book again, at once and where the reader left them,
    // with no request and nothing loading, in any frame.
    await tester.tap(find.byKey(const ValueKey('event_view_search_close')));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(spinner, findsNothing, reason: 'frame $frame');
      expect(line, findsNothing, reason: 'frame $frame');
      expect(list(), same(state), reason: 'frame $frame');
      expect(
        list().position.pixels,
        closeTo(place, 0.5),
        reason: 'frame $frame',
      );
    }
    await tester.pumpAndSettle();
    expect(repo.bookQueries.skip(browsed).map((query) => query.text), [
      'number 1',
    ]);
    expect(
      tester
          .widgetList<CollectionCard>(find.byType(CollectionCard))
          .map((card) => card.collection.title),
      contains(isNot(contains('number 1'))),
    );
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('a list read to its end settles with the morph: the search '
      "button's room gives way with the button, never in one jump", (
    tester,
  ) async {
    // A list just longer than the page: too short for the bars to leave,
    // so the reader at its very end still has the search button.
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'short-book',
        slug: 'short-book',
        kind: CollectionKind.book,
        title: 'Short book',
        access: CollectionAccess.free,
      ),
      games: [for (var i = 0; i < 8; i++) _game('g$i')],
    );
    await _pump(tester, repo, size: const Size(390, 844), premium: true);
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byKey(const PageStorageKey('collection_games')),
      matching: find.byType(Scrollable),
    );
    ScrollPosition position() =>
        tester.state<ScrollableState>(scrollable).position;
    final gap = find.byType(EventViewSearchButtonGap);
    double room() => tester.getSize(gap).height;
    final fab = find.byKey(const ValueKey('event_view_search_fab'));
    await tester.drag(scrollable, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(position().pixels, position().maxScrollExtent);
    expect(
      position().maxScrollExtent,
      inExclusiveRange(
        EventViewSearchButtonGap.extent,
        ScrollChromeController.minScrollRange,
      ),
    );
    expect(fab.hitTestable(), findsOneWidget);
    expect(room(), EventViewSearchButtonGap.extent);

    await tester.tap(fab);
    var last = position().pixels;
    var lastRoom = room();
    var steps = 0;
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = position().pixels;
      final nowRoom = room();
      // The room shrinks a little each frame, and the list with it.
      expect(nowRoom, lessThanOrEqualTo(lastRoom), reason: 'frame $frame');
      if (nowRoom < lastRoom) steps++;
      expect(
        (now - last).abs(),
        lessThan(EventViewSearchButtonGap.extent / 2),
        reason: 'frame $frame',
      );
      last = now;
      lastRoom = nowRoom;
    }
    await tester.pumpAndSettle();
    expect(room(), 0);
    expect(steps, greaterThan(3));

    // Closed, it grows back.
    await tester.tap(find.byKey(const ValueKey('event_view_search_close')));
    await tester.pumpAndSettle();
    position().jumpTo(position().maxScrollExtent);
    await tester.pump();
    expect(room(), EventViewSearchButtonGap.extent);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('the hits keep the Games list order, newest first, as the '
      'list read before the search', (tester) async {
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'order-book',
        slug: 'order-book',
        kind: CollectionKind.book,
        title: 'Order book',
        access: CollectionAccess.free,
      ),
      // Filed oldest first, the order the server answers a search in.
      games: [
        _game('old', playedOn: DateTime(2020, 3, 1)),
        _game('mid', playedOn: DateTime(2022, 3, 1)),
        _game('new', playedOn: DateTime(2024, 3, 1)),
      ],
    );
    await _pump(tester, repo, premium: true);
    await tester.pumpAndSettle();
    List<String> rows() => [
      for (final row in tester.widgetList<DiscoveryGameList>(
        find.byType(DiscoveryGameList),
      ))
        row.games[row.start].gameId,
    ];
    expect(rows(), ['new', 'mid', 'old']);

    await _openSearch(tester);
    await tester.enterText(
      find.byKey(const ValueKey('collection_games_search')),
      'Nimzowitsch',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(repo.filteredQueries.last.query.text, 'Nimzowitsch');
    expect(rows(), ['new', 'mid', 'old']);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('tapping the open tab again takes its list back to the top', (
    tester,
  ) async {
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'long-book',
        slug: 'long-book',
        kind: CollectionKind.book,
        title: 'Long book',
        access: CollectionAccess.free,
      ),
      games: [for (var i = 0; i < 30; i++) _game('g$i')],
    );
    await _pump(tester, repo, size: const Size(390, 844), premium: true);
    await tester.pumpAndSettle();
    final strip = find.byType(SegmentedSwitcher);
    expect(tester.widget<SegmentedSwitcher>(strip).currentSelection, 1);
    final list = find.byType(Scrollable).hitTestable().last;
    double offset() => tester.state<ScrollableState>(list).position.pixels;
    await tester.drag(list, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(300));

    // Scrolling back a little brings the tabs in, far from the list's top.
    await tester.drag(list, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(150));
    await tester.tap(find.text('Games').first);
    await tester.pumpAndSettle();
    expect(offset(), 0);
    expect(tester.widget<SegmentedSwitcher>(strip).currentSelection, 1);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  // Paused Openings tab regression, retained with its implementation.
  //   testWidgets(
  //     'book tabs slide to About and opening taps show only that book opening games',
  //     (tester) async {
  //       await tester.binding.setSurfaceSize(const Size(390, 844));
  //       addTearDown(() => tester.binding.setSurfaceSize(null));
  //       final repo = _FakeCollections(
  //         detail: const Collection(
  //           id: 'book',
  //           slug: 'book',
  //           kind: CollectionKind.book,
  //           title: 'Opening book',
  //           access: CollectionAccess.free,
  //         ),
  //         games: [
  //           _game('sicilian', eco: 'B20', playedOn: DateTime(2026, 8, 29)),
  //           _game('ruy', eco: 'C60', playedOn: DateTime(2026, 8, 30)),
  //         ],
  //         openings: const [
  //           CollectionOpening(eco: 'B20', gameCount: 1),
  //           CollectionOpening(eco: 'C60', gameCount: 1),
  //         ],
  //       );
  //       await _pump(tester, repo, size: const Size(390, 844));
  //       await tester.pumpAndSettle();
  //       final strip = find.byType(SegmentedSwitcher);
  //       final switcher = tester.widget<SegmentedSwitcher>(strip);
  //       expect(switcher.options, ['About', 'Openings', 'Games', 'Players']);
  //       expect(switcher.isScrollable, isTrue);
  //       expect(switcher.currentSelection, 2);
  //       final tabScroller = find.descendant(
  //         of: strip,
  //         matching: find.byType(SingleChildScrollView),
  //       );
  //       ScrollController tabScroll() =>
  //           tester.widget<SingleChildScrollView>(tabScroller).controller!;
  //       expect(
  //         tabScroll().offset,
  //         closeTo(tabScroll().position.maxScrollExtent, 0.01),
  //       );
  //       await tester.tap(find.text('Openings').first);
  //       await tester.pumpAndSettle();
  //       expect(tabScroll().offset, closeTo(0, 0.01));
  //       expect(repo.openingSlugs, contains('book'));
  //       expect(
  //         find.byKey(const ValueKey('collection_opening_all')),
  //         findsNothing,
  //       );
  //       for (final category in ['A', 'D', 'E']) {
  //         expect(
  //           find.byKey(ValueKey('collection_opening_category_$category')),
  //           findsNothing,
  //         );
  //       }
  //       for (final category in ['B', 'C']) {
  //         expect(
  //           find.byKey(ValueKey('collection_opening_category_$category')),
  //           findsOneWidget,
  //         );
  //       }
  //       await tester.tap(find.text('About').first);
  //       await tester.pumpAndSettle();
  //       expect(tester.widget<SegmentedSwitcher>(strip).currentSelection, 0);
  //       await tester.tap(find.text('Games').first);
  //       await tester.pumpAndSettle();
  //       expect(
  //         tabScroll().offset,
  //         closeTo(tabScroll().position.maxScrollExtent, 0.01),
  //       );
  //       await tester.tap(find.text('Players').first);
  //       await tester.pumpAndSettle();
  //       expect(
  //         tabScroll().offset,
  //         closeTo(tabScroll().position.maxScrollExtent, 0.01),
  //       );
  //       await tester.tap(find.text('Openings').first);
  //       await tester.pumpAndSettle();
  //       await tester.tap(
  //         find.byKey(const ValueKey('collection_opening_category_B')),
  //       );
  //       await tester.pumpAndSettle();
  //       final opening = find.byKey(const ValueKey('collection_opening_B20'));
  //       for (var depth = 0; depth < 8 && opening.evaluate().isEmpty; depth++) {
  //         final closed = find.byWidgetPredicate(
  //           (w) =>
  //               w is TournamentRoundHeader &&
  //               w.key.toString().contains('collection_opening_family_') &&
  //               !w.isExpanded,
  //         );
  //         await tester.ensureVisible(closed.first);
  //         await tester.tap(closed.first);
  //         await tester.pumpAndSettle();
  //       }
  //       expect(opening, findsOneWidget);
  //       expect(
  //         find.descendant(of: opening, matching: find.text('1 game')),
  //         findsOneWidget,
  //       );
  //       await tester.ensureVisible(opening);
  //       await tester.tap(opening);
  //       await tester.pumpAndSettle();
  //       expect(repo.filteredSlugs.last, 'book');
  //       expect(repo.filteredQueries.last.query.eco, 'B20');
  //       expect(repo.filteredQueries.last.player, isNull);
  //       expect(find.byType(GameCard), findsOneWidget);
  //       expect(find.text('29 Aug 2026'), findsOneWidget);
  //       final dateHeader = find.byWidgetPredicate(
  //         (w) => w is TournamentRoundHeader && w.subtitle == '29 Aug 2026',
  //       );
  //       await tester.tap(dateHeader);
  //       await tester.pumpAndSettle();
  //       expect(find.byType(GameCard), findsNothing);
  //       await tester.pageBack();
  //       await tester.pumpAndSettle();
  //       expect(opening, findsOneWidget);
  //       expect(tester.widget<SegmentedSwitcher>(strip).currentSelection, 1);
  //       expect(tester.takeException(), isNull);
  //       await _teardown(tester);
  //     },
  //   );
  //

  testWidgets('book About is visible beside Games and Players', (tester) async {
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'book',
        slug: 'book',
        kind: CollectionKind.book,
        title: 'Opening book',
        about: 'A collection of opening studies.',
        access: CollectionAccess.free,
      ),
      games: [_game('one')],
      players: const [
        CollectionPlayer(
          key: 'name:nimzowitsch, aron',
          name: 'Nimzowitsch, Aron',
          games: 1,
        ),
      ],
    );
    await _pump(tester, repo, size: const Size(390, 844), textScale: 2);
    await tester.pumpAndSettle();
    final strip = find.byType(SegmentedSwitcher);
    final switcher = tester.widget<SegmentedSwitcher>(strip);
    expect(switcher.options, ['About', 'Games', 'Players']);
    expect(switcher.isScrollable, isFalse);
    expect(switcher.currentSelection, 1);
    expect(find.text('Openings'), findsNothing);
    expect(find.byType(GameCard), findsOneWidget);
    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    expect(find.text('A collection of opening studies.'), findsOneWidget);
    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();
    expect(find.byType(FigmaPlayerCard), findsOneWidget);
    await tester.tap(find.text('Games').first);
    await tester.pumpAndSettle();
    expect(find.byType(GameCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets(
    'preserved opening catalog discloses families and authors open their collections',
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
      await _pump(
        tester,
        repo,
        home: EventViewShell(
          title: 'Preserved opening catalog',
          tabs: const ['Openings', 'Authors'],
          pageBuilder: (_, index) => index == 0
              ? const CollectionOpeningCatalog(query: CollectionSearchQuery())
              : const CollectionAuthorsCatalog(query: CollectionSearchQuery()),
        ),
      );
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
        find.descendant(of: opening, matching: find.text('1 collection')),
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
        findsNWidgets(2), // Rank 1 and one collection.
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

  for (final light in [false, true]) {
    testWidgets(
      'author cards open Collections and title opens About in ${light ? 'light' : 'dark'} theme',
      (tester) async {
        const authorId = 'account:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        final repo = _FakeCollections(
          detail: const Collection(
            id: 'author-book',
            slug: 'author-book',
            kind: CollectionKind.book,
            title: 'Authored collection',
            access: CollectionAccess.free,
          ),
          games: [],
          authors: const [
            CollectionAuthor(
              id: authorId,
              name: 'Test Author',
              about: 'I write about chess.\n\nI annotate my own games.',
              bookCount: 1,
            ),
          ],
        );
        await _pump(
          tester,
          repo,
          light: light,
          textScale: 2,
          size: const Size(390, 844),
          home: const CollectionsScreen(),
        );
        await tester.tap(find.text('Authors').first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'author catalog layout');
        final card = find.byType(FigmaPlayerCard);
        await tester.tapAt(
          tester.getRect(card).bottomRight - const Offset(20, 20),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'author detail collections layout',
        );
        final strip = find.byType(SegmentedSwitcher);
        expect(tester.widget<SegmentedSwitcher>(strip).options, [
          'About',
          'Collections',
        ]);
        expect(tester.widget<SegmentedSwitcher>(strip).currentSelection, 1);
        expect(find.byType(CollectionCard), findsOneWidget);
        expect(repo.bookQueries.last.authorId, authorId);
        expect(repo.bookQueries.last.author, isEmpty);
        final title = find.byKey(const ValueKey('event_view_title_action'));
        expect(tester.getSize(title).height, greaterThanOrEqualTo(44));
        await tester.tap(title);
        await tester.pumpAndSettle();
        expect(tester.widget<SegmentedSwitcher>(strip).currentSelection, 0);
        expect(find.text('I write about chess.'), findsOneWidget);
        expect(find.text('I annotate my own games.'), findsOneWidget);
        await tester.tap(find.text('Collections').first);
        await tester.pumpAndSettle();
        expect(find.byType(CollectionCard), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      },
    );
  }

  for (final kind in [CollectionKind.book, CollectionKind.analysis]) {
    testWidgets('${kind.name} author credit opens the shared author About', (
      tester,
    ) async {
      const authorId = 'account:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final repo = _FakeCollections(
        detail: Collection(
          id: 'book',
          slug: 'book',
          kind: kind,
          title: 'Authored collection',
          author: 'Test Author',
          authorId: authorId,
          authorBio: 'Editorial biography for this collection.',
          access: CollectionAccess.free,
        ),
        games: [],
        authors: const [
          CollectionAuthor(
            id: authorId,
            name: 'Test Author',
            about: 'Shared public author description.',
            bookCount: 1,
          ),
        ],
      );
      await _pump(tester, repo);
      await tester.tap(find.text('About').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Editorial biography for this collection.'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('collection_author_credit_book')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedSwitcher>(find.byType(SegmentedSwitcher))
            .currentSelection,
        0,
      );
      expect(find.text('Shared public author description.'), findsOneWidget);
      expect(
        find.text('Editorial biography for this collection.'),
        findsNothing,
      );
      await tester.tap(find.text('Collections').first);
      await tester.pumpAndSettle();
      expect(repo.bookQueries.last.authorId, authorId);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.text('Editorial biography for this collection.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });
  }

  test(
    'author About parses separately from collection editorial biographies',
    () {
      final author = CollectionAuthor.fromJson({
        'id': 'credit:one',
        'name': 'Test Author',
        'about': '  Public biography.  ',
      });
      expect(author.about, 'Public biography.');
      expect(
        CollectionAuthor.fromJson({'name': 'Legacy author'}).about,
        isNull,
      );
      expect(
        Collection.fromJson({
          'id': 'one',
          'title': 'A collection',
          'authorId': 'credit:one',
        }).authorId,
        'credit:one',
      );
    },
  );

  test(
    'legacy author credits distinguish namesakes by collection membership',
    () async {
      const first = CollectionAuthor(
        id: 'account:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        name: 'Same Name',
        about: 'First author.',
      );
      const second = CollectionAuthor(
        id: 'account:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        name: 'Same Name',
        about: 'Second author.',
      );
      const book = Collection(
        id: 'book',
        slug: 'book',
        kind: CollectionKind.book,
        title: 'Correct author collection',
      );
      final repo = _FakeCollections(
        detail: book,
        games: [],
        authors: [first, second],
        booksByAuthor: {
          first.id: [],
          second.id: [book],
        },
      );
      final container = ProviderContainer(
        overrides: [collectionsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final author = await container.read(
        collectionAuthorProfileProvider((
          id: 'Same Name',
          name: 'Same Name',
          collectionSlug: 'book',
        )).future,
      );
      expect(author?.id, second.id);
      expect(author?.about, 'Second author.');
      expect(repo.bookQueries.map((query) => query.authorId), [
        first.id,
        second.id,
      ]);
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
      expect(find.text('2 games'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(FigmaPlayerCard),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(find.text('0'), findsNothing);
      await tester.tap(find.byType(FigmaPlayerCard));
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsNWidgets(2));
      expect(find.text('29 Aug 2026'), findsOneWidget);
      expect(repo.filteredQueries.last.player, 'fide:1');
      // The player's games search behind their floating button.
      expect(
        find.byKey(const ValueKey('event_view_search_fab')),
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
      // The round selector: whatever it draws inside (the glass drop-down
      // since the popup sweep), the round picker is tapped.
      await tester.tap(find.byType(TextDropDownWidget));
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
      expect(field, findsNothing);
      await _openSearch(tester);
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
    testWidgets('the Collections tab is a root: the bar every root wears, its '
        'pages as the bar\'s tabs, no way back, at ${size.width.toInt()}dp '
        'and ${textScale}x text', (tester) async {
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
        home: const CollectionsScreen(embedded: true),
      );

      expect(find.byType(CollectionsRoot), findsOneWidget);
      expect(find.byType(HomeTopBarFrame), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.byType(PageBackButton), findsNothing);
      // Home's composition: the pages are the bar's tabs, in the root
      // title voice; no segmented strip under a title.
      expect(find.byType(SegmentedSwitcher), findsNothing);
      final tabs = tester.widget<ForYouPageTabs>(find.byType(ForYouPageTabs));
      expect(tabs.labels, ['About', 'Collections', 'Authors']);
      expect(tabs.selectedIndex, CollectionsTab.collections.index);

      final context = tester.element(find.byType(HomeTopBarFrame));
      final bar = tester.getRect(find.byType(ForYouPageTabs));
      // On the centre line every root's title sits on, and the pages start
      // where every root's page starts.
      expect(
        bar.center.dy,
        closeTo(
          HomeTopBarMetrics.topInset(context) +
              HomeTopBarMetrics.rowExtent(context) / 2,
          0.5,
        ),
      );
      expect(
        tester.getTopLeft(find.byType(PageView)).dy,
        closeTo(HomeTopBarMetrics.headerExtent(context), 0.5),
      );
      expect(bar.left, closeTo(HomeTopBarMetrics.horizontalPadding, 0.5));
      expect(
        bar.right,
        closeTo(size.width - HomeTopBarMetrics.horizontalPadding, 0.5),
      );
      // The catalog's search floats over it.
      expect(
        find.byKey(const ValueKey('event_view_search_fab')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });
  }

  testWidgets('the dock\'s Collections slot opens the Collections root', (
    tester,
  ) async {
    final repo = _FakeCollections(
      detail: const Collection(
        id: 'dock-book',
        slug: 'dock-book',
        kind: CollectionKind.book,
        title: 'Dock book',
        access: CollectionAccess.free,
      ),
      games: const [],
      list: const [
        Collection(
          id: 'dock-book',
          slug: 'dock-book',
          kind: CollectionKind.book,
          title: 'Dock book',
          access: CollectionAccess.free,
        ),
      ],
    );
    await _pump(
      tester,
      repo,
      size: const Size(393, 852),
      overrides: [
        botvinnikTabAvailableProvider.overrideWithValue(false),
        selectedBottomNavBarItemProvider.overrideWith(
          (ref) => BottomNavBarItem.collections,
        ),
      ],
      home: const Scaffold(body: BottomNavBarView()),
    );
    expect(find.byType(CollectionsRoot), findsOneWidget);
    expect(find.byKey(e2eKey(E2eIds.collectionsRoot)), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('Dock book'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('re-tapping the Collections slot takes the open page back to '
      'its top, bars and all', (tester) async {
    final books = [
      for (var i = 0; i < 25; i++)
        Collection(
          id: 'retap-$i',
          slug: 'retap-$i',
          kind: CollectionKind.book,
          title: 'Re-tap studies $i',
          access: CollectionAccess.free,
        ),
    ];
    final repo = _FakeCollections(
      detail: books.first,
      games: const [],
      list: books,
    );
    await _pump(
      tester,
      repo,
      size: const Size(390, 844),
      home: const CollectionsScreen(embedded: true),
    );
    final list = find.descendant(
      of: find.byType(PageView),
      matching: find.byType(ListView),
    );
    await tester.drag(list, const Offset(0, -700));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final scroll = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(scroll.pixels, greaterThan(200));
    expect(find.text('About').hitTestable(), findsNothing);

    ProviderScope.containerOf(tester.element(find.byType(CollectionsRoot)))
        .read(bottomNavBarReTapRequestProvider.notifier)
        .request(BottomNavBarItem.collections);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    // On its way, not there in one frame.
    expect(scroll.pixels, greaterThan(0));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.pixels, moreOrLessEquals(0, epsilon: 0.5));
    expect(find.text('About').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('the root\'s search opens in the bar\'s place, on its centre '
      'line, and closes as the reader leaves the section', (tester) async {
    const book = Collection(
      id: 'root-search',
      slug: 'root-search',
      kind: CollectionKind.book,
      title: 'Root search book',
      access: CollectionAccess.free,
    );
    final repo = _FakeCollections(
      detail: book,
      games: const [],
      list: const [book],
    );
    await _pump(
      tester,
      repo,
      size: const Size(393, 852),
      overrides: [
        selectedBottomNavBarItemProvider.overrideWith(
          (ref) => BottomNavBarItem.collections,
        ),
      ],
      home: const CollectionsScreen(embedded: true),
    );
    final bar = tester.getRect(find.byType(ForYouPageTabs));
    await _openSearch(tester);
    final field = find.byKey(const ValueKey('collections_search'));
    expect(field, findsOneWidget);
    expect(
      tester.getRect(find.byType(SimpleSearchBar)).center.dy,
      closeTo(bar.center.dy, 1),
    );
    // The catalog's filters stand beside the field.
    expect(find.byKey(const ValueKey('collections_filters')), findsOneWidget);
    // The page under it did not move.
    final context = tester.element(find.byType(CollectionsRoot));
    expect(
      tester.getTopLeft(find.byType(PageView)).dy,
      closeTo(HomeTopBarMetrics.headerExtent(context), 1),
    );

    ProviderScope.containerOf(
          context,
        ).read(selectedBottomNavBarItemProvider.notifier).state =
        BottomNavBarItem.forYou;
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(find.byType(ForYouPageTabs).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

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

        await tester.tap(find.bySemanticsLabel(BoardViewToggleButton.label));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(GameCard), findsNothing);
        expect(find.byType(GridChessBoardFromFENNew), findsNWidgets(2));

        await tester.tap(find.bySemanticsLabel(BoardViewToggleButton.label));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(GridChessBoardFromFENNew), findsNothing);
        expect(find.byType(ChessBoardFromFENNew), findsNWidgets(2));

        await tester.tap(find.bySemanticsLabel(BoardViewToggleButton.label));
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
    'primary Collections shows three tabs that scroll away with the list',
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
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Openings'), findsNothing);
      expect(find.text('Authors'), findsOneWidget);
      // The tab, on the bar: the root names itself by its pages.
      expect(find.text('Collections'), findsOneWidget);
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
      // The header and the tabs went up with the list...
      expect(find.text('About').hitTestable(), findsNothing);
      // ...and come back first as it scrolls back down.
      await tester.drag(list, const Offset(0, 300));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('About').hitTestable(), findsOneWidget);
      expect(scroll.pixels, greaterThan(0));
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      expect(find.text('About collections'), findsOneWidget);
      expect(repo.openingSlugs, isEmpty);
      await tester.tap(find.text('Collections').last);
      await tester.pumpAndSettle();
      expect(find.byType(CollectionCard), findsWidgets);
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

  group('a collection card opens once, with one haptic, however it opens', () {
    late List<String> haptics;

    setUp(() {
      haptics = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add('${call.arguments}');
            }
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    const book = Collection(
      id: 'c9',
      slug: 'zurich-1953',
      kind: CollectionKind.book,
      title: 'Zurich 1953',
      gameCount: 210,
      contentLocked: false,
    );

    // A tap plays the card's own tap; the menu's Open row only the menu's
    // selection tick; the lifted copy nothing more. Each open is reported
    // once, so My Space records every one of them.
    for (final (way, expected) in [
      ('a tap', ['HapticFeedbackType.lightImpact']),
      ('the menu\'s Open row', ['HapticFeedbackType.lightImpact']),
      ('the lifted copy', <String>[]),
    ]) {
      testWidgets('by $way', (tester) async {
        var opened = 0;
        await _pump(
          tester,
          _FakeCollections(detail: book, games: [_game('a')]),
          size: const Size(390, 844),
          overrides: [spaceShortcutsProvider.overrideWith(_NoShortcuts.new)],
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: CollectionCard(
                collection: book,
                showStar: false,
                onOpened: () => opened++,
              ),
            ),
          ),
        );
        if (way != 'a tap') {
          await tester.longPress(find.byType(CollectionCard));
          await tester.pump(const Duration(milliseconds: 600));
        }
        haptics.clear();
        switch (way) {
          case 'a tap':
            await tester.tap(find.byType(CollectionCard));
          case 'the menu\'s Open row':
            await tester.tap(find.text('Open'));
          default:
            // The copy lifted over the page (drawn inert: the menu takes
            // its tap), not the hidden original.
            await tester.tap(
              find.text('Zurich 1953').last,
              warnIfMissed: false,
            );
        }
        await tester.pump();
        expect(haptics, expected);
        expect(opened, 1);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        expect(find.byType(CollectionScreen), findsOneWidget);
        expect(opened, 1);
        await _teardown(tester);
      });
    }
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

  testWidgets(
    'book games stay flat and preserve response order across sections',
    (tester) async {
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
            _game('a', sectionId: 'ch7', orderIndex: 2),
            _game('unsectioned', orderIndex: 0),
            _game('b', sectionId: 'ch7', orderIndex: 1),
          ],
        ),
      );

      // Paused book chapter presentation:
      // expect(_rich('The Elements'), findsOneWidget);
      // expect(_rich('Part I'), findsOneWidget);
      // expect(_rich('Chapter 7: The Pin'), findsOneWidget);
      // expect(find.text('A pinned piece cannot move.'), findsOneWidget);
      // expect(find.text('Exploit it.'), findsOneWidget);
      expect(find.byType(TournamentRoundHeader), findsNothing);
      expect(_rich('The Elements'), findsNothing);
      expect(_rich('Chapter 7: The Pin'), findsNothing);
      expect(find.text('A pinned piece cannot move.'), findsNothing);
      final rows = tester
          .widgetList<DiscoveryGameList>(find.byType(DiscoveryGameList))
          .toList();
      expect(rows, hasLength(3));
      expect(
        [for (final row in rows) row.games[row.start].gameId],
        ['a', 'unsectioned', 'b'],
      );
      expect(rows.last.games.map((game) => game.gameId), [
        'a',
        'unsectioned',
        'b',
      ]);
      expect(_rich('Nothing here yet'), findsNothing);
      expect(find.text('Casual'), findsNothing);
      await _teardown(tester);
    },
  );

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

  group('tapping a "new games" collection push, through the notification '
      'router', () {
    const book = Collection(
      id: '36092ff4-126c-4c24-b989-f9078472266d',
      slug: 'us-chess-championships',
      kind: CollectionKind.book,
      title: 'US Chess Championships',
      access: CollectionAccess.free,
    );

    /// The app, and the tap of the push onesignal-dispatch sends.
    Future<void> tapPush(
      WidgetTester tester,
      _FakeCollections repo, {
      Map<String, String> extra = const {},
    }) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      late WidgetRef captured;
      DeepLinkService.instance.dispose();
      addTearDown(DeepLinkService.instance.detachNotificationRouter);
      addTearDown(DeepLinkService.instance.dispose);
      // Home is a Scaffold, so a snack raised over it has somewhere to show.
      const host = Scaffold(body: SizedBox.shrink());
      await _pump(
        tester,
        repo,
        home: host,
        rootRef: (ref) => captured = ref,
        navigatorKey: navigatorKey,
        onGenerateRoute: (settings) =>
            MaterialPageRoute<void>(settings: settings, builder: (_) => host),
        // A push opens for a reader with a session (a guest's too).
        overrides: [signedInAuthOverride()],
      );
      DeepLinkService.instance.attachNotificationRouter(navigatorKey, captured);
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.ingestNotificationData({
        'type': 'collection_games_added',
        'collection_slug': 'us-chess-championships',
        ...extra,
        // Added by the notification service on the way to the phone.
        'url': '',
        'delivery_id': '5b1c9f0e-0d1a-4c7e-9a52-0f3c6d2e8a11',
        'campaign_id': '856a94b6-a8e3-4529-9abb-b344b431c8bd',
      });
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('a published collection opens', (tester) async {
      final repo = _FakeCollections(detail: book, games: [_game('a')]);
      await tapPush(tester, repo);
      final screen = tester.widget<CollectionScreen>(
        find.byType(CollectionScreen),
      );
      expect(screen.collection.slug, 'us-chess-championships');
      expect(screen.collection.id, book.id);
      expect(find.text('US Chess Championships'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });

    testWidgets('the count the push announced is said again once it is open', (
      tester,
    ) async {
      final repo = _FakeCollections(detail: book, games: [_game('a')]);
      await tapPush(
        tester,
        repo,
        extra: const {
          'added': '4',
          'collection_title': 'US Chess Championships',
        },
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CollectionScreen), findsOneWidget);
      expect(
        find.text('4 new games just landed in US Chess Championships.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });

    testWidgets('one that cannot be read lands on Home, not a broken page', (
      tester,
    ) async {
      await tapPush(
        tester,
        _UnreadableCollection(detail: book, games: []),
        extra: const {'collection_title': 'US Chess Championships'},
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CollectionScreen), findsNothing);
      expect(
        find.text('US Chess Championships could not be opened right now.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });

    testWidgets('Try again opens it once it can be read', (tester) async {
      await tapPush(
        tester,
        _UnreadableCollection(detail: book, games: [_game('a')], failures: 1),
        extra: const {'added': '2'},
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CollectionScreen), findsNothing);
      await tester.tap(find.text('Try again'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CollectionScreen), findsOneWidget);
      expect(
        find.text('2 new games just landed in US Chess Championships.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });
  });
}
