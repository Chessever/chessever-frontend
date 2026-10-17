import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
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
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/board_feature_teaching_store.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'swipable_walkthrough_dont_show': true,
    });
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-anon-key',
    );
    GameAnalysisReportStore.debugSetInstance(GameAnalysisReportStore.memory());
  });

  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  testWidgets('arrow holds still work after swiping the notation panel', (
    tester,
  ) async {
    // The explorer cards overflow under the test font; that layout noise is
    // not what this test covers.
    final defaultOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      defaultOnError?.call(details);
    };
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final raws = [_rawGame(id: 'game-0', tourId: 'tour-1', board: 1)];
    final games = raws.map(GamesTourModel.fromGame).toList();

    final container = ProviderContainer(
      overrides: [
        boardFeatureTeachingTrackerProvider.overrideWith(
          (_) => BoardFeatureTeachingTracker(QuietBoardTeachingStore()),
        ),
        effectiveCountryProvider.overrideWithValue(const AsyncValue.loading()),
        gamesLocalStorage.overrideWith(
          (ref) => _FullCacheGamesLocalStorage(ref, {'tour-1': raws}),
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
        gamebaseOverlayEnabledProvider.overrideWith(
          _FakeGamebaseOverlayNotifier.new,
        ),
        eventNoSpoilersProvider.overrideWith(
          (ref, tourId) =>
              _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
        ),
        chessBoardPersistenceEnabledProvider.overrideWithValue(false),
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
    Future<void> settle([int frames = 10]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    final params = ChessBoardProviderParams(game: games.first, index: 0);
    ChessBoardStateNew state() =>
        container.read(chessBoardScreenProviderNew(params)).requireValue;

    final back = find.byKey(e2eKey(E2eIds.boardMoveBack)).first;
    final forward = find.byKey(e2eKey(E2eIds.boardMoveForward)).first;

    Future<void> hold(Finder f) async {
      final g = await tester.startGesture(tester.getCenter(f));
      await tester.pump(const Duration(milliseconds: 700));
      await g.up();
      await settle(5);
    }

    ScrollPosition notationPosition() {
      final scrollables = tester.stateList<ScrollableState>(
        find.byType(Scrollable),
      );
      return scrollables
          .map((s) => s.position)
          .firstWhere((p) => p.axis == Axis.vertical && p.maxScrollExtent > 0);
    }

    await hold(back);
    expect(state().analysisState.movePointer, isEmpty);
    await hold(forward);

    // Swipe the notation to the explorer and back.
    final panels = find.byKey(const ValueKey('analysis_panels_game-0'));
    expect(panels, findsOneWidget);
    // Partial drags that settle back, both directions.
    await tester.drag(panels, const Offset(-80, 0));
    await settle();
    await tester.drag(panels, const Offset(80, 0));
    await settle();
    await hold(back);
    await hold(forward);
    // Open explorer, hold there, come back.
    await tester.fling(panels, const Offset(-300, 0), 1500);
    await settle();
    await hold(back);
    await hold(forward);
    await tester.fling(panels, const Offset(300, 0), 1500);
    await settle();

    await hold(back);
    expect(state().analysisState.movePointer, isEmpty);
    expect(notationPosition().pixels, 0);

    await hold(forward);
    final pos = notationPosition();
    expect(state().analysisState.movePointer, isNotEmpty);
    expect(pos.pixels, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    FlutterError.onError = defaultOnError;
  });
}

Games _rawGame({
  required String id,
  required String tourId,
  required int board,
}) {
  return Games(
    id: id,
    roundId: 'round-1',
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
    pgn:
        '''
[Event "Dropdown jump"]
[White "White $id"]
[Black "Black $id"]
[Result "1-0"]

1. Nf3 Nf6 2. Ng1 Ng8 3. Nf3 Nf6 4. Ng1 Ng8 5. Nf3 Nf6 6. Ng1 Ng8 7. Nf3 Nf6 8. Ng1 Ng8 9. Nf3 Nf6 10. Ng1 Ng8 11. Nf3 Nf6 12. Ng1 Ng8 13. Nf3 Nf6 14. Ng1 Ng8 15. Nf3 Nf6 16. Ng1 Ng8 17. Nf3 Nf6 18. Ng1 Ng8 19. Nf3 Nf6 20. Ng1 Ng8 21. Nf3 Nf6 22. Ng1 Ng8 23. Nf3 Nf6 24. Ng1 Ng8 25. Nf3 Nf6 26. Ng1 Ng8 27. Nf3 Nf6 28. Ng1 Ng8 29. Nf3 Nf6 30. Ng1 Ng8 31. Nf3 Nf6 32. Ng1 Ng8 33. Nf3 Nf6 34. Ng1 Ng8 35. Nf3 Nf6 36. Ng1 Ng8 37. Nf3 Nf6 38. Ng1 Ng8 39. Nf3 Nf6 40. Ng1 Ng8 41. Nf3 Nf6 42. Ng1 Ng8 43. Nf3 Nf6 44. Ng1 Ng8 45. Nf3 Nf6 46. Ng1 Ng8 47. Nf3 Nf6 48. Ng1 Ng8 49. Nf3 Nf6 50. Ng1 Ng8 51. Nf3 Nf6 52. Ng1 Ng8 53. Nf3 Nf6 54. Ng1 Ng8 55. Nf3 Nf6 56. Ng1 Ng8 57. Nf3 Nf6 58. Ng1 Ng8 59. Nf3 Nf6 60. Ng1 Ng8 61. Nf3 Nf6 62. Ng1 Ng8 63. Nf3 Nf6 64. Ng1 Ng8 65. Nf3 Nf6 66. Ng1 Ng8 67. Nf3 Nf6 68. Ng1 Ng8 69. Nf3 Nf6 70. Ng1 Ng8 71. Nf3 Nf6 72. Ng1 Ng8 73. Nf3 Nf6 74. Ng1 Ng8 75. Nf3 Nf6 76. Ng1 Ng8 77. Nf3 Nf6 78. Ng1 Ng8 79. Nf3 Nf6 80. Ng1 Ng8 1-0
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
  }) async => const GamebaseResponse(
    status: 'success',
    data: GamebaseData(moves: []),
  );

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
