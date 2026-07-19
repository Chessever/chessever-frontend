import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_sheet.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('review eligibility and reveal state follow the configured game', () {
    final controller = MobileGameReviewController();
    addTearDown(controller.dispose);
    final game = ChessGame.fromPgn('eligibility', '1. e4 e5 *');

    controller.configure(
      game: game,
      active: false,
      finished: false,
      whiteRating: 0,
      blackRating: 0,
    );
    expect(controller.state.isEligible, isFalse);
    expect(controller.state.unavailableMessage, contains('when the game ends'));

    controller.configure(
      game: game,
      active: false,
      finished: true,
      whiteRating: 0,
      blackRating: 0,
    );
    expect(controller.state.isEligible, isTrue);
    expect(controller.state.reportState.status, GameReportStatus.idle);
    expect(controller.state.classificationsRevealed, isFalse);
    controller.reveal();
    expect(controller.state.classificationsRevealed, isTrue);
  });

  testWidgets('Game Analysis button exposes progress and unavailable states', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              GameAnalysisButton(
                state: MobileGameReviewState(
                  isEligible: true,
                  reportState: GameReportState(
                    status: GameReportStatus.running,
                    progress: 0.42,
                  ),
                ),
                onPressed: _noop,
              ),
              GameAnalysisButton(
                state: MobileGameReviewState(
                  unavailableMessage: 'Game analysis starts when the game ends',
                ),
                onPressed: _noop,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Game Analysis · 42%'), findsOneWidget);
    expect(
      find.text('Game analysis starts when the game ends'),
      findsOneWidget,
    );
  });

  testWidgets('completed review shows players, accuracy, recap, and graph', (
    tester,
  ) async {
    final chessGame = ChessGame.fromPgn(
      'sheet-test',
      '[White "Ada"]\n[Black "Grace"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
    );
    final reportController = GameAnalysisReportController(
      evaluator: _evaluator,
    );
    final controller = MobileGameReviewController(
      reportController: reportController,
    );
    addTearDown(controller.dispose);
    final game = _game();
    await tester.runAsync(() async {
      controller.configure(
        game: chessGame,
        active: true,
        finished: true,
        whiteRating: game.whitePlayer.rating,
        blackRating: game.blackPlayer.rating,
      );
      for (
        var i = 0;
        i < 20 &&
            controller.state.reportState.status != GameReportStatus.completed;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    expect(controller.state.reportState.status, GameReportStatus.completed);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => FilledButton(
                  onPressed:
                      () => showMobileGameReviewSheet(
                        context: context,
                        controller: controller,
                        game: game,
                        activePly: 0,
                        onJumpToPly: (_) {},
                      ),
                  child: const Text('Open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Game Review'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('Forced'), findsOneWidget);
    expect(find.text('1-0'), findsOneWidget);

    await tester.drag(find.text('Game Review'), const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('OPENING'), findsOneWidget);
    expect(find.text('MIDDLEGAME'), findsOneWidget);
    expect(find.text('ENDGAME'), findsOneWidget);

    Navigator.of(tester.element(find.text('Game Review'))).pop();
    await tester.pump(const Duration(milliseconds: 500));
  });
}

void _noop() {}

Future<EnhancedCloudEval> _evaluator(
  String fen, {
  required int depth,
  required int multiPv,
  required String ownerId,
  void Function(int reachedDepth, int knodes)? onProgress,
}) async {
  onProgress?.call(depth, 500);
  return EnhancedCloudEval(
    fen: fen,
    knodes: 500,
    depth: depth,
    pvs: [Pv(moves: 'a2a3', cp: 10)],
    requestedMultiPv: multiPv,
  );
}

GamesTourModel _game() => GamesTourModel(
  gameId: 'review-game',
  whitePlayer: PlayerCard(
    name: 'Ada Lovelace',
    federation: '',
    title: '',
    rating: 2100,
    countryCode: '',
    team: null,
  ),
  blackPlayer: PlayerCard(
    name: 'Grace Hopper',
    federation: '',
    title: '',
    rating: 2050,
    countryCode: '',
    team: null,
  ),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.whiteWins,
  roundId: 'round',
  tourId: 'tour',
);
