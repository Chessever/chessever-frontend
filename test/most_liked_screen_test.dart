import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_game_card.dart';
import 'package:chessever2/screens/my_likes/widgets/date_section_header.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_event_card.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart'
    show SpacePlateArt;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/most_liked_screen.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_controls.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_section.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/board_like_heart.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------- doubles

class _Library extends Fake implements LibraryRepository {
  @override
  Future<void> ensureDefaultFolders() async {}
}

class _Favorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => [
    FavoritePlayer(
      id: 'f1',
      userId: 'u1',
      fideId: '1000',
      playerName: 'White0, Player',
      metadata: const {},
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];

  @override
  Future<void> removeFavorite(
    String playerName, {
    String? fideId,
    String? memorialSourceIdentity,
  }) async {
    state = AsyncData([
      for (final f in state.requireValue)
        if (f.fideId != fideId) f,
    ]);
  }
}

final _savedLike = SavedAnalysis(
  id: 'saved-1',
  userId: 'u1',
  title: 'A saved game',
  chessGame: ChessGame.fromPgn(
    'saved-1',
    '[White "White0, Player"]\n[Black "Black0, Player"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
  ),
  analysisState: const {},
  variationComments: const {},
  lastViewedPosition: -1,
  tags: const [],
  isFavorite: false,
  createdAt: DateTime(2026, 9, 29),
  updatedAt: DateTime(2026, 9, 29),
);

class _SavedLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => [_savedLike];
}

class _EmptyLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => const [];
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(bool subscribed)
    : super(SubscriptionState(isSubscribed: subscribed));

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

const _fen = '6k1/5pp1/7p/3P4/1r6/6P1/5PKP/3R4 w - - 0 38';

PlayerCard _player(String name, int fide) => PlayerCard(
  name: name,
  federation: 'NOR',
  title: 'GM',
  rating: 2800,
  countryCode: 'NO',
  team: null,
  fideId: fide,
);

List<MostLikedEntry> _ranking(int n) => [
  for (var i = 0; i < n; i++)
    MostLikedEntry(
      rank: i + 1,
      likes: 500 - i * 10,
      game: GamesTourModel(
        gameId: 'g$i',
        whitePlayer: _player('White$i, Player', 1000 + i),
        blackPlayer: _player('Black$i, Player', 2000 + i),
        whiteTimeDisplay: '--:--',
        blackTimeDisplay: '--:--',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: GameStatus.whiteWins,
        roundId: 'round-1',
        tourId: 'tour-1',
        fen: _fen,
        lastMove: 'e2e4',
      ),
      eventName: 'Sinquefield Cup 2026',
    ),
];

// ---------------------------------------------------------------- pump

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool subscribed,
  List<MostLikedQuery>? queries,
  Widget home = const MostLikedScreen(),
  List<Override> extra = const [],
  Size size = const Size(390, 6000),
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      subscriptionProvider.overrideWith((ref) => _Subscription(subscribed)),
      playerPhotoProvider.overrideWith((ref, fideId) async => null),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
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
      mostLikedProvider.overrideWith((ref, query) async {
        queries?.add(query);
        return MostLikedResult.ranked(_ranking(12));
      }),
      likedGamesProvider.overrideWith(_EmptyLikes.new),
      favoritePlayersProviderNew.overrideWith(_Favorites.new),
      myLikesViewProvider.overrideWith(
        (ref) async => const MyLikesData(
          sections: [],
          openableAnalyses: [],
          totalLiked: 0,
          visibleCount: 0,
        ),
      ),
      myLikesTagCountsProvider.overrideWith((ref) async => const {}),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  await _mount(
    tester,
    container,
    home,
    phone: Size(size.width, size.height > 2000 ? 844 : size.height),
    textScale: textScale,
    theme: theme,
  );
  return container;
}

Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container,
  Widget home, {
  Size phone = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(size: phone, textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return home;
          },
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-publishable-key',
    );
  });

  for (final tab in ['Games', 'Players']) {
    testWidgets('Likes $tab keeps the period tabs and arrows in view while '
        'its list scrolls', (tester) async {
      final container = await _pump(
        tester,
        subscribed: true,
        home: const LikesScreen(),
        size: const Size(390, 844),
      );
      await tester.tap(find.text(tab).hitTestable());
      await _settle(tester);
      final segments = find.byType(DiscoverySegments<MostLikedPeriod>);
      final date = find.byType(MostLikedDateControl);
      expect(segments.hitTestable(), findsOneWidget);
      expect(date.hitTestable(), findsOneWidget);
      final top = tester.getTopLeft(segments).dy;

      // Fling the list from a point inside it, below the controls.
      await tester.dragFrom(const Offset(195, 700), const Offset(0, -3000));
      await _settle(tester);

      expect(segments.hitTestable(), findsOneWidget);
      expect(date.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(segments).dy, top);
      expect(tester.takeException(), isNull);
      await _teardown(tester, container);
    });
  }
  testWidgets(
    'Likes About opens the standalone archive and keeps ranking period',
    (tester) async {
      final queries = <MostLikedQuery>[];
      final container = await _pump(
        tester,
        subscribed: true,
        home: const LikesScreen(),
        queries: queries,
      );
      expect(queries, isNotEmpty);
      expect(queries.last.period, MostLikedPeriod.month);
      expect(container.read(mostLikedPeriodProvider), MostLikedPeriod.month);
      expect(find.bySemanticsLabel('Most liked, Month'), findsOneWidget);
      expect(
        tester
            .widget<SegmentedSwitcher>(
              find.byKey(const ValueKey('event_view_tabs_About_Games_Players')),
            )
            .currentSelection,
        1,
      );
      await tester.tap(find.text('About').hitTestable());
      await _settle(tester);
      expect(find.byType(MyLikesGamesPage), findsNothing);
      expect(find.byType(DiscoveryEventCard), findsOneWidget);
      final art = tester.getSize(find.byType(SpacePlateArt));
      expect(art.width / art.height, closeTo(5 / 4, 0.001));
      await tester.tap(find.byKey(const ValueKey('discovery_my_likes_card')));
      await _settle(tester);
      expect(find.byType(MyLikesScreen), findsOneWidget);
      expect(find.byType(MyLikesGamesPage), findsOneWidget);
      expect(find.text('About').hitTestable(), findsNothing);
      expect(find.text('No likes yet').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Back').hitTestable());
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Games').hitTestable());
      await _settle(tester);
      expect(queries, isNotEmpty);
      await tester.tap(find.bySemanticsLabel('Most liked, Week'));
      await _settle(tester);
      await tester.tap(find.text('Players').hitTestable());
      await _settle(tester);
      expect(find.text('White0, Player').hitTestable(), findsOneWidget);
      final firstRow = find.byWidgetPredicate(
        (widget) => widget is FigmaPlayerCard && widget.player.fideId == 1000,
      );
      final player = tester.widget<FigmaPlayerCard>(firstRow);
      expect(player.onToggleFavorite, isNotNull);
      expect(player.trailing, isNull);
      expect(player.detail, '500 likes');
      expect(player.isFavorite, isTrue);
      await tester.tap(
        find.descendant(of: firstRow, matching: find.byIcon(Icons.favorite)),
      );
      await _settle(tester);
      expect(container.read(favoritePlayersProviderNew).requireValue, isEmpty);
      expect(tester.widget<FigmaPlayerCard>(firstRow).isFavorite, isFalse);
      expect(tester.widget<FigmaPlayerCard>(firstRow).detail, '500 likes');
      expect(find.text('Games by White0, Player'), findsNothing);
      await tester.tap(find.text('About').hitTestable());
      await _settle(tester);
      await tester.tap(find.text('Players').hitTestable());
      await _settle(tester);
      expect(container.read(mostLikedPeriodProvider), MostLikedPeriod.week);
      expect(tester.takeException(), isNull);
      await _teardown(tester, container);
    },
  );

  testWidgets(
    'standalone archive restores saved cards, date collapse and export',
    (tester) async {
      final container = await _pump(
        tester,
        subscribed: true,
        home: const MyLikesScreen(),
        extra: [
          likedGamesProvider.overrideWith(_SavedLikes.new),
          myLikesViewProvider.overrideWith(
            (ref) async => buildMyLikesData(
              matches: [_savedLike],
              totalLiked: 1,
              window: null,
            ),
          ),
        ],
      );
      expect(find.byType(MyLikesGameCard), findsOneWidget);
      expect(find.byTooltip('Export as PGN'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(PageView), findsNothing);
      await tester.tap(find.byType(DateSectionHeader));
      await _settle(tester);
      expect(find.byType(MyLikesGameCard), findsNothing);
      await tester.tap(find.byType(DateSectionHeader));
      await _settle(tester);
      expect(find.byType(MyLikesGameCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, container);
    },
  );

  testWidgets(
    'My Space Library restores My Likes first and opens its archive',
    (tester) async {
      final folder = LibraryFolder(
        id: 'likes',
        userId: 'u1',
        name: 'My Likes',
        color: '#EF4444',
        icon: 'favorite',
        orderIndex: 99,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isLikedGames: true,
      );
      final container = await _pump(
        tester,
        subscribed: true,
        home: const Scaffold(
          body: LibraryScreen(embedded: true, databasesOnly: true),
        ),
        extra: [
          libraryRepositoryProvider.overrideWith((ref) => _Library()),
          libraryFoldersStreamProvider.overrideWith(
            (ref) => Stream.value([folder]),
          ),
          subscribedBooksProvider.overrideWith((ref) async => []),
          folderAnalysisCountProvider.overrideWith((ref, id) async => 0),
          twicDatabaseTotalGamesProvider.overrideWith((ref) async => 100),
        ],
      );
      expect(find.text('My Likes').hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('My Likes')).dy,
        lessThan(tester.getTopLeft(find.text('ChessEver')).dy),
      );
      await tester.tap(find.text('My Likes'));
      await _settle(tester);
      expect(find.byType(MyLikesScreen), findsOneWidget);
      expect(find.byType(MyLikesGamesPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, container);
    },
  );

  for (final light in [false, true]) {
    testWidgets('ranked players fit 320px at double text scale, light=$light', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        subscribed: true,
        home: const LikesScreen(),
        size: const Size(320, 844),
        textScale: 2,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        extra: [
          mostLikedProvider.overrideWith(
            (ref, query) async => MostLikedResult.ranked([
              MostLikedEntry(
                rank: 1,
                likes: 999999,
                game: _ranking(1).first.game,
              ),
            ]),
          ),
        ],
      );
      await tester.tap(find.text('Players'));
      await _settle(tester);
      expect(find.byType(FigmaPlayerCard), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, container);
    });
  }

  testWidgets('Likes player opens only their ranked games and can clear it', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      subscribed: true,
      home: const LikesScreen(),
    );
    await tester.tap(find.text('Players').first);
    await _settle(tester);
    await tester.tap(find.text('White0, Player').hitTestable());
    await _settle(tester);
    expect(find.text('Games by White0, Player').hitTestable(), findsOneWidget);
    expect(
      find.byType(GridGameCardWrapperWidget).hitTestable(),
      findsOneWidget,
    );
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).hitTestable());
    await _settle(tester);
    expect(find.text('Games by White0, Player'), findsNothing);
    expect(find.byType(GridGameCardWrapperWidget), findsNWidgets(12));
    expect(tester.takeException(), isNull);
    await _teardown(tester, container);
  });

  testWidgets('horizontal swipes switch Likes sections, not secondary tabs', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      subscribed: true,
      home: const LikesScreen(),
    );
    await tester.tap(find.text('About').hitTestable());
    await _settle(tester);
    await tester.drag(
      find.text('Games the community loves'),
      const Offset(-320, 0),
    );
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    final sections = tester.widget<PageView>(find.byType(PageView).first);
    expect(sections.controller!.page, 1);
    expect(find.byType(MostLikedDateControl), findsOneWidget);
    await tester.drag(find.byType(PageView).first, const Offset(320, 0));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(sections.controller!.page, 0);
    expect(
      find.text('Games the community loves').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _teardown(tester, container);
  });

  for (final width in [320.0, 390.0, 1024.0]) {
    for (final light in [false, true]) {
      testWidgets('Likes tabs fit at $width with large text, light=$light', (
        tester,
      ) async {
        final container = await _pump(
          tester,
          subscribed: false,
          home: const LikesScreen(),
          size: Size(width, 844),
          textScale: 2,
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        );
        expect(find.text('Games').hitTestable(), findsOneWidget);
        await tester.tap(find.text('About').hitTestable());
        await _settle(tester);
        expect(find.text('My Likes').hitTestable(), findsOneWidget);
        expect(find.text('Games').first.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Games').first);
        await _settle(tester);
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.text('About').hitTestable(), findsOneWidget);
        expect(find.text('Games').first.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester, container);
      });
    }
  }

  testWidgets('Games lists the whole ranking with a heart on every board; '
      'Players lists everyone in it, each as their profile circle', (
    tester,
  ) async {
    final container = await _pump(tester, subscribed: true);

    expect(find.text('Most liked'), findsOneWidget);
    expect(find.text('Games'), findsOneWidget);
    expect(find.text('Players'), findsOneWidget);
    // No second "Most liked" or period title: the segments pick the period
    // and the date control says which.
    expect(find.byType(DiscoverySegments<MostLikedPeriod>), findsOneWidget);
    expect(find.byType(MostLikedDateControl), findsOneWidget);

    final cards = tester.widgetList<GridGameCardWrapperWidget>(
      find.byType(GridGameCardWrapperWidget),
    );
    expect(cards, hasLength(12));
    expect(find.byType(LikeCountHeart), findsNWidgets(12));
    // Nothing runs the engine on the page.
    for (final card in cards) {
      expect(card.allowStockfishFallback, isFalse);
    }

    await tester.tap(find.text('Players'));
    await _settle(tester);
    expect(find.byType(MostLikedPlayersList), findsOneWidget);
    expect(find.byType(FigmaPlayerCard), findsWidgets);
    // Uses the shared photo and initials fallback from the other player lists.
    expect(find.byType(PlayerInitialsAvatar), findsWidgets);
    expect(find.text('White0, Player'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester, container);
  });

  testWidgets('a free account browses every period, every date and the '
      'Players list; only opening an earlier game is gated', (tester) async {
    final container = await _pump(tester, subscribed: false);
    await tester.tap(find.bySemanticsLabel('Most liked, Today'));
    await _settle(tester);

    // Nothing on the page is locked or sold: no padlock on the date control,
    // no upgrade line in place of the ranking.
    expect(find.byType(DiscoveryPadlock), findsNothing);
    expect(
      find.textContaining(kMostLikedUpgradeCta, findRichText: true),
      findsNothing,
    );

    // The earlier-date arrow walks back like it does for Premium.
    tester
        .widget<MostLikedDateControl>(find.byType(MostLikedDateControl))
        .onPrevious!();
    await _settle(tester);
    expect(container.read(mostLikedDayProvider), isNotNull);
    container.read(mostLikedDayProvider.notifier).state = null;
    await _settle(tester);

    for (final period in [
      MostLikedPeriod.week,
      MostLikedPeriod.month,
      MostLikedPeriod.year,
    ]) {
      await tester.tap(find.bySemanticsLabel('Most liked, ${period.label}'));
      await _settle(tester);
      expect(container.read(mostLikedPeriodProvider), period);
      final list = tester.widget<DiscoveryGameList>(
        find.byType(DiscoveryGameList).first,
      );
      expect(list.onOpen, isNotNull);
      expect(list.lockedFor, isNull);
      expect(find.byType(DiscoveryPadlock), findsNothing);

      // Exercise the opening handler, not just the locked appearance. Debug
      // builds without rewarded configuration must still show a paywall.
      list.onOpen!(list.games, 0);
      await _settle(tester);
      expect(find.text('Sign in to get Premium'), findsOneWidget);
      Navigator.of(tester.element(find.text('Sign in to get Premium'))).pop();
      await _settle(tester);
      expect(find.byType(MostLikedScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    // Players lists everyone in the ranking, with nothing to unlock first.
    await tester.tap(find.text('Players'));
    await _settle(tester);
    expect(find.text('See everyone in this ranking'), findsNothing);
    expect(find.byType(MostLikedPlayersList), findsOneWidget);
    await _teardown(tester, container);
  });

  testWidgets('the hub stays on today after the page picks a week', (
    tester,
  ) async {
    final queries = <MostLikedQuery>[];
    final container = await _pump(tester, subscribed: true, queries: queries);

    // The label sits under the segment's own target.
    await tester.tap(find.text('Week').first, warnIfMissed: false);
    await _settle(tester);
    expect(container.read(mostLikedPeriodProvider), MostLikedPeriod.week);
    expect(queries.last.period, MostLikedPeriod.week);

    queries.clear();
    await _mount(
      tester,
      container,
      const Scaffold(body: SingleChildScrollView(child: MostLikedPreview())),
    );
    expect(queries, isNotEmpty);
    expect(queries.every((q) => q.period == MostLikedPeriod.today), isTrue);
    // Discovery now keeps the ranking inside its event-style destination
    // card; the full game list remains on the page above.
    expect(find.text('Most liked'), findsOneWidget);
    expect(find.byType(GridGameCardWrapperWidget), findsNothing);
    await _teardown(tester, container);
  });
}
