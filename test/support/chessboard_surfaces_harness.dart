// The live board screen as the chessboard surfaces' tests open their popups
// over it: a phone in portrait (or a tablet), four finished games of a round,
// the first one a 60-ply game so the notation is the busy page it is in use.
import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
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
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/date_time_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'board_feature_teaching_store.dart';

/// The board screen on screen, and the container its providers live in.
class SurfacesBoard {
  SurfacesBoard(this.tester, this.container, this._clock, this.games);

  final WidgetTester tester;
  final ProviderContainer container;

  /// The games of the round, the first one on screen.
  final List<GamesTourModel> games;
  final StreamController<DateTime> _clock;

  /// The app-bar chip that opens the game switcher.
  void tapGameSwitcher() {
    final selector = find.byKey(e2eKey(E2eIds.boardGameSelector)).first;
    final tap = find.descendant(
      of: selector,
      matching: find.byType(GestureDetector),
    );
    tester.widget<GestureDetector>(tap.first).onTap!();
  }

  /// The root navigator, for popping whatever route is on top.
  NavigatorState get navigator =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  /// Pumps 16 ms frames until nothing is scheduled (at most [cap]); returns
  /// how many it took.
  Future<int> settle({int cap = 240}) async {
    var frames = 0;
    while (tester.binding.hasScheduledFrame && frames < cap) {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
    }
    return frames;
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await _clock.close();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Pumps the board screen for four finished games, the first one [plies]
/// long, on a [size] view at [dpr].
Future<SurfacesBoard> pumpSurfacesBoard(
  WidgetTester tester, {
  bool light = false,
  Size size = const Size(393, 852),
  double dpr = 3,
  EdgeInsets safeArea = const EdgeInsets.only(top: 59, bottom: 34),
  int plies = 60,
  Widget Function(Widget board)? wrap,
  List<ProviderObserver> observers = const [],
  List<Override> extraOverrides = const [],
  EngineSettings engineSettings = const EngineSettings(
    showEngineAnalysis: false,
    showEngineGauge: false,
  ),
}) async {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = size * dpr;
  tester.view.padding = FakeViewPadding(
    top: safeArea.top * dpr,
    bottom: safeArea.bottom * dpr,
  );
  tester.view.viewPadding = FakeViewPadding(
    top: safeArea.top * dpr,
    bottom: safeArea.bottom * dpr,
  );
  addTearDown(tester.view.reset);
  // The screenshot nudge listens for screenshots through a plugin that a
  // widget test does not have.
  tester.binding.defaultBinaryMessenger.setMockStreamHandler(
    const EventChannel('com.ss.detect/events'),
    MockStreamHandler.inline(onListen: (_, _) {}),
  );

  final raws = [
    for (var i = 0; i < 4; i++)
      _finishedGame(id: 'game-$i', board: i + 1, plies: i == 0 ? plies : 12),
  ];
  final games = raws.map(GamesTourModel.fromGame).toList();
  final clock = StreamController<DateTime>.broadcast();
  final container = ProviderContainer(
    observers: observers,
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
      dateTimeProvider.overrideWith((ref) => clock.stream),
      localEvalCacheProvider.overrideWith(_FakeLocalEvalCache.new),
      engineSettingsProviderNew.overrideWith(
        () => _FakeEngineSettingsNotifier(engineSettings),
      ),
      boardEngineLinesVisibleProvider.overrideWith(_VisibleBoardLines.new),
      gamebaseOverlayEnabledProvider.overrideWith(
        _FakeGamebaseOverlayNotifier.new,
      ),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) =>
            _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
      ),
      chessBoardPersistenceEnabledProvider.overrideWithValue(false),
      spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
      ...extraOverrides,
    ],
  );

  Widget board = MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorObservers: [routeObserver],
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
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
  );
  if (wrap != null) board = wrap(board);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: board),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  // The pinch coachmark covers the board on a first visit.
  final dismissHint = find.text('Got it');
  if (dismissHint.evaluate().isNotEmpty) {
    await tester.tap(dismissHint.first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  final handle = SurfacesBoard(tester, container, clock, games);
  await handle.settle();
  return handle;
}

/// [plies] seeded random legal moves with clock comments, and where they end.
({String movetext, String fen}) _randomGame(int plies, int seed) {
  Position position = Chess.initial;
  final random = math.Random(seed);
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

Games _finishedGame({
  required String id,
  required int board,
  required int plies,
}) {
  final played = _randomGame(plies, 7 + board);
  const names = [
    ('Firouzja, Alireza', 'Caruana, Fabiano'),
    ('Nakamura, Hikaru', 'Gukesh, D'),
    ('Abdusattorov, Nodirbek', 'Erigaisi, Arjun'),
    ('So, Wesley', 'Praggnanandhaa, R'),
  ];
  final (white, black) = names[(board - 1) % names.length];
  return Games(
    id: id,
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: 'tour-1',
    tourSlug: 'tour-1',
    players: [
      _player(name: white, fideId: board * 2 + 1),
      _player(name: black, fideId: board * 2 + 2),
    ],
    boardNr: board,
    status: '1-0',
    fen: played.fen,
    pgn:
        '''
[Event "Norway Chess 2026"]
[White "$white"]
[Black "$black"]
[Result "1-0"]

${played.movetext}1-0
''',
  );
}

Player _player({required String name, required int fideId}) {
  return Player(
    name: name,
    title: 'GM',
    rating: 2750,
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
  _FakeEngineSettingsNotifier(this.settings);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;

  @override
  Future<void> setEngineSource(EngineSource source) async {
    state = AsyncValue.data(state.value!.withSelectedSource(source));
  }

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

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

// Re-exported for the tests that open the theme themselves.
ThemeData surfacesTheme({required bool light}) =>
    light ? AppTheme.lightTheme : AppTheme.darkTheme;
