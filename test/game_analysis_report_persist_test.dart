import 'dart:async';

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    GameAnalysisReportController.clearSessionCacheForTest();
  });

  tearDown(() {
    GameAnalysisReportController.clearSessionCacheForTest();
  });

  group('gameAnalysisReport JSON round-trip', () {
    test('encode then decode preserves fingerprint, moves, classifications', () {
      final report = _sampleReport();
      final json = gameAnalysisReportToJson(report);
      final restored = gameAnalysisReportFromJson(json);
      expect(restored, isNotNull);
      expect(restored!.fingerprint, report.fingerprint);
      expect(restored.whiteAccuracy, report.whiteAccuracy);
      expect(restored.blackAccuracy, report.blackAccuracy);
      expect(restored.whiteEstimatedRating, report.whiteEstimatedRating);
      expect(restored.moves.length, report.moves.length);
      expect(restored.positions.length, report.positions.length);
      expect(
        restored.moves.map((m) => m.classification).toList(),
        report.moves.map((m) => m.classification).toList(),
      );
      expect(restored.moves.first.san, 'e4');
      expect(restored.moves.first.evaluation.centipawns, 20);
      expect(restored.moves[1].classification, GameMoveClassification.blunder);
    });
  });

  group('GameAnalysisReportStore (sqlite-shaped memory backend)', () {
    test('save then load returns matching report for fingerprint', () async {
      final store = GameAnalysisReportStore.memory();
      final report = _sampleReport();
      await store.save(report);
      await store.flush();

      final loaded = await store.load(report.fingerprint);
      expect(loaded, isNotNull);
      expect(loaded!.fingerprint, report.fingerprint);
      expect(loaded.moves.length, report.moves.length);
      expect(
        loaded.moves.map((m) => m.classification?.name).toList(),
        report.moves.map((m) => m.classification?.name).toList(),
      );
    });

    test('load misses for unknown fingerprint', () async {
      final store = GameAnalysisReportStore.memory();
      expect(await store.load('no-such-fingerprint'), isNull);
    });

    test('cache key is stable and prefixed for AppDatabase cache_store', () {
      final fp = _sampleReport().fingerprint;
      final key = GameAnalysisReportStore.cacheKeyForFingerprint(fp);
      expect(key.startsWith(GameAnalysisReportStore.keyPrefix), isTrue);
      expect(
        GameAnalysisReportStore.cacheKeyForFingerprint(fp),
        key,
        reason: 'same fingerprint must map to same SQLite key',
      );
    });
  });

  group('load-before-analyze (shipped controller path)', () {
    test(
      'analyze adopts durable report and does not call the evaluator',
      () async {
        final store = GameAnalysisReportStore.memory();
        final report = _sampleReport();
        await store.save(report);
        await store.flush();
        GameAnalysisReportController.clearSessionCacheForTest();

        var evaluatorCalls = 0;
        Future<EnhancedCloudEval> evaluator(
          String fen, {
          required int depth,
          required int multiPv,
          required String ownerId,
          void Function(int reachedDepth, int knodes)? onProgress,
        }) async {
          evaluatorCalls++;
          fail('evaluator must not run when a durable report exists');
        }

        final controller = GameAnalysisReportController(
          evaluator: evaluator,
          store: store,
        );
        addTearDown(controller.dispose);

        final chessGame = ChessGame.fromPgn(
          'persist-hit',
          '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
        );
        expect(gameReportFingerprint(chessGame), report.fingerprint);

        await controller.analyze(chessGame);

        expect(controller.state.status, GameReportStatus.completed);
        expect(controller.state.report?.fingerprint, report.fingerprint);
        expect(evaluatorCalls, 0);
        final byIndex = gameReportClassificationByMoveIndex(
          controller.state.report!,
        );
        expect(byIndex, isNotEmpty);
        expect(byIndex.containsKey(0), isTrue);
      },
    );

    test(
      'after analyze with store, memory clear + loadPersistedReport restores',
      () async {
        final store = GameAnalysisReportStore.memory();
        var evaluatorCalls = 0;
        Future<EnhancedCloudEval> evaluator(
          String fen, {
          required int depth,
          required int multiPv,
          required String ownerId,
          void Function(int reachedDepth, int knodes)? onProgress,
        }) async {
          evaluatorCalls++;
          onProgress?.call(depth, 100);
          final whiteToMove = fen.split(' ')[1] == 'w';
          return EnhancedCloudEval(
            fen: fen,
            knodes: 100,
            depth: depth,
            pvs: [
              Pv(
                moves:
                    whiteToMove
                        ? (fen.startsWith('rnbqkbnr/pppppppp')
                            ? 'e2e4'
                            : 'g1f3')
                        : 'e7e5',
                cp: 10,
              ),
            ],
            requestedMultiPv: multiPv,
          );
        }

        final controller = GameAnalysisReportController(
          evaluator: evaluator,
          store: store,
        );
        addTearDown(controller.dispose);
        final chessGame = ChessGame.fromPgn(
          'persist-write',
          '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
        );
        await controller.analyze(chessGame);
        expect(controller.state.status, GameReportStatus.completed);
        expect(evaluatorCalls, greaterThan(0));
        final fingerprint = gameReportFingerprint(chessGame);
        expect(controller.state.report?.fingerprint, fingerprint);
        await store.flush();

        GameAnalysisReportController.clearSessionCacheForTest();
        final cold = GameAnalysisReportController(
          evaluator: evaluator,
          store: store,
        );
        addTearDown(cold.dispose);
        final adopted = await cold.loadPersistedReport(fingerprint);
        expect(adopted, isTrue);
        expect(cold.state.status, GameReportStatus.completed);
        expect(cold.state.report?.fingerprint, fingerprint);

        final callsBefore = evaluatorCalls;
        await cold.analyze(chessGame);
        expect(evaluatorCalls, callsBefore);
        expect(cold.state.report?.fingerprint, fingerprint);
        await store.flush();
      },
    );

    test(
      'stale loadPersistedReport for A does not clobber completed B after invalidate',
      () async {
        final reportA = _sampleReport(
          gameId: 'stale-a',
          pgn: '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
        );
        final reportB = _sampleReport(
          gameId: 'stale-b',
          pgn: '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. d4 d5 1-0',
        );
        expect(reportA.fingerprint, isNot(reportB.fingerprint));

        final store = _LatchingReportStore();
        await store.save(reportA);
        await store.save(reportB);
        await store.flush();
        GameAnalysisReportController.clearSessionCacheForTest();

        final controller = GameAnalysisReportController(
          evaluator: _unusedEvaluator,
          store: store,
        );
        addTearDown(controller.dispose);

        store.delayFingerprint = reportA.fingerprint;
        final staleLoad = controller.loadPersistedReport(reportA.fingerprint);
        await store.loadEntered.future;

        controller.invalidate();
        store.delayFingerprint = null;
        final adoptedB = await controller.loadPersistedReport(
          reportB.fingerprint,
        );
        expect(adoptedB, isTrue);
        expect(controller.state.report?.fingerprint, reportB.fingerprint);

        store.releaseLoad.complete();
        final adoptedA = await staleLoad;
        expect(adoptedA, isFalse);
        expect(
          controller.state.report?.fingerprint,
          reportB.fingerprint,
          reason: 'stale A must not replace completed B',
        );
        expect(controller.state.status, GameReportStatus.completed);
      },
    );
  });
}

/// Blocks [load] for one fingerprint so tests can interleave invalidate/adopt.
class _LatchingReportStore extends GameAnalysisReportStore {
  _LatchingReportStore() : super.memory();

  String? delayFingerprint;
  final Completer<void> loadEntered = Completer<void>();
  final Completer<void> releaseLoad = Completer<void>();

  @override
  Future<GameAnalysisReport?> load(String fingerprint) async {
    if (fingerprint == delayFingerprint) {
      if (!loadEntered.isCompleted) loadEntered.complete();
      await releaseLoad.future;
    }
    return super.load(fingerprint);
  }
}

Future<EnhancedCloudEval> _unusedEvaluator(
  String fen, {
  required int depth,
  required int multiPv,
  required String ownerId,
  void Function(int reachedDepth, int knodes)? onProgress,
}) async {
  fail('evaluator must not run in stale-load regression');
}

GameAnalysisReport _sampleReport({
  String gameId = 'sample',
  String pgn = '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
}) {
  final chessGame = ChessGame.fromPgn(gameId, pgn);
  final fingerprint = gameReportFingerprint(chessGame);
  final line = const GameReportLine(
    moves: ['e7e5'],
    depth: 12,
    centipawns: 20,
  );
  return GameAnalysisReport(
    fingerprint: fingerprint,
    positions: [
      GameReportPosition(fen: chessGame.startingFen, lines: [line]),
      GameReportPosition(fen: chessGame.mainline[0].fen, lines: [line]),
      GameReportPosition(fen: chessGame.mainline[1].fen, lines: [line]),
    ],
    moves: [
      GameReportMove(
        ply: 1,
        san: chessGame.mainline[0].san,
        uci: chessGame.mainline[0].uci,
        isWhite: true,
        classification: GameMoveClassification.bestMove,
        evaluation: line,
      ),
      GameReportMove(
        ply: 2,
        san: chessGame.mainline[1].san,
        uci: chessGame.mainline[1].uci,
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
    whiteEstimatedRating: 2100,
    blackEstimatedRating: 1800,
    generatedAt: DateTime.utc(2026, 7, 23),
  );
}
