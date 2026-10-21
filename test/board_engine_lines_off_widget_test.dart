import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/board_engine_lines_visibility_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
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
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
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
      'explorer_panel_walkthrough_dont_show': true,
      'like_walkthrough_dont_show': true,
    });
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-anon-key',
    );
    GameAnalysisReportStore.debugSetInstance(GameAnalysisReportStore.memory());
  });
  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  for (final style in EngineLinesView.values) {
    testWidgets(
      'in-game Off hides $style while a real board eval request completes',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final raw = _rawGame();
        final game = GamesTourModel.fromGame(raw);
        final pendingEval = Completer<CloudEval>();
        CascadeEvalParams? request;
        var requestCount = 0;
        final store = _VisibilityStore();
        final container = ProviderContainer(
          overrides: [
            boardFeatureTeachingTrackerProvider.overrideWith(
              (_) => BoardFeatureTeachingTracker(QuietBoardTeachingStore()),
            ),
            effectiveCountryProvider.overrideWithValue(
              const AsyncValue.loading(),
            ),
            gamesLocalStorage.overrideWith((ref) => _GamesCache(ref, raw)),
            gameRepositoryProvider.overrideWithValue(_GamesRepo(raw)),
            gamebaseRepositoryProvider.overrideWithValue(_GamebaseRepo()),
            gameStreamRepositoryProvider.overrideWithValue(_GameStream()),
            localEvalCacheProvider.overrideWith(_EvalCache.new),
            engineSettingsProviderNew.overrideWith(
              () => _EngineSettings(style),
            ),
            boardEngineLinesVisibilityStoreProvider.overrideWithValue(store),
            gamebaseOverlayEnabledProvider.overrideWith(_Overlay.new),
            eventNoSpoilersProvider.overrideWith(
              (ref, tourId) => _Spoilers(ref: ref, tourId: tourId),
            ),
            chessBoardPersistenceEnabledProvider.overrideWithValue(false),
            spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
            // Only the cached/backend result is a fixture. The board notifier,
            // request lifecycle, PV parsing, eval bar and panel are production code.
            // Native Stockfish remains intentionally disabled in debug.
            cascadeEvalProviderForBoard.overrideWith((ref, params) {
              request = params;
              requestCount++;
              return pendingEval.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [AppColors.dark],
              ),
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return ChessBoardScreenNew(
                    currentIndex: 0,
                    games: [game],
                    viewSource: ChessboardView.tour,
                  );
                },
              ),
            ),
          ),
        );
        Future<void> frames([int count = 10]) async {
          for (var i = 0; i < count; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        await frames(20);
        expect(request, isNotNull);
        final provider = chessBoardScreenProviderNew(
          ChessBoardProviderParams(game: game, index: 0),
        );
        final board = container.read(provider.notifier);
        final before = container.read(provider).requireValue;
        expect(before.showEngineAnalysis, isTrue);
        expect(before.isEvaluating, isTrue);
        expect(find.byKey(e2eKey(E2eIds.boardPvList)), findsOneWidget);
        expect(find.byKey(e2eKey(E2eIds.boardEvalBar)), findsOneWidget);
        final settingsBefore = container
            .read(engineSettingsProviderNew)
            .requireValue;
        final requestsBefore = requestCount;
        // Toggle the very same notifier called by Settings, without remounting
        // the board or mutating Computer Analysis.
        final off = container
            .read(boardEngineLinesVisibleProvider.notifier)
            .setVisible(false);
        await tester.pump();
        await off;
        await frames(4);
        expect(find.byKey(e2eKey(E2eIds.boardPvList)), findsNothing);
        expect(find.byKey(e2eKey(E2eIds.boardEvalBar)), findsOneWidget);
        expect(container.read(provider.notifier), same(board));
        expect(container.read(provider).requireValue, same(before));
        expect(
          container.read(engineSettingsProviderNew).requireValue,
          same(settingsBefore),
        );
        expect(requestCount, requestsBefore);

        final position = Position.setupPosition(
          Rule.chess,
          Setup.parseFen(request!.fen),
        );
        final legal = makeLegalMoves(position).entries.first;
        final move = NormalMove(from: legal.key, to: legal.value.first);
        pendingEval.complete(
          CloudEval(
            fen: request!.fen,
            knodes: 120,
            depth: 22,
            pvs: [Pv(moves: move.uci, cp: 125)],
            requestedMultiPv: 1,
          ),
        );
        await frames(20);
        final after = container.read(provider).requireValue;
        expect(after.isEvaluating, isFalse);
        expect(after.evaluation?.abs(), 1.25);
        expect(after.principalVariations, hasLength(1));
        expect(after.showEngineAnalysis, isTrue);
        expect(after.showPrincipalVariations, isTrue);
        expect(
          after.analysisState.movePointer,
          before.analysisState.movePointer,
        );
        expect(
          after.analysisState.position.fen,
          before.analysisState.position.fen,
        );
        expect(find.byKey(e2eKey(E2eIds.boardPvList)), findsNothing);
        final bar = tester.widget<EvaluationBarWidget>(
          find.byKey(e2eKey(E2eIds.boardEvalBar)),
        );
        expect(bar.evaluation, after.evaluation);
        expect(bar.isEvaluating, isFalse);
        expect(
          container
              .read(engineDepthTrackerProvider)[EngineComponent.evaluationGauge]
              ?.depth,
          22,
        );
        expect(after.shapes?.whereType<Arrow>(), isNotEmpty);
        // Re-enable the retained layout without losing results/depth/position.
        final enable = container
            .read(boardEngineLinesVisibleProvider.notifier)
            .setVisible(true);
        await tester.pump();
        await enable;
        await frames(5);
        expect(find.byKey(e2eKey(E2eIds.boardPvList)), findsOneWidget);
        expect(container.read(provider).requireValue, same(after));
        expect(
          container
              .read(engineSettingsProviderNew)
              .requireValue
              .engineLinesView,
          style,
        );
        expect(requestCount, requestsBefore);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump();
      },
    );
  }
}

Games _rawGame() => Games(
  id: 'engine-lines-fixture',
  roundId: 'round-fixture',
  roundSlug: 'round-fixture',
  tourId: 'tour-fixture',
  tourSlug: 'tour-fixture',
  players: [
    Player(
      name: 'White Fixture',
      title: '',
      rating: 2000,
      fideId: 0,
      fed: '',
      clock: 0,
      team: '',
    ),
    Player(
      name: 'Black Fixture',
      title: '',
      rating: 2000,
      fideId: 0,
      fed: '',
      clock: 0,
      team: '',
    ),
  ],
  boardNr: 1,
  status: '*',
  pgn:
      '[Event "Fixture"]\n[White "White Fixture"]\n[Black "Black Fixture"]\n[Result "*"]\n\n1. e4 e5 *',
);

class _VisibilityStore extends BoardEngineLinesVisibilityStore {
  bool? value;
  @override
  Future<bool?> load() async => value;
  @override
  Future<void> save(bool visible) async {
    value = visible;
  }
}

class _EngineSettings extends EngineSettingsNotifierNew {
  _EngineSettings(this.style);
  final EngineLinesView style;
  @override
  Future<EngineSettings> build() async =>
      EngineSettings(engineLinesView: style, principalVariationIndex: 0);
}

class _GamesRepo extends GameRepository {
  _GamesRepo(this.raw);
  final Games raw;
  @override
  Future<Games> getGameWithPGN(String gameId) async => raw;
  @override
  Future<String?> getGamePgn(String gameId) async => raw.pgn;
}

class _GamesCache extends GamesLocalStorage {
  _GamesCache(super.ref, this.raw);
  final Games raw;
  @override
  Future<List<Games>> getCachedGames(String tourId) async => [raw];
  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
    String? priorityRoundId,
    void Function(List<Games>)? onPriorityRound,
    Future<void> Function()? afterPriorityRound,
    bool rethrowErrors = false,
  }) async => [raw];
}

class _GamebaseRepo extends GamebaseRepository {
  _GamebaseRepo()
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'fixture');
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
}

class _GameStream extends GameStreamRepository {
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

class _EvalCache extends LocalEvalCache {
  _EvalCache(super.ref);
  @override
  Future<CloudEval?> fetch(
    String fen, {
    int? multiPV,
    int minDepth = 0,
  }) async => null;
  @override
  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {}
}

class _Overlay extends GamebaseOverlayEnabledNotifier {
  @override
  Future<bool> build() async => false;
}

class _Spoilers extends EventNoSpoilersController {
  _Spoilers({required super.ref, required super.tourId});
  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}
