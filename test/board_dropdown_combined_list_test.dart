import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/board_engine_lines_visibility_provider.dart';
import 'package:chessever2/providers/gamebase_overlay_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_screen.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/board_feature_teaching_store.dart';

/// The Combined list hands the board every category's games, while the
/// selected category underneath still publishes only its own. The switcher
/// must page through the whole handed-over list.
class _SelectedCategoryGames extends GamesTourScreenProvider {
  _SelectedCategoryGames({required super.ref, required List<GamesTourModel> games})
    : super.loading() {
    state = AsyncValue.data(
      GamesScreenModel(gamesTourModels: games, pinnedGamedIs: const []),
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'swipable_walkthrough_dont_show': true,
      'board_pinch_coachmark_dont_show': true,
    });
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-anon-key',
    );
    GameAnalysisReportStore.debugSetInstance(GameAnalysisReportStore.memory());
  });

  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  testWidgets('a board opened from the Combined list pages across categories', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final strong = List<Games>.generate(
      3,
      (i) => _rawGame(id: 'b-$i', tourId: 'group-b', board: i + 1),
    );
    final selected = List<Games>.generate(
      3,
      (i) => _rawGame(id: 'a-$i', tourId: 'group-a', board: i + 1),
    );
    final raws = [...strong, ...selected];
    final strongModels = strong.map(GamesTourModel.fromGame).toList();
    final selectedModels = selected.map(GamesTourModel.fromGame).toList();

    Tour tour(String id, String section) => Tour.virtual(
      id: id,
      name: 'Event | $section',
      slug: id,
      dates: [DateTime.utc(2026, 11, 7), DateTime.utc(2026, 11, 14)],
      players: const [],
    );
    final tours = [tour('group-a', 'Group A'), tour('group-b', 'Group B')];
    const categories = [
      CombinedCategory(tourId: 'group-b', label: 'B', avgElo: 2735, order: 1),
      CombinedCategory(tourId: 'group-a', label: 'A', avgElo: 2718, order: 0),
    ];
    final sections = buildCombinedRoundSections(
      categories: categories,
      gamesByTourId: {'group-a': selectedModels, 'group-b': strongModels},
      roundsByTourId: const <String, List<Round>>{},
      liveRoundIds: const <String>[],
    );

    final container = ProviderContainer(
      overrides: [
        boardFeatureTeachingTrackerProvider.overrideWith(
          (_) => BoardFeatureTeachingTracker(QuietBoardTeachingStore()),
        ),
        effectiveCountryProvider.overrideWithValue(const AsyncValue.loading()),
        gamesLocalStorage.overrideWith(
          (ref) => _FullCacheGamesLocalStorage(ref, {
            'group-a': selected,
            'group-b': strong,
          }),
        ),
        gameRepositoryProvider.overrideWithValue(
          _ImmediateGameRepository({for (final g in raws) g.id: g}),
        ),
        gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
        gameStreamRepositoryProvider.overrideWithValue(
          _FakeGameStreamRepository(),
        ),
        localEvalCacheProvider.overrideWith(_FakeLocalEvalCache.new),
        engineSettingsProviderNew.overrideWith(_FakeEngineSettingsNotifier.new),
        boardEngineLinesVisibleProvider.overrideWith(_VisibleBoardLines.new),
        gamebaseOverlayEnabledProvider.overrideWith(
          _FakeGamebaseOverlayNotifier.new,
        ),
        eventNoSpoilersProvider.overrideWith(
          (ref, tourId) =>
              _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
        ),
        chessBoardPersistenceEnabledProvider.overrideWithValue(false),
        premiumAccessProvider.overrideWithValue(true),
        selectedBroadcastModelProvider.overrideWith(
          (ref) => GroupBroadcast.fromJson({
            'id': 'event',
            'created_at': '2026-11-05T19:50:50.000Z',
            'name': 'Event',
            'search': const <String>[],
          }),
        ),
        tourDetailScreenProviderOverride(
          TourDetailViewModel(
            aboutTourModel: AboutTourModel.fromTour(tours.first),
            liveTourIds: const [],
            tours: [
              for (final tour in tours)
                TourModel(tour: tour, roundStatus: RoundStatus.ongoing),
            ],
          ),
        ),
        combinedCategoriesProvider.overrideWithValue(
          const CombinedCategories(categories),
        ),
        combinedRoundSectionsProvider.overrideWithValue(
          CombinedRoundSections(
            isLoading: false,
            error: null,
            sections: sections,
            pinnedGameIds: const <String>[],
            searchQuery: '',
            hasUnscheduledRounds: false,
          ),
        ),
        gamesTourScreenProvider.overrideWith(
          (ref) => _SelectedCategoryGames(ref: ref, games: selectedModels),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const Scaffold(body: CombinedGamesScreen());
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Open the first board of the stronger category.
    await tester.tap(find.textContaining('b-0').first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final pages = find.byKey(boardGamesPageViewTestKey);
    expect(pages, findsOneWidget);
    expect(tester.widget<PageView>(pages).controller!.page, 0);

    // Open the switcher and pick a game by hand, the way a viewer does.
    await tester.tap(find.byKey(e2eKey(E2eIds.boardGameSelector)).first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final dropdown = find.byKey(boardGameDropdownContentTestKey);
    expect(dropdown, findsOneWidget);
    final snapshot = boardGameDropdownSnapshotForTesting(
      tester.widget(dropdown),
    );
    expect(snapshot.gameIds, ['b-0', 'b-1', 'b-2', 'a-0', 'a-1', 'a-2']);
    // Both categories have a "Round 1"; the round rail tells them apart.
    expect(find.text('B · Round 1'), findsOneWidget);
    expect(find.text('A · Round 1'), findsOneWidget);

    // The strip is horizontal: bring the other category's first card in.
    await tester.drag(
      find.descendant(of: dropdown, matching: find.byType(ListView)).first,
      const Offset(-420, 0),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(boardGameDropdownCardTestKey('a-0')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(tester.widget<PageView>(pages).controller!.page, 3);
    expect(find.byKey(boardGameDropdownContentTestKey), findsNothing);

    // Swipe on to the next game.
    await tester.drag(pages, const Offset(-220, 0));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(tester.widget<PageView>(pages).controller!.page, 4);
    expect(container.read(currentlyVisiblePageIndexProvider), 4);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  });

  test('categories of the open event share its stream', () {
    final game = GamesTourModel.fromGame(
      _rawGame(id: 'b-0', tourId: 'group-b', board: 1),
    );
    expect(
      eventTourIdsForVideo(game: game, openEventTourIds: 'group-a,group-b'),
      {'group-a', 'group-b'},
    );
    // A game of some other event, a single-category event, or no open event.
    expect(
      eventTourIdsForVideo(game: game, openEventTourIds: 'x,y'),
      isEmpty,
    );
    expect(
      eventTourIdsForVideo(game: game, openEventTourIds: 'group-b'),
      isEmpty,
    );
    expect(eventTourIdsForVideo(game: game, openEventTourIds: null), isEmpty);

    // Opened from outside the event's screen (For You): the event the board
    // was widened to answers instead, even with another event open.
    const widened = CombinedCategories([
      CombinedCategory(tourId: 'group-b', label: 'B', avgElo: 2735, order: 0),
      CombinedCategory(tourId: 'group-a', label: 'A', avgElo: 2718, order: 1),
    ]);
    expect(
      eventTourIdsForVideo(
        game: game,
        openEventTourIds: 'x,y',
        boardEvents: const [widened],
      ),
      {'group-a', 'group-b'},
    );
  });

  testWidgets('switcher reaches another category from a Combined list', (
    tester,
  ) async {
    final strong = List<Games>.generate(
      3,
      (i) => _rawGame(id: 'b-$i', tourId: 'group-b', board: i + 1),
    );
    final selected = List<Games>.generate(
      3,
      (i) => _rawGame(id: 'a-$i', tourId: 'group-a', board: i + 1),
    );
    final raws = [...strong, ...selected];
    final games = raws.map(GamesTourModel.fromGame).toList();
    final selectedModels = selected.map(GamesTourModel.fromGame).toList();

    final container = ProviderContainer(
      overrides: [
        boardFeatureTeachingTrackerProvider.overrideWith(
          (_) => BoardFeatureTeachingTracker(QuietBoardTeachingStore()),
        ),
        effectiveCountryProvider.overrideWithValue(const AsyncValue.loading()),
        gamesLocalStorage.overrideWith(
          (ref) => _FullCacheGamesLocalStorage(ref, {
            'group-a': selected,
            'group-b': strong,
          }),
        ),
        gameRepositoryProvider.overrideWithValue(
          _ImmediateGameRepository({for (final g in raws) g.id: g}),
        ),
        gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
        gameStreamRepositoryProvider.overrideWithValue(
          _FakeGameStreamRepository(),
        ),
        localEvalCacheProvider.overrideWith(_FakeLocalEvalCache.new),
        engineSettingsProviderNew.overrideWith(_FakeEngineSettingsNotifier.new),
        boardEngineLinesVisibleProvider.overrideWith(_VisibleBoardLines.new),
        gamebaseOverlayEnabledProvider.overrideWith(
          _FakeGamebaseOverlayNotifier.new,
        ),
        eventNoSpoilersProvider.overrideWith(
          (ref, tourId) =>
              _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
        ),
        chessBoardPersistenceEnabledProvider.overrideWithValue(false),
        gamesTourScreenProvider.overrideWith(
          (ref) => _SelectedCategoryGames(ref: ref, games: selectedModels),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return ChessBoardScreenNew(
                currentIndex: 0,
                games: games,
                viewSource: ChessboardView.tour,
              );
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final pages = find.byKey(boardGamesPageViewTestKey);
    expect(pages, findsOneWidget);

    final selector = find.byKey(e2eKey(E2eIds.boardGameSelector)).first;
    final selectorTap = find.descendant(
      of: selector,
      matching: find.byType(GestureDetector),
    );
    tester.widget<GestureDetector>(selectorTap.first).onTap!();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(boardGameDropdownContentTestKey), findsOneWidget);
    final snapshot = boardGameDropdownSnapshotForTesting(
      tester.widget(find.byKey(boardGameDropdownContentTestKey)),
    );
    expect(snapshot.gameIds, [for (final game in games) game.gameId]);

    // The fourth card belongs to the other category.
    boardGameDropdownSelectForTesting(
      tester.widget(find.byKey(boardGameDropdownContentTestKey)),
      4,
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(tester.widget<PageView>(pages).controller!.page, 4);
    expect(container.read(currentlyVisiblePageIndexProvider), 4);
    expect(find.textContaining('a-1'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  });
}

Games _rawGame({
  required String id,
  required String tourId,
  required int board,
}) {
  return Games(
    id: id,
    roundId: '$tourId-round-1',
    roundSlug: 'round-1',
    tourId: tourId,
    tourSlug: tourId,
    players: [
      _player(name: 'White $id', fideId: board * 2 + 1),
      _player(name: 'Black $id', fideId: board * 2 + 2),
    ],
    boardNr: board,
    status: '1-0',
    lastMove: 'e7e5',
    pgn: '''
[Event "Dropdown jump"]
[White "White $id"]
[Black "Black $id"]
[Result "1-0"]

1. e4 e5 1-0
''',
  );
}

Player _player({required String name, required int fideId}) {
  return Player(
    name: name,
    title: 'GM',
    rating: 2700,
    fideId: fideId,
    fed: 'USA',
    clock: 0,
    team: '',
  );
}

class _ImmediateGameRepository extends GameRepository {
  _ImmediateGameRepository(this.games);

  final Map<String, Games> games;

  @override
  Future<Games> getGameWithPGN(String gameId) async => games[gameId]!;

  @override
  Future<String?> getGamePgn(String gameId) async => games[gameId]?.pgn;
}

class _FullCacheGamesLocalStorage extends GamesLocalStorage {
  _FullCacheGamesLocalStorage(super.ref, this.byTour);

  final Map<String, List<Games>> byTour;

  @override
  Future<List<Games>> getCachedGames(String tourId) async =>
      byTour[tourId] ?? const [];

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
    String? priorityRoundId,
    void Function(List<Games>)? onPriorityRound,
    Future<void> Function()? afterPriorityRound,
    bool rethrowErrors = false,
  }) async => byTour[tourId] ?? const [];
}

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository()
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;

  @override
  Future<CloudEval?> getEvalByFen(String fen) async => null;

  @override
  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) async =>
      const GamebaseResponse(status: 'success', data: GamebaseData(moves: []));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGameStreamRepository extends GameStreamRepository {
  @override
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) =>
      const Stream.empty();

  @override
  Stream<String?> subscribeToPgn(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToLastMove(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToFen(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToStatus(String gameId) => const Stream.empty();
}

class _VisibleBoardLines extends BoardEngineLinesVisibleNotifier {
  @override
  Future<bool> build() async => true;
}

class _FakeEngineSettingsNotifier extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false, showEngineGauge: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGamebaseOverlayNotifier extends GamebaseOverlayEnabledNotifier {
  @override
  Future<bool> build() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {
    state = AsyncValue.data(enabled);
  }

  @override
  Future<void> toggle() => setEnabled(!(state.valueOrNull ?? false));
}

class _FakeEventNoSpoilersController extends EventNoSpoilersController {
  _FakeEventNoSpoilersController({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _FakeLocalEvalCache extends LocalEvalCache {
  _FakeLocalEvalCache(super.ref);

  @override
  Future<CloudEval?> fetch(
    String fen, {
    int? multiPV,
    int minDepth = 0,
  }) async => null;

  @override
  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {}
}
