import 'dart:async';
import 'dart:io';

import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:flutter_test/flutter_test.dart';

const rc7Fen = '5rk1/8/bp2pn1p/p2pNppq/3P1P2/1P3N2/P2Q1PKP/2R5 w - - 0 31';

GameReportLine line(String pv, int cp, {int depth = 18}) =>
    GameReportLine(moves: pv.split(' '), depth: depth, centipawns: cp);
GameReportPosition sample(
  String fen,
  List<GameReportLine> lines, {
  String id = 'test',
  bool complete = true,
}) => GameReportPosition(
  fen: fen,
  lines: lines,
  search: GameReportSearchEvidence(
    engineId: 'Stockfish 18',
    searchId: id,
    complete: complete,
  ),
);
ChessGame rc7Game() => ChessGame.fromPgn(
  'rc7',
  '[SetUp "1"]\n[FEN "$rc7Fen"]\n\n31. Rc7 Qh3+ 32. Kg1 Qf1#',
);
List<GameReportPosition> shallow(ChessGame game) => [
  sample(game.startingFen, [
    line('c1c7 f5f4', 70, depth: 15),
    line('d2e3', 0, depth: 15),
  ]),
  sample(game.mainline[0].fen, [
    line('h5h3 g2h1 h3f1 f3g1 f6e4', -736, depth: 16),
  ]),
  sample(game.mainline[1].fen, [line('g2h1 h3f1 f3g1 f6e4', -796, depth: 16)]),
  sample(game.mainline[2].fen, [line('h3f1', -900, depth: 16)]),
  terminalGameReportPosition(game.mainline[3].fen)!,
];

void main() {
  test('a real outcome crossing triggers confirmation even below 10pp', () {
    final game = ChessGame.fromPgn('outcome-crossing', '1. e4 *');
    final p = [
      sample(game.startingFen, [line('d2d4', 250), line('c2c4', 240)]),
      sample(game.mainline.first.fen, [line('e7e5', 325)]),
    ];
    expect(
      gameReportMoveNeedsConfirmation(index: 0, game: game, positions: p),
      true,
    );
  });

  test(
    'mate sign changes trigger confirmation; same winning cp/mate outcome does not',
    () {
      final game = ChessGame.fromPgn('mate-policy', '1. e4 *');
      final root = sample(game.startingFen, [
        const GameReportLine(moves: ['e2e4'], depth: 18, mate: 5),
        line('d2d4', 0),
      ]);
      for (final after in [
        const GameReportLine(moves: ['e7e5'], depth: 18, mate: -5),
        line('e7e5', 0),
      ]) {
        expect(
          gameReportMoveNeedsConfirmation(
            index: 0,
            game: game,
            positions: [
              root,
              sample(game.mainline.first.fen, [after]),
            ],
          ),
          true,
        );
      }
      expect(
        gameReportMoveNeedsConfirmation(
          index: 0,
          game: game,
          positions: [
            root,
            sample(game.mainline.first.fen, [line('e7e5', 419)]),
          ],
        ),
        false,
      );
      expect(
        gameReportSnapshotIsCoherent(
          sample(game.startingFen, [
            const GameReportLine(moves: ['e2e4'], depth: 18, mate: 0),
          ]),
        ),
        false,
      );
    },
  );
  test(
    'count, total-time and depth budget exhaustion are explicit and bounded',
    () async {
      final game = rc7Game();
      for (final budget in [
        const GameReportConfirmationBudget(maxConflicts: 0),
        const GameReportConfirmationBudget(maxSearchesPerConflict: 0),
        const GameReportConfirmationBudget(maxTimeTotal: Duration.zero),
        const GameReportConfirmationBudget(depths: [21, 24]),
      ]) {
        var calls = 0;
        final result = await confirmGameReportConsistency(
          game: game,
          positions: shallow(game),
          isCancelled: () => false,
          budget: budget,
          evaluate: (_) async {
            calls++;
            throw StateError('Must not search');
          },
        );
        expect(calls, 0);
        expect(result.first.uncertainty, isNotNull);
      }
    },
  );

  test(
    'captured Rc7 contradictory PV1 is detected without deleting hasVariation',
    () {
      final game = rc7Game();
      expect(
        gameReportMoveNeedsConfirmation(
          index: 0,
          game: game,
          positions: shallow(game),
        ),
        isTrue,
      );
      expect(
        lichessJudgementForReportMove(
          index: 0,
          game: game,
          positions: shallow(game),
        ),
        isNull,
      );
    },
  );

  test(
    'bounded confirmation replaces both snapshots, verdict and accuracy coherently',
    () async {
      final game = rc7Game();
      final requests = <GameReportConfirmationRequest>[];
      final confirmed = await confirmGameReportConsistency(
        game: game,
        positions: shallow(game),
        isCancelled: () => false,
        budget: const GameReportConfirmationBudget(maxConflicts: 1),
        evaluate: (request) async {
          requests.add(request);
          if (request.fen == game.startingFen) {
            return sample(request.fen, [
              line('d2e3', 31),
              line('b3b4', 2),
              line('f3g1', 0),
            ]);
          }
          return sample(request.fen, [line('h5h3 g2h1 h3f1 f3g1 f6e4', -729)]);
        },
      );
      expect(requests.length, 2);
      expect(
        requests.every(
          (r) => r.depth == 18 && r.maxNodes > 0 && r.maxTime > Duration.zero,
        ),
        isTrue,
      );
      final report = buildGameAnalysisReport(
        game: game,
        fingerprint: gameReportFingerprint(game),
        positions: confirmed,
      );
      expect(report.moves.first.classification, GameMoveClassification.blunder);
      expect(report.moves.first.bestAlternative, 'd2e3');
      expect(report.positions.first.bestLine.centipawns, 31);
      final wins = confirmed
          .map((p) => gameReportWinPercentage(p.bestLine))
          .toList();
      expect(report.whiteAccuracy, computeGameReportAccuracy(wins).white);
      expect(report.whiteAccuracy, lessThan(99));
    },
  );

  test('unresolved conflict is diagnostic and cannot mint praise', () async {
    final game = rc7Game();
    var count = 0;
    final confirmed = await confirmGameReportConsistency(
      game: game,
      positions: shallow(game),
      isCancelled: () => false,
      budget: const GameReportConfirmationBudget(
        maxConflicts: 1,
        maxSearchesPerConflict: 2,
      ),
      evaluate: (request) async {
        count++;
        return sample(
          request.fen,
          request.fen == game.startingFen
              ? [line('c1c7', 70), line('d2e3', 0)]
              : [line('h5h3 g2h1 h3f1 f3g1 f6e4', -736)],
        );
      },
    );
    expect(count, 2);
    expect(confirmed.first.uncertainty, isNotNull);
    expect(
      buildGameAnalysisReport(
        game: game,
        fingerprint: 'x',
        positions: confirmed,
      ).moves.first.classification,
      isNull,
    );
  });

  test(
    'wrong FEN, illegal PV and incomplete batch never replace captured anchors',
    () async {
      final game = rc7Game();
      for (final invalid in [
        sample('wrong', [line('d2e3', 31)]),
        sample(game.startingFen, [line('d2e3 a1a8', 31)]),
        sample(game.startingFen, [line('d2e3', 31)], complete: false),
        sample(game.startingFen, [line('d2e3', 31, depth: 17)]),
      ]) {
        final confirmed = await confirmGameReportConsistency(
          game: game,
          positions: shallow(game),
          isCancelled: () => false,
          budget: const GameReportConfirmationBudget(
            maxConflicts: 1,
            maxSearchesPerConflict: 2,
          ),
          evaluate: (request) async => invalid,
        );
        expect(confirmed.first.bestLine.centipawns, 70);
        expect(confirmed.first.uncertainty, isNotNull);
      }
    },
  );

  test(
    'timeout cancels search and late results cannot mutate the returned report',
    () async {
      final game = rc7Game();
      final pending = Completer<GameReportPosition>();
      var cancelled = 0;
      final confirmed = await confirmGameReportConsistency(
        game: game,
        positions: shallow(game),
        isCancelled: () => false,
        budget: const GameReportConfirmationBudget(
          maxTimePerSearch: Duration(milliseconds: 10),
          maxSearchesPerConflict: 1,
        ),
        cancelSearch: () async {
          cancelled++;
        },
        evaluate: (_) => pending.future,
      );
      expect(cancelled, 1);
      expect(confirmed.first.uncertainty, isNotNull);
      pending.complete(sample(game.startingFen, [line('d2e3', 31)]));
      await Future<void>.delayed(Duration.zero);
      expect(confirmed.first.bestLine.centipawns, 70);
    },
  );

  test('cancellation prevents further confirmation searches', () async {
    final game = rc7Game();
    var cancelled = false;
    var calls = 0;
    final result = await confirmGameReportConsistency(
      game: game,
      positions: shallow(game),
      isCancelled: () => cancelled,
      evaluate: (r) async {
        calls++;
        cancelled = true;
        return sample(r.fen, [line('d2e3', 31)]);
      },
    );
    expect(calls, 1);
    expect(result.first.bestLine.centipawns, 70);
  });

  test(
    'positive moat is SAME ROOT, not child minus an unrelated alternative',
    () {
      final game = ChessGame.fromPgn('same-root', '1. e4 *');
      final positions = [
        sample(game.startingFen, [line('e2e4', 20), line('d2d4', 19)]),
        sample(game.mainline.first.fen, [line('e7e5', 150)]),
      ];
      final report = buildGameAnalysisReport(
        game: game,
        fingerprint: 'x',
        positions: positions,
      );
      expect(report.moves.first.classification, isNull);
    },
  );

  test('saturated winning magnitudes are not an automatic contradiction', () {
    final game = ChessGame.fromPgn('saturated', '1. e4 *');
    final positions = [
      sample(game.startingFen, [line('e2e4', 2500), line('d2d4', 900)]),
      sample(game.mainline.first.fen, [line('e7e5', 850)]),
    ];
    expect(
      gameReportMoveNeedsConfirmation(
        index: 0,
        game: game,
        positions: positions,
      ),
      isFalse,
    );
    expect(
      buildGameAnalysisReport(
        game: game,
        fingerprint: 'x',
        positions: positions,
      ).moves.first.classification,
      isNull,
    );
  });

  test('same-root quality mismatch withholds unsupported praise', () {
    final game = ChessGame.fromPgn('quality', '1. e4 *');
    for (final root in [
      sample(game.startingFen, [
        line('e2e4', 20),
        line('d2d4', -200, depth: 15),
      ]),
      sample(game.startingFen, [
        line('e2e4', 20),
        line('d2d4', -200),
      ], complete: false),
    ]) {
      final positions = [
        root,
        sample(game.mainline.first.fen, [line('e7e5', 20)]),
      ];
      expect(
        buildGameAnalysisReport(
          game: game,
          fingerprint: 'x',
          positions: positions,
        ).moves.first.classification,
        isNull,
      );
    }
  });

  test(
    'actual captured PGN includes legal native critical punishment prehistory',
    () {
      final pgn = File('test/fixtures/native_rc7.pgn').readAsStringSync();
      final game = ChessGame.fromPgn('captured', pgn);
      expect(game.mainline.length, 64);
      expect(game.mainline[60].uci, 'c1c7');
      expect(game.mainline[61].uci, 'h5h3');
    },
  );
}
