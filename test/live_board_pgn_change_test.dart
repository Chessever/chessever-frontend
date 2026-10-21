import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
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
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/board_feature_teaching_store.dart';

const _moves = ['1. e4 e5', '1. d4 d5', '1. c4 c5'];
const _lastUci = ['e7e5', 'd7d5', 'c7c5'];
const _fens = [
  'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
  'rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq d6 0 2',
  'rnbqkbnr/pp1ppppp/8/2p5/2P5/8/PP1PPPPP/RNBQKBNR w KQkq c6 0 2',
];

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

  Future<(ProviderContainer, _FakeGameStreamRepository, List<GamesTourModel>)>
  boot(WidgetTester tester) async {
    final raws = List<Games>.generate(
      3,
      (i) => _rawGame(id: 'game-$i', tourId: 'tour-1', board: i),
    );
    final games = raws.map(GamesTourModel.fromGame).toList();
    final stream = _FakeGameStreamRepository();
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
        gameStreamRepositoryProvider.overrideWithValue(stream),
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
    container.read(shouldStreamProvider.notifier).state = false;
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
    return (container, stream, games);
  }

  List<String> mainline(ProviderContainer c, ChessBoardProviderParams params) =>
      [
        for (final move
            in c
                .read(chessBoardScreenProviderNew(params))
                .requireValue
                .analysisState
                .game!
                .mainline)
          move.san,
      ];

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> live(
    WidgetTester tester,
    _FakeGameStreamRepository stream,
    String movesText,
    String lastUci,
  ) async {
    stream.controllers['game-0']?.add({
      'id': 'game-0',
      'pgn': '[Event "Live PGN change"]\n[Result "*"]\n\n$movesText *',
      'fen': null,
      'last_move': lastUci,
      'status': '*',
    });
    await settle(tester);
  }

  testWidgets(
    'a live row that moves before its PGN leaves board moves and notation working',
    (tester) async {
      final (c, stream, games) = await boot(tester);
      final params = ChessBoardProviderParams(game: games[0], index: 0);
      final notifier = c.read(chessBoardScreenProviderNew(params).notifier);

      // FEN/last_move reach the next ply while the PGN column is unchanged.
      stream.controllers['game-0']!.add({
        'id': 'game-0',
        'pgn': games[0].pgn,
        'fen': 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
        'last_move': 'g1f3',
        'status': '*',
      });
      await settle(tester);
      expect(mainline(c, params), ['e4', 'e5', 'Nf3']);

      // The reader branches off move 1...e5. This used to land on a detached
      // navigator parked on the start position and be dropped as out of sync.
      notifier.goToMovePointer([1]);
      notifier.onAnalysisMove(NormalMove.fromUci('b1c3'));
      await tester.pump(const Duration(milliseconds: 50));
      final afterMove = c
          .read(chessBoardScreenProviderNew(params))
          .requireValue;
      expect(afterMove.analysisState.position.fen, contains('2N5'));
      expect(
        afterMove.analysisState.game!.mainline[1].variations?.single.single.san,
        'Nc3',
      );

      // The next broadcast move still reaches the notation.
      await live(tester, stream, '1. e4 e5 2. Nf3 Nc6', 'b8c6');
      expect(mainline(c, params), ['e4', 'e5', 'Nf3', 'Nc6']);
      expect(
        c
            .read(chessBoardScreenProviderNew(params))
            .requireValue
            .analysisState
            .position
            .fen,
        contains('2N5'),
        reason: 'the reader stays on their own branch',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      c.dispose();
    },
  );

  testWidgets(
    'a broadcast correction swaps the move instead of resetting the board',
    (tester) async {
      final (c, stream, games) = await boot(tester);
      final params = ChessBoardProviderParams(game: games[0], index: 0);

      await live(tester, stream, '1. e4 e5 2. Nf3', 'g1f3');
      await live(tester, stream, '1. e4 e5 2. Nc3', 'b1c3');
      var board = c.read(chessBoardScreenProviderNew(params)).requireValue;
      expect(mainline(c, params), ['e4', 'e5', 'Nc3']);
      expect(board.analysisState.movePointer, [2]);
      expect(board.analysisState.position.fen, contains('2N5'));

      await live(tester, stream, '1. e4 e5 2. Nc3 Nf6', 'g8f6');
      board = c.read(chessBoardScreenProviderNew(params)).requireValue;
      expect(mainline(c, params), ['e4', 'e5', 'Nc3', 'Nf6']);
      expect(board.analysisState.movePointer, [3], reason: 'still following');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      c.dispose();
    },
  );
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
    status: '*',
    lastMove: _lastUci[board % 3],
    fen: _fens[board % 3],
    pgn:
        '''
[Event "Live PGN change"]
[White "White $id"]
[Black "Black $id"]
[Result "*"]

${_moves[board % 3]} *
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
  final controllers = <String, StreamController<Map<String, dynamic>?>>{};

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
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) =>
      (controllers[gameId] ??= StreamController.broadcast()).stream;

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
