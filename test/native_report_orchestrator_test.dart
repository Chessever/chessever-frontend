import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/chessboard/game_review/game_report_from_pgn.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';

import 'native_report_consistency_test.dart' as fixture;

void main() {
  test(
    'phone controller preserves staged primary selection and reconciles final report',
    () async {
      final game = fixture.rc7Game();
      final fens = gameReportFens(game);
      final calls = <({String fen, int depth, int multiPv})>[];
      final confirmations = <GameReportConfirmationRequest>[];
      final controller = GameAnalysisReportController(
        evaluator:
            (
              fen, {
              required depth,
              required multiPv,
              required ownerId,
              onProgress,
            }) async {
              calls.add((fen: fen, depth: depth, multiPv: multiPv));
              final p = fixture.shallow(game)[fens.indexOf(fen)];
              return EnhancedCloudEval(
                fen: fen,
                knodes: 20,
                depth: depth,
                pvs: [
                  for (final l in p.lines)
                    Pv(moves: l.moves.join(' '), cp: l.centipawns ?? 0),
                ],
                requestedMultiPv: multiPv,
              );
            },
        confirmationEvaluator: (r) async {
          confirmations.add(r);
          if (r.fen == fens[0]) {
            return fixture.sample(r.fen, [
              fixture.line('d2e3', 31),
              fixture.line('b3b4', 2),
              fixture.line('f3g1', 0),
            ]);
          }
          if (r.fen == fens[1]) {
            return fixture.sample(r.fen, [
              fixture.line('h5h3 g2h1 h3f1 f3g1 f6e4', -729),
              fixture.line('f6e4', 0),
              fixture.line('g5g4', 27),
            ]);
          }
          return fixture.sample(r.fen, [
            fixture.line('g2h1 h3f1 f3g1 f6e4', -743),
          ]);
        },
      );
      addTearDown(controller.dispose);
      await controller.analyze(game);
      expect(controller.state.status, GameReportStatus.completed);
      final report = controller.state.report!;
      expect(report.moves[0].classification, GameMoveClassification.blunder);
      expect(report.moves[0].bestAlternative, 'd2e3');
      expect(report.moves[1].classification, GameMoveClassification.brilliant);
      expect(calls.take(4).every((c) => c.depth == 12 && c.multiPv == 1), true);
      expect(
        calls.any((c) => c.fen == fens[0] && c.depth == 12 && c.multiPv == 3),
        true,
      );
      expect(confirmations.length, lessThanOrEqualTo(6));
      expect(
        confirmations.every(
          (r) =>
              r.maxNodes == 6000000 && r.maxTime <= const Duration(seconds: 12),
        ),
        true,
      );
      expect(
        GameAnalysisReportController.primarySearchBudget,
        const Duration(milliseconds: 500),
      );
      expect(
        GameAnalysisReportController.refinementSearchBudget,
        const Duration(milliseconds: 500),
      );
      expect(
        GameAnalysisReportController.brilliantSearchBudget,
        const Duration(milliseconds: 900),
      );
      expect(kDecisiveLossNoErrorCeilingPp, 23);
    },
  );

  for (final cancel in [false, true]) {
    test(
      'phone confirmation failure/cancel cannot publish stale evidence, cancel=$cancel',
      () async {
        final game = fixture.rc7Game();
        final fens = gameReportFens(game);
        final started = Completer<void>();
        final pending = Completer<GameReportPosition>();
        final controller = GameAnalysisReportController(
          evaluator:
              (
                fen, {
                required depth,
                required multiPv,
                required ownerId,
                onProgress,
              }) async {
                final p = fixture.shallow(game)[fens.indexOf(fen)];
                return EnhancedCloudEval(
                  fen: fen,
                  depth: depth,
                  knodes: 1,
                  pvs: [
                    for (final l in p.lines)
                      Pv(moves: l.moves.join(' '), cp: l.centipawns ?? 0),
                  ],
                );
              },
          confirmationEvaluator: (r) {
            if (!started.isCompleted) started.complete();
            if (cancel) return pending.future;
            throw StateError('bounded search unavailable');
          },
        );
        addTearDown(controller.dispose);
        final run = controller.analyze(game);
        await started.future;
        if (cancel) {
          await controller.cancel();
          pending.complete(fixture.sample(fens[0], [fixture.line('d2e3', 31)]));
        }
        await run.timeout(const Duration(seconds: 2));
        expect(
          controller.state.status,
          cancel ? GameReportStatus.cancelled : GameReportStatus.completed,
        );
        if (cancel) {
          expect(controller.state.report, isNull);
        } else {
          expect(
            controller.state.report!.positions.first.uncertainty,
            isNotNull,
          );
          expect(controller.state.report!.moves.first.classification, isNull);
          expect(controller.state.message, contains('unresolved'));
        }
      },
    );
  }

  test(
    'phone adapter uses actual completed iteration, not requested/latest depth',
    () async {
      final game = ChessGame.fromPgn('iteration', '1. e4 *');
      final controller = GameAnalysisReportController(
        evaluator:
            (
              fen, {
              required depth,
              required multiPv,
              required ownerId,
              onProgress,
            }) async => EnhancedCloudEval(
              fen: fen,
              depth: 20,
              knodes: 1,
              pvs: [Pv(moves: 'a1a8', cp: 900)],
              completedDepth: 17,
              completedPvs: [
                Pv(moves: fen == game.startingFen ? 'e2e4' : 'e7e5', cp: 0),
              ],
              nativeSearchId: 'synthetic-$fen',
            ),
      );
      addTearDown(controller.dispose);
      await controller.analyze(game);
      expect(controller.state.status, GameReportStatus.completed);
      expect(
        controller.state.report!.positions.every(
          (p) => p.bestLine.depth == 17 && p.bestLine.centipawns == 0,
        ),
        true,
      );
      expect(
        controller.state.report!.positions.first.search!.searchId,
        'synthetic-${game.startingFen}',
      );
    },
  );

  final binary = Platform.environment['NATIVE_REPORT_STOCKFISH'];
  test(
    'real SF18 bounded two-root replay repairs actual captured Rc7',
    () async {
      final game = fixture.rc7Game();
      final traces = <Map<String, dynamic>>[];
      final result = await confirmGameReportConsistency(
        game: game,
        positions: fixture.shallow(game),
        isCancelled: () => false,
        budget: const GameReportConfirmationBudget(maxConflicts: 2),
        evaluate: (r) => freshSearch(binary!, r, traces),
      );
      final report = buildGameAnalysisReport(
        game: game,
        fingerprint: gameReportFingerprint(game),
        positions: result,
      );
      final receipt = <String, dynamic>{
        'traces': traces,
        'classification': report.moves.first.classification?.name,
        'criticalReplyClassification': report.moves[1].classification?.name,
        'criticalReason': nativeCriticalPunishmentReason(
          index: 1,
          game: game,
          positions: result,
          previous: report.moves.first.classification,
        ),
        'alternative': report.moves.first.bestAlternative,
        'whiteAccuracy': report.whiteAccuracy,
        'uncertainty': result.first.uncertainty,
      };
      final output = Platform.environment['NATIVE_REPORT_STOCKFISH_RECEIPT'];
      if (output != null) {
        File(output).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(receipt),
        );
      }
      expect(report.moves.first.classification, GameMoveClassification.blunder);
      expect(report.moves[1].classification, GameMoveClassification.brilliant);
      expect(report.moves.first.bestAlternative, 'd2e3');
      expect(result.first.uncertainty, isNull);
      final exported = exportGamePgnWithReport(game, report);
      final restoredGame = ChessGame.fromPgn('roundtrip', exported);
      final restored = gameAnalysisReportFromPgn(restoredGame)!;
      expect(
        restoredGame.mainline.map((m) => m.uci),
        game.mainline.map((m) => m.uci),
      );
      expect(
        restored.moves.first.classification,
        GameMoveClassification.blunder,
      );
      expect(
        restored.moves[1].classification,
        GameMoveClassification.brilliant,
      );
      expect(restored.count(GameMoveClassification.brilliant, white: false), 1);
      expect(
        restored.moves.first.evaluation.centipawns,
        report.moves.first.evaluation.centipawns,
      );

      expect(
        traces.every((t) => (t['engine'] as String).contains('Stockfish 18')),
        true,
      );
    },
    skip: binary == null
        ? 'Set NATIVE_REPORT_STOCKFISH to an actual SF18 executable'
        : false,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

Future<GameReportPosition> freshSearch(
  String binary,
  GameReportConfirmationRequest request,
  List<Map<String, dynamic>> traces,
) async {
  final elapsed = Stopwatch()..start();
  final process = await Process.start(binary, const []);
  final lines = StreamIterator(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  final raw = <String>[];
  var engine = '';
  final batch = StockfishReportIteration(request.multiPv);
  final sign = request.fen.split(' ')[1] == 'w' ? 1 : -1;
  Future<void> until(String token) async {
    while (await lines.moveNext()) {
      final s = lines.current;
      raw.add(s);
      if (s.startsWith('id name ')) {
        engine = s.substring(8);
      }
      if (s.startsWith('info depth ')) batch.add(s);
      if (s.startsWith(token)) return;
    }
    throw StateError('Stockfish closed before $token');
  }

  try {
    process.stdin.writeln('uci');
    await until('uciok').timeout(const Duration(seconds: 3));
    process.stdin.writeln('setoption name Threads value 1');
    process.stdin.writeln('setoption name Hash value 16');
    process.stdin.writeln('setoption name MultiPV value ${request.multiPv}');
    process.stdin.writeln('ucinewgame');
    process.stdin.writeln('isready');
    await until('readyok').timeout(const Duration(seconds: 3));
    process.stdin.writeln('position fen ${request.fen}');
    final command = stockfishGoCommand(
      depth: request.depth,
      maxDepth: request.depth,
      maxNodes: request.maxNodes,
      searchDuration: request.maxTime,
    );
    process.stdin.writeln(command);
    await until(
      'bestmove',
    ).timeout(request.maxTime + const Duration(seconds: 1));
    if (batch.depth == 0) throw StateError('No complete effective-depth batch');
    final reached = batch.depth;
    final selected = [
      for (final pv in batch.pvs)
        GameReportLine(
          moves: pv.moves.split(' '),
          depth: reached,
          centipawns: pv.isMate ? null : pv.cp * sign,
          mate: pv.mate == null ? null : pv.mate! * sign,
        ),
    ];
    traces.add({
      'fen': request.fen,
      'engine': engine,
      'command': command,
      'depth': reached,
      'elapsedMs': elapsed.elapsedMilliseconds,
      'lines': [
        for (final l in selected)
          {
            'moves': l.moves,
            'centipawns': l.centipawns,
            'mate': l.mate,
            'depth': l.depth,
          },
      ],
      'raw': raw,
    });
    return GameReportPosition(
      fen: request.fen,
      lines: selected,
      search: GameReportSearchEvidence(
        engineId: engine,
        searchId: 'real-${traces.length}',
        complete: true,
      ),
    );
  } finally {
    process.stdin.writeln('quit');
    await process.stdin.flush();
    await lines.cancel();
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 2));
  }
}
