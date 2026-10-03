// Local deterministic fixtures, NOT live/historical games or installed-device proof.
// Run with --dart-define=PARITY_PREVIEW_DIR=<absolute path> to save real Flutter
// RepaintBoundary captures. Only the external contact-sheet labels differ.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/collections/open_collection_game.dart';
import 'package:chessever2/screens/for_you/discovery/likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/library/widgets/saved_game_actions.dart';
import 'package:chessever2/screens/my_likes/my_likes_hub_screen.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _out = String.fromEnvironment('PARITY_PREVIEW_DIR');
const _platformFonts = String.fromEnvironment('PARITY_PLATFORM_FONTS_DIR');
const _pgn = '''[Event "Local fixture cup"]
[White "Durarbayli, Vasif"]
[Black "Ganguly, S."]
[WhiteTitle "GM"]
[BlackTitle "GM"]
[WhiteElo "2633"]
[BlackElo "2652"]
[WhiteCountry "AZE"]
[BlackCountry "IND"]
[Date "2026.09.28"]
[ECO "C60"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0''';
const _fen =
    'r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4';

CollectionGameCard fixtureCard(int n, {String? pgn}) => CollectionGameCard(
  id: 'fixture-game-$n',
  orderIndex: n,
  white: const CollectionPlayerSide(
    name: 'Durarbayli, Vasif',
    key: 'name:durarbayli, vasif',
    title: 'GM',
    fed: 'AZE',
    elo: 2633,
  ),
  black: CollectionPlayerSide(
    name: n == 1 ? 'Ganguly, S.' : 'Jumabayev, R.',
    key: n == 1 ? 'name:ganguly, s.' : 'name:jumabayev, r.',
    title: 'GM',
    fed: n == 1 ? 'IND' : 'KAZ',
    elo: n == 1 ? 2652 : 2621,
  ),
  result: '1-0',
  playedOn: DateTime(2026, 9, 28),
  event: 'Local fixture cup',
  roundTag: '$n',
  eco: 'C60',
  opening: 'Ruy Lopez',
  finalFen: _fen,
  lastMove: 'a7a6',
  hasAnnotations: true,
  pgn: pgn,
);
final _previews = [
  for (var n = 1; n <= 2; n++) CollectionGame.fromPreviewCard(fixtureCard(n))!,
];
final _saved = [
  for (var n = 1; n <= 2; n++)
    SavedAnalysis(
      id: 'fixture-like-$n',
      userId: 'fixture-viewer',
      folderId: 'fixture-likes',
      title: 'Local fixture $n',
      sourceGameId: 'fixture-game-$n',
      chessGame: ChessGame.fromPgn(
        'fixture-game-$n',
        n == 1
            ? _pgn
            : _pgn
                  .replaceAll('Ganguly, S.', 'Jumabayev, R.')
                  .replaceAll('IND', 'KAZ')
                  .replaceAll('2652', '2621'),
      ),
      analysisState: const {},
      variationComments: const {},
      lastViewedPosition: -1,
      tags: const ['Endgame'],
      isFavorite: false,
      createdAt: DateTime(2026, 9, 28),
      updatedAt: DateTime(2026, 9, 28),
    ),
];
const _players = [
  CollectionPlayer(
    key: 'name:durarbayli, vasif',
    name: 'Durarbayli, Vasif',
    title: 'GM',
    fed: 'AZE',
    bestElo: 2633,
    games: 2,
    wins: 2,
  ),
  CollectionPlayer(
    key: 'name:ganguly, s.',
    name: 'Ganguly, S.',
    title: 'GM',
    fed: 'IND',
    bestElo: 2652,
    games: 1,
    losses: 1,
  ),
  CollectionPlayer(
    key: 'name:jumabayev, r.',
    name: 'Jumabayev, R.',
    title: 'GM',
    fed: 'KAZ',
    bestElo: 2621,
    games: 1,
    losses: 1,
  ),
];

class _NavigationProbe extends NavigatorObserver {
  Route<dynamic>? lastPage;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPage = route;
  }
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(bool paid) : super(SubscriptionState(isSubscribed: paid));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Favorites extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}

class _Settings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _Engine extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Likes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => _saved;
}

class _Library extends Fake implements LibraryRepository {
  @override
  Future<void> ensureDefaultFolders() async {}
}

class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});
  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

/// Models a SAFE METADATA contract. Current backend source gates this contract
/// for Free; the previews deliberately do not claim live backend readiness.
class _Collections extends CollectionsRepository {
  _Collections({
    required this.paid,
    this.freeCollection = false,
    this.denyMetadata = false,
  }) : super(
         GamebaseRepository(
           Dio(),
           baseUrl: 'http://localhost',
           apiKey: 'fixture-key',
         ),
       );
  final bool paid;
  final bool freeCollection;
  final bool denyMetadata;
  int contentReads = 0;
  Collection get detail => Collection(
    id: 'fixture-collection',
    slug: 'fixture-collection',
    kind: CollectionKind.book,
    title: 'Advanced',
    author: 'Local preview fixtures',
    gameCount: 2,
    access: freeCollection ? CollectionAccess.free : CollectionAccess.premium,
    contentLocked: !freeCollection && !paid,
    about: 'Representative local test data. Not historical games.',
  );
  @override
  Future<Collection> fetchCollection(String slug) async => detail;
  @override
  Future<List<CollectionGame>> fetchGames(String slug) async {
    if (denyMetadata) {
      throw const CollectionsRequestException(
        'Metadata gated',
        code: 'premium_required',
      );
    }
    return _previews;
  }

  @override
  Future<List<CollectionPlayer>> fetchPlayers(String slug) async {
    if (denyMetadata) {
      throw const CollectionsRequestException(
        'Metadata gated',
        code: 'premium_required',
      );
    }
    return _players;
  }

  @override
  Future<List<CollectionGame>> fetchPlayableGames(String slug) async {
    contentReads++;
    if (!paid && !freeCollection) {
      throw const CollectionsRequestException(
        'PGN gated',
        code: 'premium_required',
      );
    }
    return [
      for (var n = 1; n <= 2; n++)
        CollectionGame.fromCard(fixtureCard(n, pgn: _pgn))!,
    ];
  }

  @override
  Future<List<CollectionGame>> searchGames(
    String slug,
    CollectionSearchQuery query, {
    String? playerKey,
  }) async => [
    for (final g in await fetchGames(slug))
      if ((playerKey == null || g.card.involves(playerKey)) &&
          (query.text.isEmpty ||
              '${g.card.white.name} ${g.card.black.name}'
                  .toLowerCase()
                  .contains(query.text.toLowerCase())) &&
          (query.eco.isEmpty || g.card.eco == query.eco) &&
          (query.result.isEmpty || g.card.result == query.result))
        g,
  ];
  @override
  Future<List<CollectionOpening>> fetchOpenings({String? slug}) async =>
      const [];
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget screen,
  bool paid, {
  bool light = false,
  GamesListViewMode mode = GamesListViewMode.gamesCard,
  _Collections? repo,
  NavigatorObserver? observer,
  // Whether the My Likes view was derived with every like past the free
  // window. Defaults to the tier; set apart from it to stand in for a view
  // read before the entitlement has re-derived it.
  bool? likesLocked,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  final likes = buildMyLikesData(
    matches: _saved,
    totalLiked: 2,
    window: (likesLocked ?? !paid) ? <String>{} : null,
  );
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(null),
      favoriteEventsProvider.overrideWith(_Favorites.new),
      subscriptionProvider.overrideWith((ref) => _Subscription(paid)),
      collectionsRepositoryProvider.overrideWithValue(
        repo ?? _Collections(paid: paid),
      ),
      libraryRepositoryProvider.overrideWithValue(_Library()),
      boardSettingsProviderNew.overrideWith(_Settings.new),
      engineSettingsProviderNew.overrideWith(_Engine.new),
      gamesListViewModeProvider.overrideWithValue(mode),
      eventNoSpoilersProvider.overrideWith(
        (ref, id) => _NoSpoilers(ref: ref, tourId: id),
      ),
      gameCardEvalCacheOnlyProvider.overrideWith(
        (ref, fen) async => CloudEval(
          fen: fen,
          knodes: 0,
          depth: 0,
          pvs: const [],
          requestedMultiPv: 1,
        ),
      ),
      likedGamesProvider.overrideWith(_Likes.new),
      myLikesViewProvider.overrideWith((ref) async => likes),
      myLikesTagCountsProvider.overrideWith(
        (ref) async => const {'Endgame': 2},
      ),
      playerPhotoProvider.overrideWith((ref, id) async => null),
      mostLikedProvider.overrideWith(
        (ref, query) async => MostLikedResult.ranked([
          for (var n = 0; n < _previews.length; n++)
            MostLikedEntry(
              rank: n + 1,
              likes: 12 - n * 3,
              game: _previews[n].game,
              eventName: 'Local fixture cup',
            ),
        ]),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorObservers: [if (observer != null) observer],
          theme: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
            textTheme: (light ? AppTheme.lightTheme : AppTheme.darkTheme)
                .textTheme
                .apply(fontFamily: 'InterDisplay'),
            primaryTextTheme: (light ? AppTheme.lightTheme : AppTheme.darkTheme)
                .primaryTextTheme
                .apply(fontFamily: 'InterDisplay'),
          ),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return screen;
            },
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  if (screen is CollectionScreen) {
    for (var n = 0; n < mode.index; n++) {
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.label == 'Toggle chessboard view',
        ),
      );
      await _settle(tester);
    }
    final list = find.byType(DiscoveryGameList);
    if (list.evaluate().isNotEmpty) {
      expect(tester.widget<DiscoveryGameList>(list.first).viewMode, mode);
    }
  }
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  for (var n = 0; n < 6; n++) {
    // Asset/image codecs use the real event loop, not FakeAsync's clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 160));
  }
}

Future<void> _selectWeek(WidgetTester tester) async {
  tester
      .widget<DiscoverySegments<MostLikedPeriod>>(
        find.byType(DiscoverySegments<MostLikedPeriod>),
      )
      .onSelect(MostLikedPeriod.week);
  await _settle(tester);
  final c = ProviderScope.containerOf(tester.element(find.byType(LikesScreen)));
  expect(c.read(mostLikedPeriodProvider), MostLikedPeriod.week);
}

Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
  container.dispose();
}

void _noLocks(WidgetTester tester) {
  expect(find.byType(DiscoveryPadlock), findsNothing);
  for (final icon in [
    Icons.lock,
    Icons.lock_outline,
    Icons.lock_rounded,
    Icons.lock_outline_rounded,
  ]) {
    expect(find.byIcon(icon), findsNothing);
  }
  expect(find.textContaining('Read all'), findsNothing);
  expect(find.text('PREMIUM'), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<Uint8List> _capture(WidgetTester tester, String name) async {
  final render = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  final bytes = await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final bytes = data!.buffer.asUint8List();
    if (_out.isNotEmpty) {
      await Directory(_out).create(recursive: true);
      await File('$_out/$name.png').writeAsBytes(bytes);
    }
    return bytes;
  });
  return bytes!;
}

List<String> _structure(WidgetTester tester) => [
  for (final widget in tester.widgetList(
    find.descendant(
      of: find.byKey(const ValueKey('capture')),
      matching: find.byWidgetPredicate((_) => true),
    ),
  ))
    widget.runtimeType.toString(),
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
  'cards:${find.byType(DiscoveryGameList).evaluate().length}',
  'players:${find.byType(FigmaPlayerCard).evaluate().length}',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture-publishable-key',
    );
    // Load bundled app fonts for both names already used by its renderers.
    for (final family in ['InterDisplay', 'Inter']) {
      final font = FontLoader(family);
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        font.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
      }
      await font.load();
    }
    if (_platformFonts.isNotEmpty) {
      // Real SDK Roboto replaces Flutter test's Ahem fallback for RichText
      // fields without a named app font. This is Android-style fixture proof.
      for (final family in ['Roboto', 'Ahem']) {
        final loader = FontLoader(family);
        for (final weight in ['Regular', 'Medium', 'Bold']) {
          loader.addFont(
            File(
              '$_platformFonts/Roboto-$weight.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          );
        }
        await loader.load();
      }
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  // Primary requested visuals plus the existing My Likes hub and Likes Players.
  for (final light in [false, true]) {
    for (final surface in [
      'my-likes',
      'my-likes-games',
      'my-likes-players',
      'likes-games',
      'likes-players',
      'collection-games',
      'collection-players',
    ]) {
      testWidgets(
        '$surface same-data structure and pixels match ${light ? "light" : "dark"}',
        (tester) async {
          addTearDown(tester.view.reset);
          final bytes = <Uint8List>[];
          final structures = <List<String>>[];
          for (final paid in [false, true]) {
            final repo = _Collections(paid: paid);
            final screen = surface == 'my-likes'
                ? const MyLikesScreen()
                : surface.startsWith('my-likes-')
                ? MyLikesHubScreen(
                    initialTab: surface.endsWith('players') ? 1 : 0,
                  )
                : surface.startsWith('likes-')
                ? const LikesScreen()
                : CollectionScreen(collection: repo.detail);
            final container = await _pump(
              tester,
              screen,
              paid,
              light: light,
              repo: repo,
            );
            if (surface == 'likes-games' || surface == 'likes-players') {
              await _selectWeek(tester);
              await _settle(tester);
            }
            if (surface.endsWith('players') &&
                !surface.startsWith('my-likes-')) {
              await tester.tap(find.text('Players'));
              await _settle(tester);
            }
            _noLocks(tester);
            if (surface.endsWith('games')) {
              expect(find.byType(DiscoveryGameList), findsWidgets);
            }
            if (surface.endsWith('players')) {
              expect(find.byType(FigmaPlayerCard), findsWidgets);
            }
            structures.add(_structure(tester));
            bytes.add(
              await _capture(
                tester,
                '$surface-${light ? "light" : "dark"}-${paid ? "premium" : "free"}',
              ),
            );
            expect(
              repo.contentReads,
              0,
              reason: 'browsing must not ask for PGN',
            );
            await _close(tester, container);
          }
          expect(structures[0], structures[1]);
          expect(
            bytes[0],
            orderedEquals(bytes[1]),
            reason: 'only external labels may differ',
          );
        },
      );
    }
  }

  for (final mode in [
    GamesListViewMode.chessBoard,
    GamesListViewMode.chessBoardGrid,
  ]) {
    for (final surface in ['my-likes', 'likes-games', 'collection-games']) {
      testWidgets('$surface ${mode.name} same-data pixels match', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        final captures = <Uint8List>[];
        for (final paid in [false, true]) {
          final repo = _Collections(paid: paid);
          final screen = surface == 'my-likes'
              ? const MyLikesScreen()
              : surface == 'likes-games'
              ? const LikesScreen()
              : CollectionScreen(collection: repo.detail);
          final c = await _pump(tester, screen, paid, repo: repo, mode: mode);
          if (surface == 'likes-games') {
            await _selectWeek(tester);
            await _settle(tester);
          }
          _noLocks(tester);
          captures.add(
            await _capture(
              tester,
              '$surface-${mode.name}-dark-${paid ? "premium" : "free"}',
            ),
          );
          expect(repo.contentReads, 0);
          await _close(tester, c);
        }
        expect(captures[0], orderedEquals(captures[1]));
      });
    }
  }

  testWidgets(
    'restricted My Likes and historical Likes use existing upgrade sheet',
    (tester) async {
      addTearDown(tester.view.reset);
      var container = await _pump(tester, const MyLikesHubScreen(), false);
      final list = tester.widget<DiscoveryGameList>(
        find.byType(DiscoveryGameList).first,
      );
      list.onOpen!(list.games, 0);
      await _settle(tester);
      expect(find.text('Sign in to get Premium'), findsOneWidget);
      await _capture(tester, 'my-likes-restricted-tap-gate');
      Navigator.of(tester.element(find.text('Sign in to get Premium'))).pop();
      await _settle(tester);
      await _close(tester, container);
      container = await _pump(tester, const LikesScreen(), false);
      await _selectWeek(tester);
      await _settle(tester);
      final historical = tester.widget<DiscoveryGameList>(
        find.byType(DiscoveryGameList).first,
      );
      historical.onOpen!(historical.games, 0);
      await _settle(tester);
      expect(find.text('Sign in to get Premium'), findsOneWidget);
      Navigator.of(tester.element(find.text('Sign in to get Premium'))).pop();
      await _settle(tester);
      await _close(tester, container);
    },
  );

  testWidgets('strict shared game guard permits Premium', (tester) async {
    addTearDown(tester.view.reset);
    final c = await _pump(tester, const MyLikesScreen(), true);
    expect(
      await ensurePremiumGameAccess(
        tester.element(find.byType(MyLikesScreen)),
        featureId: 'my_likes_history',
        returnTo: 'my_likes',
      ),
      isTrue,
    );
    await _close(tester, c);
  });

  testWidgets('My Likes hands the board every listed like once access is '
      'granted', (tester) async {
    addTearDown(tester.view.reset);
    final observer = _NavigationProbe();
    // Access was just unlocked, and the view still carries the locks it was
    // derived with: nothing in it counts as openable yet.
    final c = await _pump(
      tester,
      const MyLikesScreen(),
      true,
      observer: observer,
      likesLocked: true,
    );
    expect(c.read(myLikesViewProvider).requireValue.openableAnalyses, isEmpty);
    final initial = observer.lastPage;
    tester.widget<MyLikesGameCard>(find.byType(MyLikesGameCard).at(1)).onOpen();
    await tester.idle();
    expect(observer.lastPage, isNot(same(initial)));
    final route = observer.lastPage as MaterialPageRoute<dynamic>;
    // Inspect only the real navigation payload: do not start native engines.
    final dynamic board = route.builder(
      tester.element(find.byType(MyLikesScreen)),
    );
    // Both likes in page order, opened on the tapped one: not the tapped game
    // alone, which is what the stale openable list used to leave.
    expect((board.games as List).map((dynamic g) => g.likeId), [
      'fixture-game-1',
      'fixture-game-2',
    ]);
    expect(board.currentIndex, 1);
    await _close(tester, c);
  });

  testWidgets(
    'Collection restricted tap asks upgrade without requesting full PGN',
    (tester) async {
      addTearDown(tester.view.reset);
      final repo = _Collections(paid: false);
      final c = await _pump(
        tester,
        CollectionScreen(collection: repo.detail),
        false,
        repo: repo,
      );
      final list = tester.widget<DiscoveryGameList>(
        find.byType(DiscoveryGameList).first,
      );
      list.onOpen!(list.games, 0);
      await _settle(tester);
      expect(find.text('Sign in to get Premium'), findsOneWidget);
      expect(repo.contentReads, 0);
      await _capture(tester, 'collection-restricted-tap-gate');
      Navigator.of(tester.element(find.text('Sign in to get Premium'))).pop();
      await _settle(tester);
      await _close(tester, c);
    },
  );

  for (final paid in [false, true]) {
    testWidgets('allowed Collection tap routes authorized content paid=$paid', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      final repo = _Collections(paid: paid, freeCollection: !paid);
      final observer = _NavigationProbe();
      final c = await _pump(
        tester,
        CollectionScreen(collection: repo.detail),
        paid,
        repo: repo,
        observer: observer,
      );
      final initial = observer.lastPage;
      final list = tester.widget<DiscoveryGameList>(
        find.byType(DiscoveryGameList).first,
      );
      list.onOpen!(list.games, 0);
      await tester.idle();
      expect(observer.lastPage, isNot(same(initial)));
      final route = observer.lastPage as MaterialPageRoute<void>;
      final board =
          route.builder(tester.element(find.byType(CollectionScreen)))
              as ChessBoardScreenNew;
      expect(board.games.map((g) => g.gameId), [
        'fixture-game-1',
        'fixture-game-2',
      ]);
      expect(board.games.every((g) => g.pgn != null), isTrue);
      expect(board.allowGameExport, isFalse);
      expect(repo.contentReads, 1);
      await _close(tester, c);
    });
  }
  for (final paid in [false, true]) {
    testWidgets('allowed Likes tap routes normal board paid=$paid', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      final observer = _NavigationProbe();
      final c = await _pump(
        tester,
        const LikesScreen(),
        paid,
        observer: observer,
      );
      if (paid) {
        await _selectWeek(tester);
        await _settle(tester);
      } else {
        // App default is Month (restricted), not the freely openable Today.
        tester
            .widget<DiscoverySegments<MostLikedPeriod>>(
              find.byType(DiscoverySegments<MostLikedPeriod>),
            )
            .onSelect(MostLikedPeriod.today);
        await _settle(tester);
        expect(c.read(mostLikedPeriodProvider), MostLikedPeriod.today);
      }
      final initial = observer.lastPage;
      final list = tester.widget<DiscoveryGameList>(
        find.byType(DiscoveryGameList).first,
      );
      list.onOpen!(list.games, 0);
      await tester.idle();
      expect(observer.lastPage, isNot(same(initial)));
      final route = observer.lastPage as MaterialPageRoute<int>;
      // Inspect only the real navigation payload: do not start native engines.
      final dynamic board = route.builder(
        tester.element(find.byType(LikesScreen)),
      );
      expect((board.initialGames as List).map((dynamic g) => g.gameId), [
        'fixture-game-1',
        'fixture-game-2',
      ]);
      expect(board.initialIndex, 0);
      expect(find.text('Sign in to get Premium'), findsNothing);
      await _close(tester, c);
    });
  }
  testWidgets('historical Likes Share is gated before PGN resolution', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final c = await _pump(tester, const LikesScreen(), false);
    await _selectWeek(tester);
    await _settle(tester);
    expect(c.read(mostLikedPeriodProvider), MostLikedPeriod.week);
    final list = tester.widget<DiscoveryGameList>(
      find.byType(DiscoveryGameList).first,
    );
    final actions = list.menuActionsFor!(
      tester.element(find.byType(LikesScreen)),
      0,
    );
    expect(actions.map((a) => a.label), containsAll(['Open game', 'Share']));
    actions.singleWhere((a) => a.label == 'Share').onSelected();
    await _settle(tester);
    expect(find.text('Sign in to get Premium'), findsOneWidget);
    Navigator.of(tester.element(find.text('Sign in to get Premium'))).pop();
    await _settle(tester);
    await _close(tester, c);
  });

  testWidgets(
    'metadata denial is honest, no banner/event/name-summary substitutes',
    (tester) async {
      addTearDown(tester.view.reset);
      final repo = _Collections(paid: false, denyMetadata: true);
      final c = await _pump(
        tester,
        CollectionScreen(collection: repo.detail),
        false,
        repo: repo,
      );
      expect(
        find.text("Game previews aren't available from this server yet."),
        findsOneWidget,
      );
      _noLocks(tester);
      await tester.tap(find.text('Players'));
      await _settle(tester);
      expect(
        find.text("Player previews aren't available from this server yet."),
        findsOneWidget,
      );
      expect(find.textContaining('Durarbayli'), findsNothing);
      _noLocks(tester);
      expect(repo.contentReads, 0);
      await _close(tester, c);
    },
  );

  for (final paid in [false, true]) {
    testWidgets(
      'Collection search/filter and player narrowing remain usable paid=$paid',
      (tester) async {
        addTearDown(tester.view.reset);
        final repo = _Collections(paid: paid);
        final c = await _pump(
          tester,
          CollectionScreen(collection: repo.detail),
          paid,
          repo: repo,
        );
        await tester.enterText(find.byType(EditableText), 'Ganguly');
        await tester.pump(const Duration(seconds: 1));
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('book_search_results')),
          findsOneWidget,
        );
        expect(find.byType(DiscoveryGameList), findsOneWidget);
        _noLocks(tester);
        await tester.enterText(find.byType(EditableText), '');
        await _settle(tester);
        await tester.tap(
          find.byKey(const ValueKey('collection_games_filters')),
        );
        await _settle(tester);
        expect(find.textContaining('Filter'), findsWidgets);
        Navigator.of(tester.element(find.textContaining('Filter').first)).pop();
        await _settle(tester);
        await tester.tap(find.text('Players'));
        await _settle(tester);
        expect(find.byType(FigmaPlayerCard), findsNWidgets(3));
        await tester.tap(find.text('Ganguly, S.').first);
        await _settle(tester);
        expect(find.byType(DiscoveryGameList), findsOneWidget);
        _noLocks(tester);
        expect(repo.contentReads, 0);
        await _close(tester, c);
      },
    );
  }

  testWidgets(
    'My Likes menus match and deny copy/edit/move without protected actions',
    (tester) async {
      addTearDown(tester.view.reset);
      final c = await _pump(tester, const MyLikesScreen(), false);
      final context = tester.element(find.byType(MyLikesScreen));
      var gates = 0;
      final actions = savedGameMenuActions(
        context: context,
        analysis: _saved.first,
        onOpen: () {},
        beforeContentAction: () async {
          gates++;
          return false;
        },
        showSpaceAction: false,
        showShareAction: false,
      );
      expect(
        actions.map((a) => a.label),
        containsAll([
          'Open game',
          'Edit & annotate',
          'Copy PGN',
          'Copy FEN',
          'Move to database',
        ]),
      );
      for (final a in actions.where((a) => a.label != 'Open game')) {
        await a.onSelected();
      }
      expect(gates, 4);
      await _close(tester, c);
    },
  );

  test(
    'metadata mapper drops full PGN from both card and game; no invented identity/position',
    () {
      final preview = CollectionGame.fromPreviewCard(
        fixtureCard(1, pgn: _pgn),
      )!;
      expect(preview.game.pgn, isNull);
      expect(preview.card.pgn, isNull);
      expect(preview.game.fen, _fen);
      expect(preview.game.whitePlayer.name, 'Durarbayli, Vasif');
      expect(preview.game.blackPlayer.rating, 2652);
      final absent = CollectionGame.fromPreviewCard(
        const CollectionGameCard(
          id: 'missing-fields',
          white: CollectionPlayerSide(name: 'White', key: 'name:white'),
          black: CollectionPlayerSide(name: 'Black', key: 'name:black'),
        ),
      )!.game;
      expect(absent.fen, isNull);
      expect(absent.whitePlayer.fideId, isNull);
      expect(absent.whitePlayer.title, isEmpty);
    },
  );

  for (final paid in [false, true]) {
    test(
      'authorized Collection opening retains ordered scope paid=$paid',
      () async {
        final repo = _Collections(paid: paid, freeCollection: !paid);
        var prompts = 0;
        final result = await resolvePlayableCollectionGames(
          repository: repo,
          slug: repo.detail.slug,
          visibleIds: ['fixture-game-2', 'fixture-game-1'],
          requestAccess: (_) async {
            prompts++;
            return false;
          },
          stillCurrent: () => true,
        );
        expect(result!.map((g) => g.gameId), [
          'fixture-game-2',
          'fixture-game-1',
        ]);
        expect(result.every((g) => g.pgn != null), isTrue);
        expect(prompts, 0);
        expect(repo.contentReads, 1);
      },
    );
  }
  test('declined Collection guard never fetches protected PGN', () async {
    final repo = _Collections(paid: false);
    final result = await resolvePlayableCollectionGames(
      repository: repo,
      slug: repo.detail.slug,
      visibleIds: ['fixture-game-1'],
      requestAccess: (_) async => false,
      stillCurrent: () => true,
    );
    expect(result, isNull);
    expect(repo.contentReads, 0);
  });
  test(
    'stale Premium is still rejected by server and account changes discard response',
    () async {
      final repo = _Collections(paid: false);
      await expectLater(
        resolvePlayableCollectionGames(
          repository: repo,
          slug: repo.detail.slug,
          visibleIds: ['fixture-game-1'],
          requestAccess: (_) async => true,
          stillCurrent: () => true,
        ),
        throwsA(isA<CollectionsRequestException>()),
      );
      final changed = _Collections(paid: true);
      final result = await resolvePlayableCollectionGames(
        repository: changed,
        slug: changed.detail.slug,
        visibleIds: ['fixture-game-1'],
        requestAccess: (_) async => true,
        stillCurrent: () => false,
      );
      expect(result, isNull);
      expect(changed.contentReads, 0);
    },
  );
}
