import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart'
    show standingsSearchQueryProvider;
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_round_demand_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/event_mute_provider.dart';
import 'package:chessever2/providers/event_video_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_list_presentation_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _detail = TourDetailViewModel(
  aboutTourModel: AboutTourModel(
    id: 'selected',
    slug: 'test-event',
    name: 'Test Event',
    groupBroadcastId: 'test-group',
    description: '',
    imageUrl: '',
    players: [],
    timeControl: '',
    date: '',
    location: '',
    websiteUrl: '',
    standingsUrl: '',
    tourUrl: '',
  ),
  liveTourIds: [],
  tours: [],
);

class _Database implements AppDatabase {
  final bools = <String, bool>{};
  final cache = <String, CacheEntry>{};
  final lists = <String, List<String>>{};
  @override
  Future<bool?> getBool(String key) async => bools[key];
  @override
  Future<void> setBool(String key, bool value) async {
    bools[key] = value;
  }

  @override
  Future<CacheEntry?> getCache({
    required String key,
    String? userId,
    Duration? maxAge,
  }) async => cache[key];
  @override
  Future<void> setCache({
    required String key,
    required String value,
    String? userId,
  }) async {
    cache[key] = CacheEntry(value: value, cachedAt: DateTime.now());
  }

  @override
  Future<List<String>> getList({required String key, String? userId}) async =>
      List.of(lists[key] ?? []);
  @override
  Future<void> clearList({required String key, String? userId}) async {
    lists.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Preferences extends AutoPinPreferencesNotifier {
  @override
  Future<AutoPinPreferences> build() async => const AutoPinPreferences();
}

class _Favorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => [
    FavoritePlayer(
      id: 'fav',
      userId: '',
      fideId: '123',
      playerName: 'Favorite',
      metadata: {},
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];
}

class _Mute extends EventMuteNotifier {
  int toggles = 0;
  bool failNext = false;
  @override
  Future<bool> build(String arg) async => false;
  @override
  Future<void> toggleMute() async {
    toggles++;
    if (failNext) return;
    state = AsyncData(!(state.valueOrNull ?? false));
  }
}

class _Rounds extends RoundRepository {
  @override
  Future<List<Round>> getRoundsByTourId(String tourId) async => [
    for (final (id, days) in [('current', 1), ('old', 2)])
      Round(
        id: id,
        slug: id,
        tourId: tourId,
        tourSlug: tourId,
        name: id,
        createdAt: DateTime.now().subtract(Duration(days: days)),
        startsAt: DateTime.now().subtract(Duration(days: days)),
        url: '',
      ),
  ];
  @override
  Stream<String> watchRoundMetadataChanges(String tourId) =>
      const Stream.empty();
}

class _Games extends GameRepository {
  final requests = <String>[];
  bool finished = false;
  final catalogRequests = <String>[];
  Future<List<Games>> Function(String)? searchResponse;

  @override
  Future<List<Games>> getTourGamePreviews(
    String tourId, {
    String? priorityRoundId,
    void Function(List<Games>)? onPriorityRound,
    Future<void> Function()? afterPriorityRound,
  }) async {
    catalogRequests.add(tourId);
    expectSync(priorityRoundId, isNull);
    if (searchResponse != null) return searchResponse!(tourId);
    return catalog(tourId);
  }

  List<Games> catalog(String tourId) => [
    ...roundGames(tourId, 'current'),
    ...roundGames(tourId, 'old'),
  ];
  @override
  Future<List<Games>> getRoundGamePreviews(
    String tourId,
    String roundId, {
    bool hydrateFallbacks = false,
  }) async {
    requests.add(roundId);
    return roundGames(tourId, roundId);
  }

  List<Games> roundGames(String tourId, String roundId) => [
    for (final board in [1, 2])
      Games(
        id:
            tourId == 'selected'
                ? '$roundId-$board'
                : '$tourId-$roundId-$board',
        roundId: roundId,
        roundSlug: roundId,
        tourId: tourId,
        tourSlug: tourId,
        boardNr: board,
        search: ['Favorite $roundId'],
        eco: board == 1 ? 'B90' : 'C60',
        openingName: board == 1 ? 'Sicilian Defense' : 'Ruy Lopez',
        status: board == 1 || finished ? '1-0' : '*',
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        lastMove: 'e2e4',
        lastClockWhite: 60,
        lastClockBlack: 60,
        isPgnDeferred: true,
        players: [
          Player(
            name: 'Favorite',
            fideId: 123,
            title: 'GM',
            rating: 2400,
            fed: 'US',
            clock: 0,
            team: 'Team A',
          ),
          Player(
            name: 'Opponent',
            fideId: 456,
            title: 'GM',
            rating: 2400,
            fed: 'GB',
            clock: 0,
            team: 'Team B',
          ),
        ],
      ),
  ];
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'test',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  });
  for (final isTablet in [false, true]) {
    group(isTablet ? 'tablet menu' : 'phone menu', () {
      late ProviderContainer container;
      late _Games games;
      late _Database db;
      late _Mute mute;
      late List<MethodCall> shares;
      Future<void> mount(
        WidgetTester tester, {
        bool signedIn = true,
        TourDetailViewModel detail = _detail,
        bool knockout = false,
        String initialQuery = '',
      }) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            isTablet ? const Size(800, 600) : const Size(393, 852);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        games = _Games();
        db = _Database();
        shares = [];
        // Tests use local memory only; no real preferences, notifications or shares.
        db.cache['selected_country_code'] = CacheEntry(
          value: 'US',
          cachedAt: DateTime.now(),
        );
        container = ProviderContainer(
          overrides: [
            tourDetailScreenProviderOverride(detail),
            standingsSearchQueryProvider.overrideWith((ref) => initialQuery),
            appDatabaseProvider.overrideWithValue(db),
            gameRepositoryProvider.overrideWithValue(games),
            roundRepositoryProvider.overrideWithValue(_Rounds()),
            eventVideoConfigurationProvider.overrideWithValue(null),
            currentUserProvider.overrideWithValue(null),
            isAuthenticatedProvider.overrideWithValue(signedIn),
            autoPinPreferencesProvider.overrideWith(_Preferences.new),
            favoritePlayersProviderNew.overrideWith(_Favorites.new),
            eventMuteProvider.overrideWith(() => mute = _Mute()),
            knockoutTournamentStateProvider.overrideWith(
              (ref, id) => KnockoutTournamentState(
                isKnockout: knockout,
                isTeamEvent: false,
                stageName: null,
                allGames: const [],
              ),
            ),
            relatedKnockoutStageIdsProvider.overrideWith((ref, id) => const []),
            liveRoundsIdProvider.overrideWith((ref) => const Stream.empty()),
            // Keep the real metadata/controller, with a lightweight list presentation.
            gamesTourListPresentationProvider.overrideWith(
              (ref) => GamesTourListPresentation(
                displayRounds:
                    ref
                        .watch(gamesAppBarProvider)
                        .valueOrNull
                        ?.gamesAppBarModels ??
                    [],
                gamesByRound: const {},
                layout: GamesTourFlattenedLayout.empty,
              ),
            ),
          ],
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/share'),
              (call) async {
                shares.add(call);
                return 'success';
              },
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    body: Align(
                      alignment: Alignment.topRight,
                      child: TournamentMenuButton(tourData: detail),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        container.listen(gamesTourScreenProvider, (_, _) {});
        container.listen(gamesAppBarProvider, (_, _) {});
        await _settle(tester);
        expect(container.read(gamesTourScreenProvider).hasValue, isTrue);
        expect(games.requests, ['current']);
      }

      Future<void> open(WidgetTester tester) async {
        await tester.tap(find.byType(AppBarIcons));
        await tester.pumpAndSettle();
      }

      Future<void> choose(WidgetTester tester, String label) async {
        await open(tester);
        expect(find.text(label), findsOneWidget);
        await tester.tap(find.text(label));
        await _settle(tester);
      }

      Future<void> close(WidgetTester tester) async {
        await _settle(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        container.dispose();
        await tester.pump();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/share'),
              null,
            );
      }

      testWidgets(
        'search scopes selected category and knockout lane independently of loaded stages',
        (tester) async {
          Tour tour(String id, String name, String group) => Tour(
            id: id,
            name: name,
            slug: id,
            info: TourInfo(format: 'Knockout'),
            createdAt: DateTime(2026),
            url: '',
            tier: 0,
            dates: [],
            players: [],
            groupBroadcastId: group,
          );
          final selected = tour(
            'selected',
            'World Cup | Open | Round 2',
            'test-group',
          );
          final detail = TourDetailViewModel(
            aboutTourModel: AboutTourModel.fromTour(selected),
            liveTourIds: [],
            tours: [
              for (final t in [
                selected,
                tour('sibling', 'World Cup | Open | Round 1', 'test-group'),
                tour('women', 'World Cup | Women | Round 2', 'test-group'),
                tour('unrelated', 'Other Cup | Open | Round 1', 'other-group'),
              ])
                TourModel(tour: t, roundStatus: RoundStatus.completed),
            ],
          );
          await mount(tester, detail: detail);
          final controller = container.read(gamesTourScreenProvider.notifier);
          await controller.searchGamesEnhanced('old');
          expect(games.catalogRequests, ['selected']);
          await close(tester);

          await mount(tester, detail: detail, knockout: true);
          final knockoutController = container.read(
            gamesTourScreenProvider.notifier,
          );
          await knockoutController.searchGamesEnhanced('old');
          expect(
            container.read(gamesTourScreenProvider).hasError,
            isFalse,
            reason:
                '${container.read(gamesTourScreenProvider).error} ${container.read(gamesTourScreenProvider).stackTrace}',
          );
          expect(games.catalogRequests.toSet(), {'selected', 'sibling'});
          expect(
            container
                .read(gamesTourScreenProvider)
                .requireValue
                .gamesTourModels
                .map((g) => g.gameId)
                .toSet(),
            {'old-1', 'old-2', 'sibling-old-1', 'sibling-old-2'},
          );
          expect(container.exists(gamesTourProvider('sibling')), isFalse);
          expect(container.exists(gamesTourProvider('women')), isFalse);
          games.searchResponse = (id) async {
            if (id == 'sibling') throw StateError('stage unavailable');
            return games.catalog(id);
          };
          await knockoutController.searchGamesEnhanced('old');
          expect(container.read(gamesTourScreenProvider).hasError, isTrue);
          await close(tester);
        },
      );

      testWidgets(
        'retained search is reapplied when a category creates its screen controller',
        (tester) async {
          await mount(tester, initialQuery: 'old');
          expect(
            container.read(gamesTourScreenProvider).requireValue.searchQuery,
            'old',
          );
          expect(
            container
                .read(gamesTourScreenProvider)
                .requireValue
                .gamesTourModels
                .map((g) => g.gameId),
            unorderedEquals(['old-1', 'old-2']),
          );
          expect(games.catalogRequests, ['selected']);
          await close(tester);
        },
      );

      testWidgets(
        'search/filter/sort/view/pin/expansion matrix uses full catalog',
        (tester) async {
          await mount(tester);
          container.listen(gamesTourGroupedProvider, (_, _) {});
          final controller = container.read(gamesTourScreenProvider.notifier);
          final browseRounds = container.read(roundExpansionProvider.notifier);
          browseRounds.collapseAll(['current', 'old']);
          final allIds = {'current-1', 'current-2', 'old-1', 'old-2'};
          final queries = <String, Set<String>>{
            'FaVoRiTe': allIds,
            'old': {'old-1', 'old-2'},
            ' Favorite   GM ': allIds,
            '2400': allIds,
            'GB': allIds,
            'b90': {'current-1', 'old-1'},
            'Ruy Lopez': {'current-2', 'old-2'},
            '1-0': {'current-1', 'old-1'},
            'no match': {},
          };
          var combinations = 0;
          for (final entry in queries.entries) {
            await tester.runAsync(
              () => controller.searchGamesEnhanced(entry.key),
            );
            for (final pinned in [false, true]) {
              final pinAction =
                  pinned
                      ? controller.enableAutoPin()
                      : controller.unpinAllGames();
              await _settle(tester);
              await pinAction;
              for (final mode in GameDisplayMode.values) {
                switch (mode) {
                  case GameDisplayMode.all:
                    await controller.showAllGames();
                  case GameDisplayMode.hideFinishedGames:
                    await controller.hideFinishedGames();
                  case GameDisplayMode.showfinishedGame:
                    await controller.showFinishedGames();
                }
                final data =
                    container.read(gamesTourScreenProvider).requireValue;
                expect(data.isSearchMode, isTrue);
                expect(data.searchQuery, entry.key.trim());
                expect(
                  data.pinnedGamedIs.toSet(),
                  pinned ? allIds : <String>{},
                );
                expect(
                  data.gamesTourModels.map((g) => g.gameId).toSet(),
                  entry.value,
                );
                final grouped = container.read(gamesTourGroupedProvider);
                final expected =
                    entry.value
                        .where(
                          (id) =>
                              mode != GameDisplayMode.showfinishedGame ||
                              id.endsWith('-1'),
                        )
                        .toSet();
                expect(
                  grouped.gamesByRound.values
                      .expand((g) => g)
                      .map((g) => g.gameId)
                      .toSet(),
                  expected,
                );
                expect(grouped.unloadedRoundIds, isEmpty);
                for (final roundGames in grouped.gamesByRound.values) {
                  if (roundGames.length != 2) continue;
                  expect(
                    roundGames.first.boardNr,
                    mode == GameDisplayMode.hideFinishedGames ? 2 : 1,
                  );
                }
                final teamOrder = orderTeamEventGamesForBoardNavigation(
                  grouped.gamesByRound.values.expand((g) => g).toList(),
                );
                expect(teamOrder.map((g) => g.gameId).toSet(), expected);
                for (final view in GamesListViewMode.values) {
                  for (final collapsed in [false, true]) {
                    final layout = buildGamesTourFlattenedLayout(
                      rounds: grouped.filteredRounds,
                      gamesByRound: grouped.gamesByRound,
                      mode: view,
                      isSearchMode: true,
                      isKnockoutTournament: false,
                      displayMode: mode,
                      roundExpansionState: {
                        for (final r in grouped.filteredRounds)
                          r.id: !collapsed,
                      },
                      matchExpansionState: const {},
                    );
                    expect(
                      layout.orderedGames.map((g) => g.gameId).toSet(),
                      expected,
                    );
                    expect(
                      layout.gameItemIndices.keys.toSet(),
                      collapsed ? <String>{} : expected,
                    );
                    combinations++;
                  }
                }
              }
            }
          }
          expect(combinations, 324);
          expect(
            games.catalogRequests,
            List.filled(queries.length, 'selected'),
          );
          expect(games.requests, ['current']);
          expect(
            container.read(gamesTourProvider('selected')).requireValue,
            hasLength(2),
          );
          expect(
            container
                .read(gamesTourProvider('selected').notifier)
                .isCatalogComplete,
            isFalse,
          );
          // Query rendering must never turn visible result rounds into browsing requests.
          container
              .read(visibleTournamentRoundsProvider('selected').notifier)
              .state = {'old'};
          expect(
            container.read(gamesTourRoundDemandProvider)['selected'],
            isEmpty,
          );
          await close(tester);
        },
      );

      testWidgets(
        'search survives every Games menu action and restores browsing collapse state',
        (tester) async {
          await mount(tester);
          final controller = container.read(gamesTourScreenProvider.notifier);
          container.read(roundExpansionProvider.notifier).collapseAll([
            'current',
            'old',
          ]);
          await tester.runAsync(() => controller.searchGamesEnhanced('old'));
          for (final action in [
            'Live games first',
            'Board order',
            'No Spoilers',
            'Unpin all',
            'Pin all',
            'Collapse all',
            'Expand all',
            'Disable notifications',
            'Enable notifications',
            'Share event',
          ]) {
            await choose(tester, action);
            final data = container.read(gamesTourScreenProvider).requireValue;
            expect(data.searchQuery, 'old', reason: action);
            expect(
              data.gamesTourModels.map((g) => g.gameId),
              unorderedEquals(['old-1', 'old-2']),
              reason: action,
            );
            if (action == 'Collapse all' || action == 'Expand all') {
              expect(
                container
                    .read(searchRoundExpansionProvider.notifier)
                    .isExpanded('old'),
                action == 'Expand all',
              );
              expect(
                container
                    .read(searchMatchExpansionProvider.notifier)
                    .isExpanded(
                      teamMatchExpansionKey('old', 'Team A vs Team B'),
                    ),
                action == 'Expand all',
              );
            }
          }
          expect(games.catalogRequests, ['selected']);
          expect(
            container.read(roundExpansionProvider.notifier).isExpanded('old'),
            isFalse,
          );
          controller.clearSearch();
          await _settle(tester);
          final restored = container.read(gamesTourScreenProvider).requireValue;
          expect(restored.isSearchMode, isFalse);
          expect(restored.searchQuery, isNull);
          expect(restored.gamesTourModels, hasLength(2));
          expect(games.requests, ['current']);
          await close(tester);
        },
      );

      testWidgets(
        'search races, clear, refresh, and failures never publish partial results',
        (tester) async {
          await mount(tester);
          final controller = container.read(gamesTourScreenProvider.notifier);
          final gate = Completer<List<Games>>();
          games.searchResponse = (_) => gate.future;
          final oldSearch = controller.searchGamesEnhanced('current');
          await tester.pump();
          final newSearch = controller.searchGamesEnhanced('old');
          await tester.pump();
          await controller.hideFinishedGames();
          expect(container.read(gamesTourScreenProvider).isLoading, isTrue);
          gate.complete(games.catalog('selected'));
          await Future.wait([oldSearch, newSearch]);
          expect(
            container.read(gamesTourScreenProvider).requireValue.searchQuery,
            'old',
          );
          expect(
            container
                .read(gamesTourScreenProvider)
                .requireValue
                .gamesTourModels
                .map((g) => g.gameId),
            unorderedEquals(['old-1', 'old-2']),
          );
          expect(games.catalogRequests, ['selected']);
          final clearGate = Completer<List<Games>>();
          games.searchResponse = (_) => clearGate.future;
          final pending = controller.searchGamesEnhanced('Favorite');
          await tester.pump();
          controller.clearSearch();
          clearGate.complete(games.catalog('selected'));
          await pending;
          await _settle(tester);
          expect(
            container.read(gamesTourScreenProvider).requireValue.isSearchMode,
            isFalse,
          );
          games.searchResponse =
              (_) async => throw StateError('backend unavailable');
          await controller.searchGamesEnhanced('old');
          expect(container.read(gamesTourScreenProvider).hasError, isTrue);
          games.searchResponse = null;
          await controller.refreshGames();
          expect(
            container.read(gamesTourScreenProvider).requireValue.searchQuery,
            'old',
          );
          expect(
            container
                .read(gamesTourScreenProvider)
                .requireValue
                .gamesTourModels,
            hasLength(2),
          );
          expect(games.requests, ['current']);
          await close(tester);
        },
      );

      testWidgets(
        'Games menu contains every expected action without standings actions',
        (tester) async {
          await mount(tester);
          await open(tester);
          for (final label in [
            'Live games first',
            'No Spoilers',
            'Unpin all',
            'Collapse all',
            'Disable notifications',
            'Share event',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          expect(find.text('Share standings'), findsNothing);
          expect(find.text('Share team standings'), findsNothing);
          expect(find.text('Share brackets'), findsNothing);
          expect(games.requests, ['current']);
          await close(tester);
        },
      );

      testWidgets(
        'sorting survives later round loads and toggles back without fetching a catalog',
        (tester) async {
          await mount(tester);
          container.listen(gamesTourGroupedProvider, (_, _) {});
          await _settle(tester);
          List<String> order(String round) =>
              container
                  .read(gamesTourGroupedProvider)
                  .gamesByRound[round]!
                  .map((game) => game.gameId)
                  .toList();
          expect(order('current'), ['current-1', 'current-2']);
          await choose(tester, 'Live games first');
          expect(order('current'), ['current-2', 'current-1']);
          expect(
            container.read(gameDisplayModeProvider('selected')),
            GameDisplayMode.hideFinishedGames,
          );
          expect(
            container
                .read(gamesTourScreenProvider)
                .requireValue
                .gamesTourModels
                .length,
            2,
          );
          expect(games.requests, ['current']);
          await tester.runAsync(
            () => container
                .read(gamesTourProvider('selected').notifier)
                .setActiveRounds({'current', 'old'}),
          );
          await _settle(tester);
          expect(
            container
                .read(gamesTourScreenProvider)
                .requireValue
                .gameDisplayMode,
            GameDisplayMode.hideFinishedGames,
          );
          expect(
            container
                .read(gamesTourScreenProvider)
                .requireValue
                .gamesTourModels
                .length,
            4,
          );
          expect(order('old'), ['old-2', 'old-1']);
          games.finished = true;
          await tester.runAsync(
            () =>
                container
                    .read(gamesTourProvider('selected').notifier)
                    .refreshGames(),
          );
          await _settle(tester);
          expect(order('current'), ['current-1', 'current-2']);
          final requestsBeforeToggle = List.of(games.requests);
          await choose(tester, 'Board order');
          expect(order('old'), ['old-1', 'old-2']);
          expect(games.requests, requestsBeforeToggle);
          expect(
            container.read(gameDisplayModeProvider('selected')),
            GameDisplayMode.all,
          );
          expect(
            container
                .read(gamesTourScreenProvider)
                .requireValue
                .gamesTourModels
                .length,
            4,
          );
          expect(
            container.read(gameDisplayModeProvider('other-category')),
            GameDisplayMode.all,
          );
          expect(games.requests.toSet(), {'current', 'old'});
          expect(
            container
                .read(gamesTourProvider('selected').notifier)
                .isCatalogComplete,
            isFalse,
          );
          await close(tester);
        },
      );

      testWidgets(
        'spoilers toggle persists and applies before an older round loads',
        (tester) async {
          await mount(tester);
          await choose(tester, 'No Spoilers');
          expect(db.bools['event_no_spoilers_selected'], isTrue);
          expect(
            container.read(eventNoSpoilersProvider('selected')).enabled,
            isTrue,
          );
          await tester.runAsync(
            () => container
                .read(gamesTourProvider('selected').notifier)
                .setActiveRounds({'current', 'old'}),
          );
          await _settle(tester);
          expect(
            container.read(eventNoSpoilersProvider('selected')).enabled,
            isTrue,
          );
          expect(
            container.read(eventNoSpoilersProvider('other-category')).enabled,
            isFalse,
          );
          await choose(tester, 'Disable No Spoilers');
          expect(db.bools['event_no_spoilers_selected'], isFalse);
          expect(games.requests, ['current', 'old']);
          await close(tester);
        },
      );

      testWidgets(
        'unpin all clears stored older pins and pin all applies to later-loaded favorites',
        (tester) async {
          await mount(tester);
          db.lists['pinned_games_selected'] = ['old-1'];
          db.lists['pinned_games_other-category'] = ['other-1'];
          await choose(tester, 'Unpin all');
          expect(db.lists['pinned_games_selected'], isNull);
          expect(db.lists['pinned_games_other-category'], ['other-1']);
          expect(container.read(gamesPinprovider('selected')).allPins, isEmpty);
          await choose(tester, 'Pin all');
          expect(container.read(gamesPinprovider('selected')).allPins.toSet(), {
            'current-1',
            'current-2',
          });
          await tester.runAsync(
            () => container
                .read(gamesTourProvider('selected').notifier)
                .setActiveRounds({'current', 'old'}),
          );
          await _settle(tester);
          expect(container.read(gamesPinprovider('selected')).allPins.toSet(), {
            'current-1',
            'current-2',
            'old-1',
            'old-2',
          });
          await close(tester);
        },
      );

      testWidgets(
        'bulk expansion covers unloaded rounds and late team matchups',
        (tester) async {
          await mount(tester);
          final rounds = container.read(roundExpansionProvider.notifier);
          final matches = container.read(matchExpansionProvider.notifier);
          rounds.collapseAll([
            'current',
            'old',
          ]); // Manual parent collapse, child defaults still expanded.
          await choose(tester, 'Expand all');
          expect(rounds.isExpanded('old'), isTrue);
          expect(
            matches.isExpanded(teamMatchExpansionKey('old', 'A vs B')),
            isTrue,
          );
          await choose(tester, 'Collapse all');
          expect(rounds.isExpanded('current'), isFalse);
          expect(rounds.isExpanded('old'), isFalse);
          expect(
            matches.isExpanded(teamMatchExpansionKey('old', 'A vs B')),
            isFalse,
          );
          rounds.expandRound('old');
          expect(
            matches.isExpanded(teamMatchExpansionKey('old', 'A vs B')),
            isFalse,
          );
          await choose(tester, 'Collapse all');
          await choose(tester, 'Expand all');
          expect(
            matches.isExpanded(teamMatchExpansionKey('old', 'A vs B')),
            isTrue,
          );
          await close(tester);
        },
      );

      testWidgets('notification menu toggles both directions', (tester) async {
        await mount(tester);
        await choose(tester, 'Disable notifications');
        expect(mute.state.requireValue, isTrue);
        await choose(tester, 'Enable notifications');
        expect(mute.state.requireValue, isFalse);
        expect(mute.toggles, 2);
        expect(games.requests, ['current']);
        await close(tester);
      });

      testWidgets(
        'signed-out notifications show sign-in feedback without mutation',
        (tester) async {
          await mount(tester, signedIn: false);
          await choose(tester, 'Disable notifications');
          expect(mute.toggles, 0);
          expect(
            find.text('Please sign in to manage notifications'),
            findsOneWidget,
          );
          await close(tester);
        },
      );

      testWidgets(
        'share uses the selected event URL with a valid popover origin',
        (tester) async {
          await mount(tester);
          await choose(tester, 'Share event');
          expect(shares, hasLength(1));
          expect(
            shares.single.arguments['text'],
            contains('test-event/selected'),
          );
          expect(shares.single.arguments['originWidth'], greaterThan(0));
          expect(shares.single.arguments['originHeight'], greaterThan(0));
          expect(games.requests, ['current']);
          await close(tester);
        },
      );
      testWidgets(
        'failed notification save reports failure instead of success',
        (tester) async {
          await mount(tester);
          mute.failNext = true;
          await choose(tester, 'Disable notifications');
          expect(mute.state.requireValue, isFalse);
          expect(
            find.text('Could not update notifications. Please try again.'),
            findsOneWidget,
          );
          expect(
            find.text('Notifications disabled for this event'),
            findsNothing,
          );
          await close(tester);
        },
      );

      testWidgets(
        'share platform failure gives feedback without losing the games tab',
        (tester) async {
          await mount(tester);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('dev.fluttercommunity.plus/share'),
                (call) async {
                  throw PlatformException(code: 'unavailable');
                },
              );
          await choose(tester, 'Share event');
          expect(
            find.text('Could not share this event. Please try again.'),
            findsOneWidget,
          );
          expect(container.read(gamesTourScreenProvider).hasValue, isTrue);
          expect(games.requests, ['current']);
          await close(tester);
        },
      );
    });
  }
}
