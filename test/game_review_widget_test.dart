import 'dart:async';
import 'dart:io' as io;

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/supabase/game_analysis_quota_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_sheet.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_sheet_host.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<GameAnalysisClaimResult> _allowClaim(String _) async =>
    const GameAnalysisClaimResult(
      allowed: true,
      reason: 'premium',
      isPremium: true,
    );

void main() {
  test('review eligibility and reveal state follow the configured game', () {
    final controller = MobileGameReviewController(claimQuota: _allowClaim);
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
    expect(
      controller.reviewState.unavailableMessage,
      contains('when the game ends'),
    );

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

  // Report generation is on-demand for EVERY tier. Premium used to auto-start
  // a couple of seconds after the board went active; nothing may bring a report
  // into being now except the reader asking for one.
  test('no tier starts a report from opening or resuming a board', () async {
    var claims = 0;
    final controller = MobileGameReviewController(
      reportController: GameAnalysisReportController(evaluator: _evaluator),
      claimQuota: (fingerprint) async {
        claims++;
        return const GameAnalysisClaimResult(
          allowed: true,
          reason: 'premium',
          isPremium: true,
        );
      },
    );
    addTearDown(controller.dispose);

    controller.configure(
      game: ChessGame.fromPgn(
        'no-auto',
        '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
      ),
      active: true,
      finished: true,
      whiteRating: 2100,
      blackRating: 2050,
    );
    // Board goes away and comes back — still nothing.
    controller.setActive(false);
    controller.setActive(true);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(controller.reviewState.isEligible, isTrue);
    expect(controller.reviewState.reportState.status, GameReportStatus.idle);
    expect(claims, 0, reason: 'a quota slot must never be spent unasked');

    // Asking is what runs it, and premium may ask for as many games as it likes
    // (the server RPC returns allowed without spending a slot).
    await controller.retry();
    expect(claims, 1);
    expect(
      controller.reviewState.reportState.status,
      GameReportStatus.completed,
    );
  });

  // The check above catches an auto-start that fires promptly; this one catches
  // the timer-behind-a-delay shape the removed version used, without making a
  // unit test sit through the delay.
  test('the controller holds no auto-start timer at all', () {
    final source =
        io.File(
          'lib/screens/chessboard/game_review/game_review_provider.dart',
        ).readAsStringSync();
    expect(source, isNot(contains('autoStart')));
    expect(source, isNot(contains('_scheduleAnalyze')));
    expect(source, isNot(contains('Timer(')));
    expect(source, contains('requestAnalysis('));
    expect(source, contains('stopAnalysis('));
  });

  test(
    'deactivate while running leaves non-running CTA and resume does not auto-start',
    () async {
      final gate = Completer<void>();
      var claims = 0;
      Future<EnhancedCloudEval> blockedEvaluator(
        String fen, {
        required int depth,
        required int multiPv,
        required String ownerId,
        void Function(int reachedDepth, int knodes)? onProgress,
      }) async {
        await gate.future;
        return EnhancedCloudEval(
          fen: fen,
          knodes: 100,
          depth: depth,
          pvs: [Pv(moves: 'e2e4', cp: 0)],
          requestedMultiPv: multiPv,
        );
      }

      final reportController = GameAnalysisReportController(
        evaluator: blockedEvaluator,
      );
      final controller = MobileGameReviewController(
        reportController: reportController,
        claimQuota: (_) async {
          claims++;
          return const GameAnalysisClaimResult(
            allowed: true,
            reason: 'premium',
            isPremium: true,
          );
        },
      );
      addTearDown(controller.dispose);

      controller.configure(
        game: ChessGame.fromPgn(
          'bg-cancel',
          '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
        ),
        active: true,
        finished: true,
        whiteRating: 2100,
        blackRating: 2050,
      );

      // Start without awaiting completion (evaluator is gated).
      unawaited(controller.retry());
      for (
        var i = 0;
        i < 50 && !controller.reviewState.reportState.isRunning;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(controller.reviewState.reportState.status, GameReportStatus.running);
      expect(claims, 1);

      // Lifecycle deactivate (background / swipe-away) cancels promptly.
      controller.setActive(false);
      // Status must leave running without waiting on the blocked evaluator.
      for (
        var i = 0;
        i < 20 && controller.reviewState.reportState.isRunning;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(controller.reviewState.reportState.isRunning, isFalse);
      expect(
        controller.reviewState.reportState.status,
        GameReportStatus.cancelled,
      );
      // Cancelled surfaces as retry CTA, not in-progress %.
      expect(
        controller.reviewState.reportState.status == GameReportStatus.running,
        isFalse,
      );

      // Resume must not auto-start a new report or spend another claim.
      final claimsBeforeResume = claims;
      controller.setActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.reviewState.reportState.isRunning, isFalse);
      expect(claims, claimsBeforeResume);

      gate.complete();
      // Explicit ask after stop can run again.
      await controller.retry();
      expect(claims, claimsBeforeResume + 1);
      expect(
        controller.reviewState.reportState.status,
        GameReportStatus.completed,
      );
    },
  );

  test('second tap / stopAnalysis stops generation while running', () async {
    final gate = Completer<void>();
    Future<EnhancedCloudEval> blockedEvaluator(
      String fen, {
      required int depth,
      required int multiPv,
      required String ownerId,
      void Function(int reachedDepth, int knodes)? onProgress,
    }) async {
      await gate.future;
      return EnhancedCloudEval(
        fen: fen,
        knodes: 100,
        depth: depth,
        pvs: [Pv(moves: 'e2e4', cp: 0)],
        requestedMultiPv: multiPv,
      );
    }

    final reportController = GameAnalysisReportController(
      evaluator: blockedEvaluator,
    );
    final controller = MobileGameReviewController(
      reportController: reportController,
      claimQuota: _allowClaim,
    );
    addTearDown(controller.dispose);

    controller.configure(
      game: ChessGame.fromPgn(
        'second-tap',
        '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
      ),
      active: true,
      finished: true,
      whiteRating: 2100,
      blackRating: 2050,
    );

    unawaited(controller.retry());
    for (
      var i = 0;
      i < 50 && !controller.reviewState.reportState.isRunning;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.reviewState.reportState.isRunning, isTrue);

    // Same user-facing entry the notation button uses when already running.
    await controller.stopAnalysis();
    expect(controller.reviewState.reportState.isRunning, isFalse);
    expect(
      controller.reviewState.reportState.status,
      GameReportStatus.cancelled,
    );

    // retry() while running also stops (sheet / second path).
    final gate2 = Completer<void>();
    final report2 = GameAnalysisReportController(
      evaluator: (
        String fen, {
        required int depth,
        required int multiPv,
        required String ownerId,
        void Function(int reachedDepth, int knodes)? onProgress,
      }) async {
        await gate2.future;
        return EnhancedCloudEval(
          fen: fen,
          knodes: 100,
          depth: depth,
          pvs: [Pv(moves: 'e2e4', cp: 0)],
          requestedMultiPv: multiPv,
        );
      },
    );
    final controller2 = MobileGameReviewController(
      reportController: report2,
      claimQuota: _allowClaim,
    );
    addTearDown(controller2.dispose);
    controller2.configure(
      game: ChessGame.fromPgn(
        'retry-stops',
        '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. d4 d5 1-0',
      ),
      active: true,
      finished: true,
      whiteRating: 2100,
      blackRating: 2050,
    );
    unawaited(controller2.retry());
    for (
      var i = 0;
      i < 50 && !controller2.reviewState.reportState.isRunning;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller2.reviewState.reportState.isRunning, isTrue);
    await controller2.retry();
    expect(controller2.reviewState.reportState.isRunning, isFalse);
    expect(
      controller2.reviewState.reportState.status,
      GameReportStatus.cancelled,
    );

    gate.complete();
    gate2.complete();
  });

  test('openGameReview path stops when report is running (source wiring)', () {
    final boardSource =
        io.File(
          'lib/screens/chessboard/chess_board_screen_new.dart',
        ).readAsStringSync();
    expect(boardSource, contains('stopAnalysis()'));
    expect(
      boardSource,
      contains('reportState.isRunning'),
      reason: 'openGameReview must branch on running to stop without sheet open',
    );
    final reportSource =
        io.File(
          'lib/screens/chessboard/game_review/game_analysis_report.dart',
        ).readAsStringSync();
    // Cancel must set cancelled status before awaiting Stockfish teardown.
    final cancelIdx = reportSource.indexOf('Future<void> cancel() async');
    expect(cancelIdx, greaterThan(0));
    final cancelBody = reportSource.substring(
      cancelIdx,
      cancelIdx + 800,
    );
    final statusBeforeAwait =
        cancelBody.indexOf('GameReportStatus.cancelled') <
        cancelBody.indexOf('cancelEvaluationsForOwner');
    expect(
      statusBeforeAwait,
      isTrue,
      reason: 'UI status must leave running before engine cancel await',
    );
    expect(cancelBody, isNot(contains('will restart when this game is active')));
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
        claimQuota: _allowClaim,
      );
      addTearDown(controller.dispose);

      controller.configure(
        game: chessGame,
        active: true,
        finished: true,
        whiteRating: 2100,
        blackRating: 2050,
      );
      // On-demand for every tier: configuring the board never starts a report.
      expect(controller.reviewState.reportState.status, GameReportStatus.idle);
      await controller.retry();
      for (
        var i = 0;
        i < 40 &&
            controller.reviewState.reportState.status !=
                GameReportStatus.completed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(
        controller.reviewState.reportState.status,
        GameReportStatus.completed,
      );
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

  test('notation tree moveIndex keys align with report attach map indices', () {
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
  });

  test('sheet exposes two snap steps above a dismiss floor', () {
    expect(GameReviewSheetExtents.full, lessThan(1.0));
    expect(GameReviewSheetExtents.full, greaterThan(0.5));
    // Step 1 must leave the board and both player rows on screen.
    expect(
      GameReviewSheetExtents.maxPeek,
      lessThan(GameReviewSheetExtents.full),
    );
    expect(
      GameReviewSheetExtents.minPeek,
      lessThan(GameReviewSheetExtents.maxPeek),
    );
    expect(GameReviewSheetExtents.minPeek, greaterThan(0.0));
    expect(
      GameReviewSheetExtents.peekFallback,
      inInclusiveRange(
        GameReviewSheetExtents.minPeek,
        GameReviewSheetExtents.maxPeek,
      ),
    );
    expect(
      GameReviewSheetExtents.dismissFloor,
      lessThan(GameReviewSheetExtents.minPeek),
    );
    expect(GameReviewSheetExtents.anchorGap, greaterThanOrEqualTo(0));
    expect(GameReviewSheetExtents.topRadius, greaterThan(0));
  });

  test('active ply maps board position to report position', () {
    // Start position → report position 0; mainline move n → position n.
    expect(gameReviewActivePly(const AsyncValue.loading()), -1);
    expect(
      gameReviewActivePly(AsyncValue.data(_boardState(currentMoveIndex: -1))),
      0,
    );
    expect(
      gameReviewActivePly(AsyncValue.data(_boardState(currentMoveIndex: 3))),
      4,
    );
    // Inside an analysis variation the report has no position to point at, so
    // the marker must hold rather than jump somewhere misleading.
    expect(
      gameReviewActivePly(
        AsyncValue.data(_boardState(currentMoveIndex: 3, inVariation: true)),
      ),
      -1,
    );
  });

  testWidgets('Game Analysis button labels follow report status', (
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
                ),
                onPressed: _noop,
              ),
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
                  isEligible: true,
                  reportState: GameReportState(
                    status: GameReportStatus.completed,
                    progress: 1.0,
                  ),
                ),
                onPressed: _noop,
              ),
              GameAnalysisButton(
                state: MobileGameReviewState(
                  isEligible: true,
                  reportState: GameReportState(
                    status: GameReportStatus.failed,
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

    expect(find.text('Generate Report'), findsOneWidget);
    expect(find.text('Game Analysis · 42%'), findsOneWidget);
    expect(find.text('Show report'), findsOneWidget);
    expect(find.text('Retry Game Analysis'), findsOneWidget);
    expect(
      find.text('Game analysis starts when the game ends'),
      findsOneWidget,
    );
    // Idle eligible must not still use the old entry copy.
    expect(find.text('Game Analysis'), findsNothing);
    final buttonWidthBoxes = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .where((box) => box.widthFactor == 0.75);
    expect(buttonWidthBoxes, hasLength(5));
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
      claimQuota: _allowClaim,
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
      // Reports are on-demand for every tier — the sheet has something to show
      // only because the reader asked for it.
      await controller.retry();
      for (
        var i = 0;
        i < 30 &&
            controller.reviewState.reportState.status !=
                GameReportStatus.completed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(
      controller.reviewState.reportState.status,
      GameReportStatus.completed,
    );

    var closed = false;
    var boardTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              // Stands in for the live board underneath the sheet.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => boardTaps++,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: GameReviewSheet(
                  controller: controller,
                  game: game,
                  activePly: 0,
                  onJumpToPly: (ply) => jumpedToPly = ply,
                  onClose: () => closed = true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    expect(find.text('Great move'), findsOneWidget);
    expect(find.text('Top move'), findsOneWidget);
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
    // Two snap steps: opens at the measured peek, drags up to `full`, and the
    // floor below the peek dismisses.
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    final draggable = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(draggable.snap, isTrue);
    expect(draggable.snapSizes, hasLength(1));
    expect(draggable.snapSizes!.single, draggable.initialChildSize);
    expect(draggable.maxChildSize, GameReviewSheetExtents.full);
    expect(draggable.minChildSize, GameReviewSheetExtents.dismissFloor);
    expect(
      draggable.initialChildSize,
      lessThan(GameReviewSheetExtents.full),
      reason: 'step 1 must sit below the fully-open height',
    );

    expect(
      find.byKey(const ValueKey('game-review-full-sheet')),
      findsOneWidget,
    );
    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('game-review-full-sheet')),
    );
    final decoration = surface.decoration as BoxDecoration;
    final radius = decoration.borderRadius! as BorderRadius;
    expect(radius.topLeft.x, GameReviewSheetExtents.topRadius);
    expect(radius.topRight.x, GameReviewSheetExtents.topRadius);
    // No scrim and no modal barrier: a tap above the sheet has to reach the
    // board underneath instead of being swallowed (or dismissing the sheet).
    final sheetTop =
        tester
            .getTopLeft(find.byKey(const ValueKey('game-review-full-sheet')))
            .dy;
    await tester.tapAt(Offset(200, sheetTop - 40));
    await tester.pump();
    expect(boardTaps, 1);
    expect(closed, isFalse);

    expect(find.text('OPENING'), findsNothing);
    expect(find.text('MIDDLEGAME'), findsNothing);
    expect(find.text('ENDGAME'), findsNothing);
    // Tooltip reads as a move, not telemetry: no half-move counter, no win%.
    expect(find.textContaining('Start'), findsOneWidget);
    expect(find.textContaining('1/3'), findsNothing);
    expect(find.textContaining('% White'), findsNothing);
    expect(find.byKey(const ValueKey('game-review-next-move')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('game-review-previous-move')),
      findsOneWidget,
    );

    // Stepping forward drives the board, not a private cursor in the sheet.
    await tester.tap(find.byKey(const ValueKey('game-review-next-move')));
    await tester.pump();
    expect(jumpedToPly, 1);

    expect(closed, isFalse);
    await tester.tap(find.byKey(const ValueKey('game-review-close')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('graph marker follows the board, not a cursor inside the sheet', (
    tester,
  ) async {
    final chessGame = ChessGame.fromPgn(
      'sheet-sync',
      '[White "Ada"]\n[Black "Grace"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
    );
    final controller = MobileGameReviewController(
      reportController: GameAnalysisReportController(evaluator: _evaluator),
      claimQuota: _allowClaim,
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
      // Reports are on-demand for every tier — the sheet has something to show
      // only because the reader asked for it.
      await controller.retry();
      for (
        var i = 0;
        i < 30 &&
            controller.reviewState.reportState.status !=
                GameReportStatus.completed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });

    Widget sheetAt(int ply) => MaterialApp(
      home: Scaffold(
        body: GameReviewSheet(
          controller: controller,
          game: game,
          activePly: ply,
          onJumpToPly: (_) {},
          onClose: () {},
        ),
      ),
    );

    await tester.pumpWidget(sheetAt(0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Start'), findsOneWidget);

    // Board moved on its own (arrows, notation, a piece drag) — the marker
    // must follow without any tap inside the sheet.
    await tester.pumpWidget(sheetAt(2));
    await tester.pump();
    expect(find.textContaining('1... e5'), findsOneWidget);

    // Board wandered into an analysis variation the report cannot describe:
    // hold the last mainline position instead of snapping to the start.
    await tester.pumpWidget(sheetAt(-1));
    await tester.pump();
    expect(find.textContaining('1... e5'), findsOneWidget);
  });

  testWidgets('step 1 stops at the measured board anchor', (tester) async {
    final controller = MobileGameReviewController(claimQuota: _allowClaim);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 500,
              child: GameReviewSheet(
                controller: controller,
                game: _game(),
                activePly: 0,
                peekPixels: 200,
                onJumpToPly: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final draggable = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(draggable.initialChildSize, closeTo(200 / 500, 0.001));

    // The whole point of the measured anchor: the sheet's top edge lands
    // exactly the requested distance up from the bottom of its host, so it
    // finishes right under the board's player row on any device.
    final hostBottom =
        tester.getBottomLeft(find.byType(DraggableScrollableSheet)).dy;
    final sheetTop =
        tester
            .getTopLeft(find.byKey(const ValueKey('game-review-full-sheet')))
            .dy;
    expect(hostBottom - sheetTop, closeTo(200, 0.5));
  });

  testWidgets('board anchor publishes the height that clears the player row', (
    tester,
  ) async {
    final anchor = ValueNotifier<double?>(null);
    addTearDown(anchor.dispose);
    final target = ValueNotifier<ChessBoardProviderParams?>(null);
    addTearDown(target.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameReviewSheetScope(
          target: target,
          anchorPixels: anchor,
          child: const Scaffold(
            body: Column(
              children: [
                SizedBox(height: 120),
                GameReviewBoardAnchor(
                  enabled: true,
                  child: SizedBox(height: 40, width: 200),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Default test window is 600 tall; the row's bottom edge sits at 160.
    expect(
      anchor.value,
      closeTo(600 - 160 - GameReviewSheetExtents.anchorGap, 0.5),
    );
  });

  testWidgets('off-screen pages do not publish an anchor', (tester) async {
    final anchor = ValueNotifier<double?>(null);
    addTearDown(anchor.dispose);
    final target = ValueNotifier<ChessBoardProviderParams?>(null);
    addTearDown(target.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameReviewSheetScope(
          target: target,
          anchorPixels: anchor,
          child: const Scaffold(
            body: GameReviewBoardAnchor(
              enabled: false,
              child: SizedBox(height: 40, width: 200),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(anchor.value, isNull);
  });
}

ChessBoardStateNew _boardState({
  required int currentMoveIndex,
  bool inVariation = false,
}) {
  return ChessBoardStateNew(
    game: _game(),
    isAnalysisMode: true,
    analysisState: AnalysisBoardState(
      currentMoveIndex: currentMoveIndex,
      branchPointMoveIndex: inVariation ? 0 : null,
      analysisMoves:
          inVariation
              ? const <Move>[NormalMove(from: Square.e2, to: Square.e4)]
              : const <Move>[],
    ),
  );
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
  final top =
      whiteToMove
          ? (fen.startsWith('rnbqkbnr/pppppppp') ? 'e2e4' : 'g1f3')
          : 'e7e5';
  final second = whiteToMove ? 'd2d4' : 'd7d5';
  final third = whiteToMove ? 'c2c4' : 'c7c5';
  return EnhancedCloudEval(
    fen: fen,
    knodes: 500,
    depth: depth,
    pvs: [
      Pv(moves: top, cp: 180),
      if (multiPv > 1) Pv(moves: second, cp: 20),
      if (multiPv > 2) Pv(moves: third, cp: -40),
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
