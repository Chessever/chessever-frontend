import 'dart:math' as math;

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('game report snapshots', () {
    final game = ChessGame.fromPgn(
      'report-test',
      '[White "Ada"]\n[Black "Grace"]\n\n1. e4 e5 2. Nf3 *',
    );

    test('fingerprint and FEN list follow the mainline', () {
      expect(gameReportFingerprint(game), contains('e2e4 e7e5 g1f3'));
      expect(gameReportFens(game), hasLength(game.mainline.length + 1));
      expect(gameReportFens(game).first, game.startingFen);
      expect(gameReportFens(game).last, game.mainline.last.fen);
    });

    test('fingerprint changes with the mainline', () {
      final shorter = game.copyWith(mainline: game.mainline.take(2).toList());
      expect(
        gameReportFingerprint(shorter),
        isNot(gameReportFingerprint(game)),
      );
    });
  });

  group('score calculations', () {
    test('mate and centipawn values convert to white win percentage', () {
      expect(gameReportWinPercentage(_line(mate: 2)), 100);
      expect(gameReportWinPercentage(_line(mate: -2)), 0);
      expect(gameReportWinPercentage(_line(cp: 0)), closeTo(50, 0.001));
      expect(
        gameReportWinPercentage(_line(cp: 300)),
        greaterThan(gameReportWinPercentage(_line(cp: 100))),
      );
    });

    test('accuracy stays finite and penalizes a large loss', () {
      final steady = computeGameReportAccuracy([50, 50, 50, 50, 50]);
      final blunder = computeGameReportAccuracy([50, 10, 10, 10, 10]);
      expect(steady.white, closeTo(100, 0.1));
      expect(blunder.white, lessThan(steady.white));
      expect(blunder.black, inInclusiveRange(0, 100));
    });

    test('estimated ratings require moves by both players', () {
      expect(
        computeGameReportEstimatedRatings([_position(0), _position(10)]),
        isNull,
      );
      final ratings = computeGameReportEstimatedRatings(
        [_position(0), _position(-20), _position(15)],
        whiteRating: 1800,
        blackRating: 1750,
      );
      expect(ratings, isNotNull);
      expect(ratings!.white, inInclusiveRange(100, 3500));
      expect(ratings.black, inInclusiveRange(100, 3500));
    });

    test('terminal checkmate and draw positions skip Stockfish', () {
      final mate = terminalGameReportPosition('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      final draw = terminalGameReportPosition('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(mate?.bestLine.mate, 1);
      expect(draw?.bestLine.centipawns, 0);
    });
  });

  group('report progress', () {
    Future<EnhancedCloudEval> evaluator(
      String fen, {
      required int depth,
      required int multiPv,
      required String ownerId,
      void Function(int reachedDepth, int knodes)? onProgress,
    }) async {
      var knodes = 0;
      for (var d = 1; d <= depth; d++) {
        for (var tick = 0; tick < 3; tick++) {
          knodes += 20 * d;
          onProgress?.call(d, knodes);
        }
      }
      return EnhancedCloudEval(
        fen: fen,
        knodes: knodes,
        depth: depth,
        pvs: [Pv(moves: 'a2a3', cp: 20)],
        requestedMultiPv: multiPv,
      );
    }

    test('progress advances within positions and never regresses', () async {
      final game = ChessGame.fromPgn('smooth', '1. e4 e5 2. Nf3 Nc6 *');
      final controller = GameAnalysisReportController(evaluator: evaluator);
      addTearDown(controller.dispose);
      final progresses = <double>[];
      final messages = <String>[];
      controller.addListener(() {
        if (controller.state.isRunning) {
          progresses.add(controller.state.progress);
          final message = controller.state.message;
          if (message != null) messages.add(message);
        }
      });

      await controller.analyze(game);

      expect(controller.state.status, GameReportStatus.completed);
      expect(controller.state.progress, 1);
      for (var i = 1; i < progresses.length; i++) {
        expect(progresses[i], greaterThanOrEqualTo(progresses[i - 1]));
      }
      expect(progresses.length, greaterThan(gameReportFens(game).length));
      expect(messages, contains('Analyzing move 1 of 2'));
      expect(messages, contains('Analyzing move 2 of 2'));
      expect(messages.where((message) => message.contains('of 4')), isEmpty);
    });

    test('runs a primary pass before selective MultiPV refinement', () async {
      expect(
        GameAnalysisReportController.primarySearchBudget,
        const Duration(milliseconds: 500),
      );
      expect(
        GameAnalysisReportController.refinementSearchBudget,
        const Duration(milliseconds: 500),
      );
      final game = ChessGame.fromPgn('staged', '1. e4 e5 2. Nf3 *');
      final requestedWidths = <int>[];
      final requestedDepths = <int>[];

      Future<EnhancedCloudEval> recordingEvaluator(
        String fen, {
        required int depth,
        required int multiPv,
        required String ownerId,
        void Function(int reachedDepth, int knodes)? onProgress,
      }) async {
        requestedWidths.add(multiPv);
        requestedDepths.add(depth);
        return EnhancedCloudEval(
          fen: fen,
          knodes: 100,
          depth: depth,
          pvs: [
            Pv(moves: 'a2a3', cp: 0),
            if (multiPv > 1) Pv(moves: 'h2h3', cp: -5),
          ],
          requestedMultiPv: multiPv,
        );
      }

      final controller = GameAnalysisReportController(
        evaluator: recordingEvaluator,
      );
      addTearDown(controller.dispose);
      await controller.analyze(game);

      final primaryCount = gameReportFens(game).length;
      expect(requestedWidths.take(primaryCount), everyElement(1));
      expect(requestedWidths.skip(primaryCount), everyElement(3));
      expect(requestedDepths, everyElement(12));
      expect(controller.state.status, GameReportStatus.completed);
    });

    test(
      'a preempted position is retried without exposing a partial report',
      () async {
        var calls = 0;
        Future<EnhancedCloudEval> preemptOnce(
          String fen, {
          required int depth,
          required int multiPv,
          required String ownerId,
          void Function(int reachedDepth, int knodes)? onProgress,
        }) async {
          calls++;
          if (calls == 1) {
            return EnhancedCloudEval(
              fen: fen,
              knodes: 0,
              depth: 0,
              pvs: const [],
              isCancelled: true,
              requestedMultiPv: multiPv,
            );
          }
          return EnhancedCloudEval(
            fen: fen,
            knodes: 100,
            depth: depth,
            pvs: [Pv(moves: 'a2a3', cp: 0)],
            requestedMultiPv: multiPv,
          );
        }

        final controller = GameAnalysisReportController(evaluator: preemptOnce);
        addTearDown(controller.dispose);
        await controller.analyze(ChessGame.fromPgn('retry', '1. e4 *'));

        expect(calls, greaterThan(1));
        expect(controller.state.status, GameReportStatus.completed);
        expect(controller.state.report, isNotNull);
      },
    );

    test('empty first-use results retry while the engine warms up', () async {
      var calls = 0;
      Future<EnhancedCloudEval> warmingEvaluator(
        String fen, {
        required int depth,
        required int multiPv,
        required String ownerId,
        void Function(int reachedDepth, int knodes)? onProgress,
      }) async {
        calls++;
        return EnhancedCloudEval(
          fen: fen,
          knodes: calls < 4 ? 0 : 100,
          depth: calls < 4 ? 0 : depth,
          pvs: [Pv(moves: calls < 4 ? '' : 'e2e4', cp: 0)],
          requestedMultiPv: multiPv,
        );
      }

      final controller = GameAnalysisReportController(
        evaluator: warmingEvaluator,
      );
      addTearDown(controller.dispose);
      final messages = <String?>[];
      controller.addListener(() => messages.add(controller.state.message));

      await controller.analyze(ChessGame.fromPgn('warm-up', '1. e4 *'));

      expect(calls, greaterThanOrEqualTo(4));
      expect(messages, contains('Stockfish is warming up…'));
      expect(controller.state.status, GameReportStatus.completed);
      expect(controller.state.report, isNotNull);
    });
  });

  group('move classification', () {
    final game = ChessGame.fromPgn('classify', '1. e4 *');

    test('engine top among near-equals stays untagged', () {
      expect(
        _classifyWin(
          game,
          beforeWin: 55,
          afterWin: 55,
          bestMove: 'e2e4',
          alternativeWin: 53, // 2pp gap < 5
        ),
        isNull,
      );
    });

    test('engine top with a PV moat is Best', () {
      expect(
        _classifyWin(
          game,
          beforeWin: 52,
          afterWin: 54,
          bestMove: 'e2e4',
          alternativeWin: 44, // 10pp gap ≥ 5
        ),
        GameMoveClassification.goodMove,
      );
    });

    test('win% loss tiers', () {
      // Non-best (engine wanted a2a3).
      expect(_classifyWin(game, beforeWin: 50, afterWin: 46), isNull); // 4
      expect(
        _classifyWin(game, beforeWin: 50, afterWin: 44),
        GameMoveClassification.inaccuracy,
      ); // 6
      expect(
        _classifyWin(game, beforeWin: 50, afterWin: 35),
        GameMoveClassification.mistake,
      ); // 15
      expect(
        _classifyWin(game, beforeWin: 50, afterWin: 25),
        GameMoveClassification.blunder,
      ); // 25
    });

    test('only-good-move or outcome swing is Great', () {
      expect(
        _classifyWin(
          game,
          beforeWin: 52,
          afterWin: 55,
          bestMove: 'e2e4',
          alternativeWin: 40, // gap 15 > 10
        ),
        GameMoveClassification.bestMove,
      );
      expect(
        _classifyWin(
          game,
          beforeWin: 48,
          afterWin: 72,
          bestMove: 'e2e4',
          alternativeWin: 45,
        ),
        GameMoveClassification.bestMove,
      );
    });

    test('decided games soften tags', () {
      expect(_classifyWin(game, beforeWin: 5, afterWin: 0), isNull);
      expect(_classifyWin(game, beforeWin: 99, afterWin: 93), isNull);
    });

    test('missed win when throwing a winning position', () {
      expect(
        _classifyWin(game, beforeWin: 85, afterWin: 45),
        GameMoveClassification.missedWin,
      );
    });

    test('sacrifice and recapture guards inspect the board', () {
      expect(
        isReportPieceSacrifice(
          '4k3/8/8/8/1p6/8/3Q4/4K3 w - - 0 1',
          'd2c3',
          const ['b4c3'],
        ),
        isTrue,
      );
      expect(
        isSimpleReportRecapture(
          '4k3/8/2p5/3p4/4P3/8/8/4K3 w - - 0 1',
          'e4d5',
          'c6d5',
        ),
        isTrue,
      );
    });

    test('report retains the first unplayed candidate as best alternative', () {
      final positions = [
        GameReportPosition(
          fen: game.startingFen,
          lines: [
            _line(cp: 10, moves: const ['e2e4']),
            _line(cp: 5, moves: const ['d2d4']),
          ],
        ),
        GameReportPosition(
          fen: game.mainline.first.fen,
          lines: [_line(cp: 10)],
        ),
      ];
      final report = buildGameAnalysisReport(
        game: game,
        fingerprint: gameReportFingerprint(game),
        positions: positions,
      );
      expect(report.moves.single.bestAlternative, 'd2d4');
      // Tiny multipv gap → not Best
      expect(report.moves.single.classification, isNull);
    });
  });
}

GameMoveClassification? _classifyWin(
  ChessGame game, {
  required double beforeWin,
  required double afterWin,
  String bestMove = 'a2a3',
  double? alternativeWin,
  GameMoveClassification? previousMoveClassification,
}) {
  final alt = alternativeWin;
  final positions = [
    GameReportPosition(
      fen: game.startingFen,
      lines: [
        _line(cp: 0, moves: [bestMove]),
        if (alt != null) _line(cp: 0, moves: const ['h2h3']),
      ],
    ),
    GameReportPosition(
      fen: game.mainline.first.fen,
      lines: [_line(cp: 0)],
    ),
  ];
  if (alt != null) {
    int cpForWin(double w) {
      if (w >= 99) return 1000;
      if (w <= 1) return -1000;
      final wc = (w - 50) / 50;
      final ratio = (1 + wc) / (1 - wc).clamp(1e-6, 1e6);
      final cp = math.log(ratio) / 0.00368208;
      return cp.round().clamp(-1000, 1000);
    }

    final positions2 = [
      GameReportPosition(
        fen: game.startingFen,
        lines: [
          _line(cp: cpForWin(afterWin), moves: [bestMove]),
          _line(cp: cpForWin(alt), moves: const ['h2h3']),
        ],
      ),
      GameReportPosition(
        fen: game.mainline.first.fen,
        lines: [_line(cp: cpForWin(afterWin))],
      ),
    ];
    return classifyGameReportMove(
      index: 0,
      game: game,
      positions: positions2,
      winPercentages: [beforeWin, afterWin],
      previousMoveClassification: previousMoveClassification,
    );
  }

  return classifyGameReportMove(
    index: 0,
    game: game,
    positions: positions,
    winPercentages: [beforeWin, afterWin],
    previousMoveClassification: previousMoveClassification,
  );
}

GameReportPosition _position(int cp) => GameReportPosition(
  fen: '8/8/8/8/8/8/8/K6k w - - 0 1',
  lines: [_line(cp: cp)],
);

GameReportLine _line({
  int cp = 0,
  int? mate,
  List<String> moves = const ['a2a3'],
}) => GameReportLine(
  moves: moves,
  depth: 16,
  centipawns: mate == null ? cp : null,
  mate: mate,
);
