import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/supabase/game_analysis_quota_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/game_review/game_report_from_pgn.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_sheet.dart';
import 'package:chessever2/screens/chessboard/game_review/server_game_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(GameAnalysisReportController.clearSessionCacheForTest);
  tearDown(GameAnalysisReportController.clearSessionCacheForTest);

  Map<String, dynamic> savedPayload() =>
      jsonDecode(
            File('test/fixtures/server_game_report.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  test(
    'restores saved verdicts and scores without fabricating search lines',
    () {
      final payload = savedPayload();
      final game = ChessGame.fromPgn('saved', payload['pgn'] as String);
      final expected = gameAnalysisReportFromServerJson(payload, game: game);
      final restored = gameAnalysisReportFromPgn(game)!;
      expect(restored.fingerprint, expected.fingerprint);
      expect(
        restored.moves.map((move) => move.classification),
        expected.moves.map((move) => move.classification),
      );
      expect(
        restored.moves.map((move) => move.evaluation.centipawns),
        expected.moves.map((move) => move.evaluation.centipawns),
      );
      expect(
        restored.moves.map((move) => move.evaluation.mate),
        expected.moves.map((move) => move.evaluation.mate),
      );
      expect(
        restored.positions.map((position) => position.fen),
        expected.positions.map((position) => position.fen),
      );
      expect(restored.positions.first.bestLine.centipawns, isNull);
      expect(
        restored.moves.every((move) => move.bestAlternative == null),
        isTrue,
      );
    },
  );

  test('ordinary annotations and partial reports still need analysis', () {
    for (final pgn in [
      '1. e4 e5 *',
      r'1. e4 $1 {[%eval 0.32]} e5 $2 {[%eval 0.22]} *',
      r'1. e4 $247 {[%eval 0.32]} e5 *',
      r'1. e4 $247 {[%eval NaN]} e5 {[%eval 0.22]} *',
      r'1. e4 $247 {[%eval #999999999999999999999]} e5 {[%eval 0.22]} *',
      r'1. e4 $247 {[%eval 0.32,invalid]} e5 {[%eval 0.22]} *',
    ]) {
      expect(
        gameAnalysisReportFromPgn(ChessGame.fromPgn('partial', pgn)),
        isNull,
        reason: pgn,
      );
    }
  });

  test(
    'legacy verdicts, custom starts, negative mate and score depth survive',
    () {
      final game = ChessGame.fromPgn(
        'custom',
        '[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"]\n'
            '[SetUp "1"]\n\n'
            '1... e5 {[%eval -0.25,18] [%chessever_annotation book]} '
            '2. Nf3 {[%eval #-3]} *',
      );
      final restored = gameAnalysisReportFromPgn(game)!;
      expect(restored.positions.first.fen, game.startingFen);
      expect(restored.moves.first.isWhite, isFalse);
      expect(
        restored.moves.first.classification,
        GameMoveClassification.bookMove,
      );
      expect(restored.moves.first.evaluation.centipawns, -25);
      expect(restored.moves.first.evaluation.depth, 18);
      expect(restored.moves.last.evaluation.mate, -3);
    },
  );

  test(
    'full durable reports keep their accuracy and principal variations',
    () async {
      final payload = savedPayload();
      final game = ChessGame.fromPgn('saved', payload['pgn'] as String);
      final full = gameAnalysisReportFromServerJson(payload, game: game);
      final store = GameAnalysisReportStore.memory();
      await store.save(full);
      final reports = GameAnalysisReportController(store: store);
      addTearDown(reports.dispose);
      expect(await reports.loadExistingReport(game), isTrue);
      expect(reports.state.report!.whiteAccuracy, full.whiteAccuracy);
      expect(
        reports.state.report!.moves.first.bestAlternative,
        full.moves.first.bestAlternative,
      );
      expect(
        reports.state.report!.positions.first.bestLine.moves,
        full.positions.first.bestLine.moves,
      );
      await store.flush();
    },
  );

  test(
    'restored reports persist for reopening a clean copy of the same game',
    () async {
      final payload = savedPayload();
      final game = ChessGame.fromPgn('saved', payload['pgn'] as String);
      final store = GameAnalysisReportStore.memory();
      final reports = GameAnalysisReportController(store: store);
      addTearDown(reports.dispose);
      expect(await reports.loadExistingReport(game), isTrue);
      await store.flush();
      GameAnalysisReportController.clearSessionCacheForTest();
      final cold = GameAnalysisReportController(store: store);
      addTearDown(cold.dispose);
      expect(await cold.loadExistingReport(game.withoutAnalysis()), isTrue);
      expect(
        cold.state.report!.whiteAccuracy,
        reports.state.report!.whiteAccuracy,
      );
      expect(cold.state.report!.whiteAccuracy, isNotNull);
      expect(
        cold.state.report!.moves[5].classification,
        GameMoveClassification.blunder,
      );
      await store.flush();
    },
  );

  test(
    'a report restored from a PGN shows the accuracy and game rating again',
    () {
      final payload = savedPayload();
      final game = ChessGame.fromPgn('saved', payload['pgn'] as String);
      final expected = gameAnalysisReportFromServerJson(payload, game: game);
      final restored = gameAnalysisReportFromPgn(game)!;
      // Only the starting position's score is missing from a PGN, so the
      // derived numbers sit within rounding of the engine report's own.
      expect(restored.whiteAccuracy, closeTo(expected.whiteAccuracy!, 0.5));
      expect(restored.blackAccuracy, closeTo(expected.blackAccuracy!, 0.5));
      // The game rating is anchored to the players' known ratings, so it is
      // compared against the engine report's positions under the same anchor.
      for (final known in const [null, 2700]) {
        final fromEngine =
            computeGameReportEstimatedRatings(
              expected.positions,
              whiteRating: known,
              blackRating: known,
            )!;
        final fromPgn =
            gameAnalysisReportFromPgn(
              game,
              whiteRating: known,
              blackRating: known,
            )!;
        expect(fromPgn.whiteEstimatedRating, fromEngine.white);
        expect(fromPgn.blackEstimatedRating, fromEngine.black);
      }
    },
  );

  test(
    'a report an older build saved without accuracy gains it on the next load',
    () async {
      final payload = savedPayload();
      final game = ChessGame.fromPgn('saved', payload['pgn'] as String);
      final current = gameAnalysisReportFromPgn(game)!;
      final store = GameAnalysisReportStore.memory();
      await store.save(
        GameAnalysisReport(
          fingerprint: current.fingerprint,
          positions: current.positions,
          moves: current.moves,
          whiteAccuracy: null,
          blackAccuracy: null,
          generatedAt: current.generatedAt,
        ),
      );
      final reports = GameAnalysisReportController(store: store);
      addTearDown(reports.dispose);
      // The clean copy carries no report of its own: disk is the only source.
      expect(await reports.loadExistingReport(game.withoutAnalysis()), isTrue);
      expect(reports.state.report!.whiteAccuracy, current.whiteAccuracy);
      expect(reports.state.report!.blackAccuracy, current.blackAccuracy);
      expect(
        reports.state.report!.whiteEstimatedRating,
        current.whiteEstimatedRating,
      );
      await store.flush();
      final saved = await store.load(current.fingerprint);
      expect(saved!.whiteAccuracy, current.whiteAccuracy);
    },
  );

  test('a report missing a score keeps its accuracy blank, not invented', () {
    const unscored = GameReportLine(moves: [], depth: 0);
    const scored = GameReportLine(moves: [], depth: 0, centipawns: 20);
    final report = GameAnalysisReport(
      fingerprint: 'partial',
      positions: const [
        GameReportPosition(fen: 'start', lines: [unscored]),
        GameReportPosition(fen: 'one', lines: [scored]),
        GameReportPosition(fen: 'two', lines: [unscored]),
      ],
      moves: const [
        GameReportMove(
          ply: 1,
          san: 'e4',
          uci: 'e2e4',
          isWhite: true,
          classification: null,
          evaluation: scored,
        ),
        GameReportMove(
          ply: 2,
          san: 'e5',
          uci: 'e7e5',
          isWhite: false,
          classification: null,
          evaluation: unscored,
        ),
      ],
      whiteAccuracy: null,
      blackAccuracy: null,
      generatedAt: DateTime.utc(2026),
    );
    expect(identical(recoverGameReportSummary(report), report), isTrue);
  });

  test('explicitly requesting a cleared report can reuse its saved backup', () {
    final payload = savedPayload();
    final game = ChessGame.fromPgn('saved', payload['pgn'] as String);
    expect(gameAnalysisReportFromPgn(game.withoutAnalysis()), isNotNull);
    final edited = game.withoutAnalysis().copyWith(
      mainline: game.mainline.sublist(0, 3),
    );
    expect(gameAnalysisReportFromPgn(edited), isNull);
  });

  testWidgets(
    'leaving a game during restoration does not claim or analyze it',
    (tester) async {
      final payload = savedPayload();
      final previous = ChessGame.fromPgn('previous', payload['pgn'] as String);
      final next = ChessGame.fromPgn(
        'next',
        r'1. d4 $247 {[%eval 0.25]} d5 {[%eval 0.15]} 1-0',
      );
      final store = _DelayedReportStore(gameReportFingerprint(previous));
      final reports = GameAnalysisReportController(store: store);
      var quotaCalls = 0;
      final review = MobileGameReviewController(
        reportController: reports,
        claimQuota: (_) async {
          quotaCalls++;
          return const GameAnalysisClaimResult(
            allowed: false,
            reason: 'denied',
            isPremium: false,
          );
        },
      );
      addTearDown(review.dispose);
      review.configure(
        game: previous,
        active: false,
        finished: true,
        whiteRating: 0,
        blackRating: 0,
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      final pending = review.requestAnalysis(context);
      await store.entered.future;
      review.configure(
        game: next,
        active: false,
        finished: true,
        whiteRating: 0,
        blackRating: 0,
      );
      expect(await reports.loadExistingReport(next), isTrue);
      store.release.complete();
      await pending;
      expect(quotaCalls, 0);
      expect(
        review.reviewState.reportState.report!.fingerprint,
        gameReportFingerprint(next),
      );
      await store.flush();
    },
  );

  testWidgets(
    'opening a saved report on a cold device never generates it again',
    (tester) async {
      final payload =
          jsonDecode(
                File(
                  'test/fixtures/server_game_report.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final game = ChessGame.fromPgn('saved-report', payload['pgn'] as String);
      var quotaCalls = 0;
      var generationCalls = 0;
      final store = GameAnalysisReportStore.memory();
      final reports = GameAnalysisReportController(
        store: store,
        remoteRunner:
            (
              game, {
              whiteRating,
              blackRating,
              required onProgress,
              required isCancelled,
            }) async {
              generationCalls++;
              return gameAnalysisReportFromServerJson(payload, game: game);
            },
      );
      final review = MobileGameReviewController(
        reportController: reports,
        claimQuota: (_) async {
          quotaCalls++;
          return const GameAnalysisClaimResult(
            allowed: true,
            reason: 'allowed',
            isPremium: false,
          );
        },
      );
      addTearDown(review.dispose);
      review.configure(
        game: game,
        active: false,
        finished: true,
        whiteRating: 2400,
        blackRating: 2400,
      );

      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return GameAnalysisButton(
                state: review.reviewState,
                onPressed: null,
              );
            },
          ),
        ),
      );
      await review.requestAnalysis(context);

      expect(generationCalls, 0, reason: 'the PGN already contains the report');
      expect(
        quotaCalls,
        0,
        reason: 'viewing a saved report is not a new analysis',
      );
      expect(review.reviewState.reportState.status, GameReportStatus.completed);
      expect(
        review.reviewState.reportState.report!.fingerprint,
        gameReportFingerprint(game),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GameAnalysisButton(state: review.reviewState, onPressed: null),
        ),
      );
      expect(find.text('Show report'), findsOneWidget);
      expect(find.text('Generate Report'), findsNothing);
      await store.flush();
    },
  );
}

class _DelayedReportStore extends GameAnalysisReportStore {
  _DelayedReportStore(this.fingerprint) : super.memory();
  final String fingerprint;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<GameAnalysisReport?> load(String value) async {
    if (value == fingerprint) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return super.load(value);
  }
}
