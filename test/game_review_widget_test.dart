import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_sheet.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('review eligibility and reveal state follow the configured game', () {
    expect(
      MobileGameReviewController.defaultAutoStartDelay,
      const Duration(seconds: 2),
    );
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
    expect(controller.reviewState.isEligible, isFalse);
    expect(controller.reviewState.unavailableMessage, contains('when the game ends'));

    controller.configure(
      game: game,
      active: false,
      finished: true,
      whiteRating: 0,
      blackRating: 0,
    );
    expect(controller.reviewState.isEligible, isTrue);
    expect(controller.reviewState.reportState.status, GameReportStatus.idle);
    expect(controller.reviewState.classificationsRevealed, isFalse);
    controller.reveal();
    expect(controller.reviewState.classificationsRevealed, isTrue);
  });

  test(
    'completed report auto-reveals classifications without opening the sheet',
    () async {
      final chessGame = ChessGame.fromPgn(
        'auto-reveal',
        '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
      );
      final reportController = GameAnalysisReportController(
        evaluator: _evaluator,
      );
      final controller = MobileGameReviewController(
        reportController: reportController,
        autoStartDelay: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.configure(
        game: chessGame,
        active: true,
        finished: true,
        whiteRating: 2100,
        blackRating: 2050,
      );
      for (
        var i = 0;
        i < 40 &&
            controller.reviewState.reportState.status != GameReportStatus.completed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(controller.reviewState.reportState.status, GameReportStatus.completed);
      // Icons must light up when the report finishes — no sheet open required.
      expect(controller.reviewState.classificationsRevealed, isTrue);

      final report = controller.reviewState.reportState.report!;
      final boardFp = gameReportFingerprint(chessGame);
      expect(
        shouldShowReportClassificationsOnBoard(
          reviewState: controller.reviewState,
          boardGameFingerprint: boardFp,
        ),
        isTrue,
      );
      final byIndex = gameReportClassificationByMoveIndex(report);
      expect(byIndex, isNotEmpty);
      // Zero-based indexes for notation tokens.
      expect(byIndex.containsKey(0), isTrue);

      // Same map `_MovesDisplay` attaches — without calling reveal() via sheet.
      final attachMap = reportClassificationsForNotationAttach(
        reviewState: controller.reviewState,
        boardGameFingerprint: boardFp,
      );
      expect(attachMap, isNotEmpty);
      expect(attachMap.containsKey(0), isTrue);
      expect(attachMap, equals(byIndex));
    },
  );

  test(
    'notation attach map is non-empty for completed report without reveal()',
    () {
      final chessGame = ChessGame.fromPgn(
        'attach-no-reveal',
        '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
      );
      final boardFp = gameReportFingerprint(chessGame);
      // Simulate a completed report that landed in state without ever calling
      // reveal() (sheet never opened). Gate must still allow notation attach.
      final report = GameAnalysisReport(
        fingerprint: boardFp,
        positions: const [],
        moves: [
          GameReportMove(
            ply: 1,
            san: 'e4',
            uci: 'e2e4',
            isWhite: true,
            classification: GameMoveClassification.bestMove,
            evaluation: const GameReportLine(
              moves: ['e7e5'],
              depth: 12,
              centipawns: 20,
            ),
          ),
          GameReportMove(
            ply: 2,
            san: 'e5',
            uci: 'e7e5',
            isWhite: false,
            classification: GameMoveClassification.blunder,
            evaluation: const GameReportLine(
              moves: ['g1f3'],
              depth: 12,
              centipawns: -90,
            ),
          ),
        ],
        whiteAccuracy: 90,
        blackAccuracy: 40,
        generatedAt: DateTime.utc(2026, 1, 1),
      );
      final reviewState = MobileGameReviewState(
        fingerprint: boardFp,
        // revealedFingerprint deliberately null — sheet never opened.
        isEligible: true,
        reportState: GameReportState(
          status: GameReportStatus.completed,
          progress: 1,
          report: report,
        ),
      );

      expect(reviewState.revealedFingerprint, isNull);
      expect(
        shouldShowReportClassificationsOnBoard(
          reviewState: reviewState,
          boardGameFingerprint: boardFp,
        ),
        isTrue,
      );
      final attachMap = reportClassificationsForNotationAttach(
        reviewState: reviewState,
        boardGameFingerprint: boardFp,
      );
      expect(attachMap, isNotEmpty);
      expect(attachMap[0], GameMoveClassification.bestMove);
      expect(attachMap[1], GameMoveClassification.blunder);
      // Mainline order indices (0, 1) — same keys notation tokens use.
      expect(gameReportClassificationByMoveIndex(report).keys, [0, 1]);
    },
  );

  test(
    'notation tree moveIndex keys align with report attach map indices',
    () {
      final chessGame = ChessGame.fromPgn(
        'index-align',
        '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 2. Nf3 Nc6 1-0',
      );
      final tree = NotationTreeBuilder.build(chessGame);
      final boardFp = gameReportFingerprint(chessGame);
      final report = GameAnalysisReport(
        fingerprint: boardFp,
        positions: const [],
        moves: [
          for (var i = 0; i < chessGame.mainline.length; i++)
            GameReportMove(
              ply: i + 1,
              san: chessGame.mainline[i].san,
              uci: chessGame.mainline[i].uci,
              isWhite: chessGame.mainline[i].turn == ChessColor.white,
              classification:
                  i.isEven
                      ? GameMoveClassification.bestMove
                      : GameMoveClassification.inaccuracy,
              evaluation: const GameReportLine(
                moves: ['a2a3'],
                depth: 8,
                centipawns: 10,
              ),
            ),
        ],
        whiteAccuracy: 80,
        blackAccuracy: 70,
        generatedAt: DateTime.utc(2026, 1, 1),
      );
      final reviewState = MobileGameReviewState(
        fingerprint: boardFp,
        isEligible: true,
        reportState: GameReportState(
          status: GameReportStatus.completed,
          progress: 1,
          report: report,
        ),
      );
      final attachMap = reportClassificationsForNotationAttach(
        reviewState: reviewState,
        boardGameFingerprint: boardFp,
      );
      expect(attachMap.length, chessGame.mainline.length);
      for (var i = 0; i < tree.mainline.length; i++) {
        final node = tree.mainline[i];
        final moveIndex = node.ply - tree.startingPly;
        expect(moveIndex, i, reason: 'token moveIndex must be mainline index');
        expect(attachMap.containsKey(moveIndex), isTrue);
        expect(node.pointer.single, i);
      }
    },
  );

  test('sheet uses a single open height with drag-to-dismiss floor', () {
    expect(GameReviewSheetExtents.height, lessThan(1.0));
    expect(GameReviewSheetExtents.height, greaterThan(0.5));
    expect(
      GameReviewSheetExtents.minHeight,
      lessThan(GameReviewSheetExtents.height),
    );
    expect(GameReviewSheetExtents.minHeight, greaterThan(0.0));
    expect(GameReviewSheetExtents.topRadius, greaterThan(0));
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
    final buttonWidthBoxes = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .where((box) => box.widthFactor == 0.75);
    expect(buttonWidthBoxes, hasLength(2));
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
      autoStartDelay: Duration.zero,
    );
    int? jumpedToPly;
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
        i < 30 &&
            controller.reviewState.reportState.status != GameReportStatus.completed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(controller.reviewState.reportState.status, GameReportStatus.completed);

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
                        onJumpToPly: (ply) => jumpedToPly = ply,
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
    expect(find.text('Game Review'), findsNothing);
    expect(find.text('GM Lovelace'), findsOneWidget);
    expect(find.text('IM Hopper'), findsOneWidget);
    expect(find.byType(PlayerInitialsAvatar), findsNWidgets(2));
    expect(find.text('Accuracy'), findsOneWidget);
    expect(find.text('Game Rating'), findsOneWidget);
    final completedReport = controller.reviewState.reportState.report!;
    expect(
      find.text('${completedReport.whiteEstimatedRating}'),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.text('${completedReport.blackEstimatedRating}'),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Forced'), findsNothing);
    expect(find.text('Best'), findsOneWidget);
    expect(find.text('Great'), findsOneWidget);
    expect(find.text('Missed Win'), findsOneWidget);
    expect(find.text('1-0'), findsNothing);
    expect(find.byType(CircleAvatar), findsNothing);
    expect(
      find.byKey(const ValueKey('game-review-evaluation-graph')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('game-review-evaluation-graph')))
          .height,
      75,
    );
    expect(
      find.byKey(const ValueKey('game-review-graph-info')),
      findsOneWidget,
    );
    // Opens at a single height; DraggableScrollableSheet wires dismiss to the
    // primary scroll controller so handle / top-of-content drag closes it.
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('game-review-full-sheet')),
      findsOneWidget,
    );
    final sheet = tester.widget<Material>(
      find.byKey(const ValueKey('game-review-full-sheet')),
    );
    final shape = sheet.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, isA<BorderRadius>());
    final radius = shape.borderRadius as BorderRadius;
    expect(radius.topLeft.x, GameReviewSheetExtents.topRadius);
    expect(radius.topRight.x, GameReviewSheetExtents.topRadius);

    expect(find.text('OPENING'), findsNothing);
    expect(find.text('MIDDLEGAME'), findsNothing);
    expect(find.text('ENDGAME'), findsNothing);
    expect(find.textContaining('1/3'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('game-review-bestMove-white-score')),
    );
    await tester.pump();
    expect(jumpedToPly, 1);
    expect(find.textContaining('2/3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('game-review-next-move')));
    await tester.pump();
    expect(jumpedToPly, 2);
    expect(find.textContaining('3/3'), findsOneWidget);

    Navigator.of(
      tester.element(find.byKey(const ValueKey('game-review-full-sheet'))),
    ).pop();
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
  final whiteToMove = fen.split(' ')[1] == 'w';
  return EnhancedCloudEval(
    fen: fen,
    knodes: 500,
    depth: depth,
    pvs: [
      Pv(
        moves:
            whiteToMove
                ? (fen.startsWith('rnbqkbnr/pppppppp') ? 'e2e4' : 'g1f3')
                : 'e7e5',
        cp: 10,
      ),
    ],
    requestedMultiPv: multiPv,
  );
}

GamesTourModel _game() => GamesTourModel(
  gameId: 'review-game',
  whitePlayer: PlayerCard(
    name: 'Ada Lovelace',
    federation: '',
    title: 'GM',
    rating: 2100,
    countryCode: '',
    team: null,
  ),
  blackPlayer: PlayerCard(
    name: 'Grace Hopper',
    federation: '',
    title: 'IM',
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
