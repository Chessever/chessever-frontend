import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_engine_lines_visibility_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/gamebase_overlay_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
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
import 'package:chessever2/utils/date_time_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/board_feature_teaching_store.dart';

/// What the focused board pays for one live event: widget builds, render
/// object layouts and paints, while a game is running.
///
/// Regressions this guards (measured on an 80-ply live game, phone portrait):
/// * an engine line rebuilt the notation (~490 builds, ~470 layouts) and the
///   app bar (~180 builds) though neither reads the engine's fields;
/// * each frame of the eval bar's spring scheduled the board LayoutBuilder's
///   layout and repainted the whole page (~264 paints a frame);
/// * the unseen-moves blink did the same for the page and the notation
///   (~1,160 paints a frame, for as long as moves were unseen);
/// * a clock tick repainted the whole page (~250 paints).
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

  testWidgets('a clock tick rebuilds the clock and repaints its row only', (
    tester,
  ) async {
    final board = await _pumpLiveBoard(tester);
    for (var tick = 0; tick < 2; tick++) {
      final cost = await _measure(tester, () async {
        board.tick();
        await tester.pump();
        await tester.pump();
      });
      // The countdown text and its sub-second slot, nothing around them.
      expect(cost.builds, lessThanOrEqualTo(6), reason: cost.report);
      expect(
        cost.regions.keys,
        everyElement(isIn(['PlayerFirstRowDetailWidget', 'other'])),
        reason: cost.report,
      );
      expect(cost.paints, lessThan(100), reason: cost.report);
    }
    await board.dispose();
  });

  testWidgets('an engine line leaves the notation and the app bar alone', (
    tester,
  ) async {
    final board = await _pumpLiveBoard(tester);
    // The first line moves the bar off its starting state; measure steady
    // ones after it.
    await board.engineLine(0.3);
    await tester.pump(const Duration(seconds: 1));
    for (final eval in [0.6, -0.4]) {
      final cost = await _measure(tester, () async {
        await board.engineLine(eval);
        await tester.pump();
      });
      expect(cost.regions['_MovesDisplay'], isNull, reason: cost.report);
      expect(cost.regions['_AppBar'], isNull, reason: cost.report);
      expect(cost.builds, lessThan(250), reason: cost.report);
      expect(cost.layouts, lessThan(60), reason: cost.report);
      expect(cost.paints, lessThan(200), reason: cost.report);

      // The bar then springs to the new value by paint alone, in its layer.
      final spring = await _measure(tester, () async {
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      });
      expect(spring.builds, 0, reason: spring.report);
      expect(spring.layouts, 0, reason: spring.report);
      expect(spring.paints, lessThanOrEqualTo(60), reason: spring.report);
    }
    await board.dispose();
  });

  testWidgets('the unseen-moves blink repaints nothing around it', (
    tester,
  ) async {
    final board = await _pumpLiveBoard(tester);
    board.update((state) => state.copyWith(hasUnseenMoves: true));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final cost = await _measure(tester, () async {
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    });
    expect(cost.builds, 0, reason: cost.report);
    expect(cost.layouts, 0, reason: cost.report);
    expect(cost.paints, lessThanOrEqualTo(60), reason: cost.report);
    board.update((state) => state.copyWith(hasUnseenMoves: false));
    await tester.pump(const Duration(milliseconds: 16));
    await board.dispose();
  });

  testWidgets('a quiet board does no work between frames', (tester) async {
    final board = await _pumpLiveBoard(tester);
    final cost = await _measure(tester, () async {
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    });
    expect(cost.builds + cost.layouts + cost.paints, 0, reason: cost.report);
    await board.dispose();
  });
}

/// Build, layout and paint counts by type, and builds by board region.
class _Cost {
  final regions = <String, int>{};
  final buildsByType = <String, int>{};
  final layoutsByType = <String, int>{};
  final paintsByType = <String, int>{};

  int get builds => buildsByType.values.fold(0, (a, b) => a + b);
  int get layouts => layoutsByType.values.fold(0, (a, b) => a + b);
  int get paints => paintsByType.values.fold(0, (a, b) => a + b);

  String get report {
    String top(Map<String, int> counts) {
      final entries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return entries.take(20).map((e) => '${e.key}=${e.value}').join(', ');
    }

    return 'builds=$builds layouts=$layouts paints=$paints\n'
        '  regions: ${top(regions)}\n'
        '  builds: ${top(buildsByType)}\n'
        '  layouts: ${top(layoutsByType)}\n'
        '  paints: ${top(paintsByType)}';
  }
}

/// The board's parts a rebuilt widget is counted under.
const _regions = {
  '_AppBar',
  '_BottomNavBar',
  'PlayerFirstRowDetailWidget',
  '_MovesDisplay',
  '_PrincipalVariationList',
  '_AnalysisBoard',
  'EvaluationBarWidget',
  '_AnalysisSwipePanels',
};

void _count(Map<String, int> counts, String key) =>
    counts.update(key, (n) => n + 1, ifAbsent: () => 1);

/// Counts every widget rebuilt, render object laid out and render object
/// painted while [run] pumps.
Future<_Cost> _measure(WidgetTester tester, Future<void> Function() run) async {
  final cost = _Cost();
  final print = debugPrint;
  final layoutName = RegExp(r'\) (\S+?)#');
  debugOnRebuildDirtyWidget = (element, _) {
    final type = element.widget.runtimeType.toString();
    var region = _regions.contains(type) ? type : 'other';
    if (region == 'other') {
      element.visitAncestorElements((ancestor) {
        final name = ancestor.widget.runtimeType.toString();
        if (!_regions.contains(name)) return true;
        region = name;
        return false;
      });
    }
    _count(cost.regions, region);
    _count(cost.buildsByType, type);
  };
  debugPrintLayouts = true;
  debugPrint = (message, {wrapWidth}) {
    final name = message == null || !message.startsWith('Laying out')
        ? null
        : layoutName.firstMatch(message)?.group(1);
    if (name != null) {
      _count(cost.layoutsByType, name);
    } else if (message != null && !message.startsWith('Laying out')) {
      print(message, wrapWidth: wrapWidth);
    }
  };
  debugProfilePaintsEnabled = true;
  FlutterTimeline.debugCollectionEnabled = true;
  try {
    await run();
  } finally {
    for (final block in FlutterTimeline.debugCollect().timedBlocks) {
      if (block.name.startsWith('Render') || block.name.startsWith('_Render')) {
        _count(cost.paintsByType, block.name);
      }
    }
    FlutterTimeline.debugCollectionEnabled = false;
    debugProfilePaintsEnabled = false;
    debugPrintLayouts = false;
    debugPrint = print;
    debugOnRebuildDirtyWidget = null;
  }
  return cost;
}

class _LiveBoard {
  _LiveBoard(this.tester, this.container, this.params, this._clock);

  final WidgetTester tester;
  final ProviderContainer container;
  final ChessBoardProviderParams params;
  final StreamController<DateTime> _clock;
  DateTime _now = DateTime.now();

  /// One second of the running clock.
  void tick() {
    _now = _now.add(const Duration(seconds: 1));
    _clock.add(_now);
  }

  /// Puts a new board state, as the engine and the live stream do.
  void update(ChessBoardStateNew Function(ChessBoardStateNew state) change) {
    final provider = chessBoardScreenProviderNew(params);
    final notifier = container.read(provider.notifier);
    // ignore: invalid_use_of_protected_member
    notifier.state = AsyncValue.data(
      change(container.read(provider).requireValue),
    );
  }

  /// One engine info line: a new evaluation while the search runs.
  Future<void> engineLine(double evaluation) async => update(
    (state) => state.copyWith(evaluation: evaluation, isEvaluating: true),
  );

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// The focused board on a phone in portrait, showing a live 80-ply game
/// whose white clock is running.
Future<_LiveBoard> _pumpLiveBoard(WidgetTester tester) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final raw = _liveGame(
    id: 'live-1',
    lastMoveTime: DateTime.now().subtract(const Duration(seconds: 5)),
  );
  final game = GamesTourModel.fromGame(raw);
  final clock = StreamController<DateTime>.broadcast();
  final updates = StreamController<Map<String, dynamic>?>.broadcast();
  addTearDown(clock.close);
  addTearDown(updates.close);
  final container = _boardTestContainer(
    gamesByTour: {
      raw.tourId: [raw],
    },
    gameRepository: _ImmediateGameRepository({raw.id: raw}),
    updates: updates,
    clock: clock,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorObservers: [routeObserver],
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
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
  final board = _LiveBoard(
    tester,
    container,
    ChessBoardProviderParams(game: game, index: 0),
    clock,
  );
  clock.add(board._now);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byType(ChessBoardScreenNew), findsOneWidget);
  return board;
}

/// [plies] seeded random legal moves with clock comments, and the position
/// they reach.
({String movetext, String fen}) _randomGame(int plies) {
  Position position = Chess.initial;
  final random = math.Random(7);
  final movetext = StringBuffer();
  String two(int n) => n.toString().padLeft(2, '0');
  for (var ply = 0; ply < plies; ply++) {
    final moves = [
      for (final entry in position.legalMoves.entries)
        for (final to in entry.value.squares)
          NormalMove(from: entry.key, to: to),
    ];
    if (moves.isEmpty) break;
    final (next, san) = position.makeSan(moves[random.nextInt(moves.length)]);
    final seconds = 3600 - ply * 20;
    if (ply.isEven) movetext.write('${ply ~/ 2 + 1}. ');
    movetext.write(
      '$san {[%clk ${seconds ~/ 3600}:${two(seconds % 3600 ~/ 60)}:'
      '${two(seconds % 60)}]} ',
    );
    position = next;
  }
  return (movetext: movetext.toString(), fen: position.fen);
}

Games _liveGame({required String id, required DateTime lastMoveTime}) {
  final played = _randomGame(80);
  return Games(
    id: id,
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: 'live-tour',
    tourSlug: 'live-tour',
    players: [
      _player(name: 'Wiśniewska-Kowalczyk, Aleksandra', fideId: 11),
      _player(name: 'Caruana, Fabiano', fideId: 12),
    ],
    boardNr: 1,
    status: '*',
    fen: played.fen,
    lastMoveTime: lastMoveTime,
    lastClockWhite: 3600,
    lastClockBlack: 3500,
    pgn:
        '''
[Event "Live"]
[White "Wiśniewska-Kowalczyk, Aleksandra"]
[Black "Caruana, Fabiano"]
[Result "*"]

${played.movetext}*
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

ProviderContainer _boardTestContainer({
  required Map<String, List<Games>> gamesByTour,
  required GameRepository gameRepository,
  required StreamController<Map<String, dynamic>?> updates,
  required StreamController<DateTime> clock,
}) {
  return ProviderContainer(
    overrides: [
      boardFeatureTeachingTrackerProvider.overrideWith(
        (_) => BoardFeatureTeachingTracker(QuietBoardTeachingStore()),
      ),
      effectiveCountryProvider.overrideWithValue(const AsyncValue.loading()),
      gamesLocalStorage.overrideWith(
        (ref) => _FullCacheGamesLocalStorage(ref, gamesByTour),
      ),
      gameRepositoryProvider.overrideWithValue(gameRepository),
      gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
      gameStreamRepositoryProvider.overrideWithValue(
        _FakeGameStreamRepository(updates),
      ),
      dateTimeProvider.overrideWith((ref) => clock.stream),
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
    ],
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
  _FakeGameStreamRepository(this.updates);

  final StreamController<Map<String, dynamic>?> updates;

  @override
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) =>
      updates.stream;

  @override
  Stream<LiveGameUpdate?> subscribeToLiveGameUpdate(String gameId) =>
      const Stream.empty();

  @override
  Stream<Map<String, LiveGameUpdate>> subscribeToLiveGameUpdatesBatch(
    List<String> gameIds,
  ) => const Stream.empty();

  @override
  Stream<Map<String, LiveGameUpdate>> subscribeToLiveGameUpdatesForRound(
    String roundId,
  ) => const Stream.empty();

  @override
  Stream<Map<String, LiveGameUpdate>> subscribeToLiveGameUpdatesForTour(
    String tourId,
  ) => const Stream.empty();

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
  Future<EngineSettings> build() async => const EngineSettings();

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
