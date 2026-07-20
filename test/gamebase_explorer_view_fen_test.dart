import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/widgets/board_opening_explorer_panel.dart';
import 'package:chessever2/screens/gamebase/widgets/gamebase_explorer_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository()
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  String? lastFen;
  List<String>? lastMoves;

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
  }) async {
    lastFen = fen;
    lastMoves = List<String>.from(moves);
    return const GamebaseResponse(
      status: 'success',
      data: GamebaseData(moves: []),
    );
  }
}

({List<Move> moves, Position position}) _buildLongLegalLine() {
  final moves = <Move>[];
  Position position = Chess.initial;

  void play(String uci) {
    final move = NormalMove.fromUci(uci);
    if (!position.isLegal(move)) {
      throw StateError('$uci is not legal from ${position.fen}');
    }
    moves.add(move);
    position = position.play(move);
  }

  for (var i = 0; i < 37; i++) {
    play('g1f3');
    play('g8f6');
    play('f3g1');
    play('f6g8');
  }
  play('g1f3');
  play('g8f6');

  return (moves: moves, position: position);
}

GamesTourModel _dummyGame() {
  final white = PlayerCard(
    name: 'White',
    federation: 'TR',
    title: '',
    rating: 0,
    countryCode: 'TR',
    team: null,
  );
  final black = PlayerCard(
    name: 'Black',
    federation: 'TR',
    title: '',
    rating: 0,
    countryCode: 'TR',
    team: null,
  );

  return GamesTourModel(
    gameId: 'g1',
    whitePlayer: white,
    blackPlayer: black,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'r1',
    tourId: 't1',
  );
}

void main() {
  testWidgets('GamebaseExplorerView uses analysis position FEN', (
    tester,
  ) async {
    final fakeRepository = _FakeGamebaseRepository();
    final container = ProviderContainer(
      overrides: [gamebaseRepositoryProvider.overrideWithValue(fakeRepository)],
    );
    addTearDown(container.dispose);

    const analysisFen =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
    final position = Chess.fromSetup(Setup.parseFen(analysisFen));

    final state = ChessBoardStateNew(
      game: _dummyGame(),
      isAnalysisMode: true,
      position: null,
      analysisState: AnalysisBoardState(position: position),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: GamebaseExplorerView(
                  state: state,
                  onMoveSelected: (_) {},
                  showFilterPanel: false,
                ),
              );
            },
          ),
        ),
      ),
    );

    // useEffect schedules setPosition via a microtask.
    await tester.pump();

    expect(container.read(gamebaseExplorerProvider).currentFen, analysisFen);

    // Let the debounced fetch timer complete to avoid pending timers.
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('GamebaseExplorerView replays flat history to its deep FEN', (
    tester,
  ) async {
    final fakeRepository = _FakeGamebaseRepository();
    final container = ProviderContainer(
      overrides: [gamebaseRepositoryProvider.overrideWithValue(fakeRepository)],
    );
    addTearDown(container.dispose);

    final longLine = _buildLongLegalLine();
    final state = ChessBoardStateNew(
      game: _dummyGame(),
      isAnalysisMode: true,
      position: null,
      analysisState: AnalysisBoardState(
        position: longLine.position,
        allMoves: longLine.moves,
        currentMoveIndex: longLine.moves.length - 2,
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: GamebaseExplorerView(
                  state: state,
                  onMoveSelected: (_) {},
                  showFilterPanel: false,
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(fakeRepository.lastFen, longLine.position.fen);
    expect(fakeRepository.lastMoves, hasLength(150));
    expect(fakeRepository.lastMoves, longLine.moves.map((m) => m.uci));
  });

  testWidgets(
    'board explorer uses the canonical game path when the flat index lags at ply 21',
    (tester) async {
      final fakeRepository = _FakeGamebaseRepository();
      final container = ProviderContainer(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );
      var containerDisposed = false;
      addTearDown(() {
        if (!containerDisposed) container.dispose();
      });

      final activeGame = ChessGame.fromPgn(
        'deep-node',
        '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 '
            '5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O '
            '9. h3 Nb8 10. d4 Nbd7 11. c4',
      );
      final expectedMoves = activeGame.mainline
          .map((move) => move.uci)
          .toList(growable: false);
      final targetPosition = Position.setupPosition(
        Rule.chess,
        Setup.parseFen(activeGame.mainline.last.fen),
      );

      expect(expectedMoves, hasLength(21));
      expect(
        targetPosition.fen,
        'r1bq1rk1/2pnbppp/p2p1n2/1p2p3/2PPP3/1B3N1P/PP3PP1/RNBQR1K1 b - - 0 11',
      );

      final state = ChessBoardStateNew(
        game: _dummyGame(),
        isAnalysisMode: true,
        position: null,
        analysisState: AnalysisBoardState(
          position: targetPosition,
          startingPosition: Chess.initial,
          allMoves: expectedMoves.map(NormalMove.fromUci).toList(),
          // The navigator pointer is authoritative. The flat index can lag
          // briefly while a live-game update and navigator sync interleave.
          game: activeGame,
          movePointer: const [20],
          currentMoveIndex: 19,
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: BoardOpeningExplorerPanel(
                    state: state,
                    onMoveSelected: (_) {},
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();
      expect(
        container.read(gamebaseExplorerProvider).exploredMoves,
        expectedMoves,
      );

      await tester.pump(const Duration(milliseconds: 250));
      expect(fakeRepository.lastMoves, expectedMoves);

      // BoardOpeningExplorerPanel mounts the app's subscription provider,
      // which owns a periodic timer. Dispose it inside fake time so the test
      // cannot leak that timer into Flutter's invariant check.
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      containerDisposed = true;
    },
  );
}
