import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/move_position_facts.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the classification rules that make positive symbols mean "exceptional
/// decision" rather than "engine-first move", without letting the tightening
/// swallow genuine errors.
void main() {
  group('position facts', () {
    test('an attacked piece stepping to safety reads as a routine retreat', () {
      final facts = describeMove(
        beforeFen: _retreatFen,
        playedUci: 'd5d8',
      );

      expect(facts.movedPieceWasAttacked, isTrue);
      expect(facts.landsSafely, isTrue);
      expect(facts.isCapture, isFalse);
      expect(facts.isRoutineRetreat, isTrue);
      expect(facts.isForcedOrRoutine, isTrue);
    });

    test('a position with one legal reply to check is forced', () {
      final facts = describeMove(
        beforeFen: _onlyMoveFen,
        playedUci: 'h8h7',
      );

      expect(facts.wasInCheckBefore, isTrue);
      expect(facts.isOnlyLegalMove, isTrue);
      expect(facts.isForcedCheckEvasion, isTrue);
      expect(facts.isForcedOrRoutine, isTrue);
    });

    test('capturing a loose piece is board-level material recovery', () {
      final facts = describeMove(
        beforeFen: _looseCaptureFen,
        playedUci: 'c8c6',
      );

      expect(facts.isCapture, isTrue);
      expect(facts.capturedPieceWasLoose, isTrue);
      expect(facts.givesMaterialBack, isFalse);
      // Still down material after winning the bishop back.
      expect(facts.moverIsMateriallyWorse, isTrue);
      expect(facts.isBoardLevelMaterialRecovery, isTrue);
    });

    test('an unparseable move yields neutral facts, never "routine"', () {
      final facts = describeMove(beforeFen: 'not-a-fen', playedUci: 'e2e4');

      expect(facts.isForcedOrRoutine, isFalse);
      expect(facts.isBoardLevelMaterialRecovery, isFalse);
    });
  });

  group('outcome bands', () {
    test('boundaries follow the documented thresholds', () {
      expect(outcomeBandFor(5), OutcomeBand.clearlyLosing);
      expect(outcomeBandFor(10), OutcomeBand.clearlyLosing);
      expect(outcomeBandFor(20), OutcomeBand.worse);
      expect(outcomeBandFor(50), OutcomeBand.competitive);
      expect(outcomeBandFor(80), OutcomeBand.better);
      expect(outcomeBandFor(95), OutcomeBand.clearlyWinning);
    });

    test('escaping the losing band needs a real gain', () {
      expect(
        escapesClearlyLosingBand(moverBefore: 9, moverAfter: 10.5),
        isFalse,
      );
      expect(escapesClearlyLosingBand(moverBefore: 8, moverAfter: 30), isTrue);
    });
  });

  group('positive labels are withheld from ordinary moves', () {
    test('being PV1 is not enough without a meaningful moat', () {
      final game = _openingGame;
      // Sub-moat gap: still no Best (kBestRequiredPvMoatPp = 2.5).
      expect(
        _classify(
          game,
          moverBefore: 52,
          moverAfter: 54,
          bestMove: 'e2e4',
          alternativeMoverWin: 52, // 2pp < 2.5
        ),
        isNull,
      );
      // Clears Best moat but stays under the Great only-reliable bar.
      expect(
        _classify(
          game,
          moverBefore: 52,
          moverAfter: 54,
          bestMove: 'e2e4',
          alternativeMoverWin: 49, // 5pp ≥ 2.5 and < 7.5
        ),
        GameMoveClassification.goodMove,
      );
    });

    test('only-reliable MultiPV gap of 7.5pp is Great', () {
      // Win% fixtures travel through centipawns, so aim clearly above the
      // 7.5 bar rather than landing on the float boundary.
      expect(
        _classify(
          _openingGame,
          moverBefore: 52,
          moverAfter: 55,
          bestMove: 'e2e4',
          alternativeMoverWin: 46, // ~9pp ≥ kGreatOnlyGoodMoveGapPp
        ),
        GameMoveClassification.bestMove,
      );
      // Under the Great only-reliable bar, still Best when contested + moat.
      expect(
        _classify(
          _openingGame,
          moverBefore: 52,
          moverAfter: 55,
          bestMove: 'e2e4',
          alternativeMoverWin: 50, // ~5pp < 7.5, ≥ 2.5
        ),
        GameMoveClassification.goodMove,
      );
    });

    test('defensive save from a lost position is Great', () {
      // Engine-top resource that escapes clearly-losing. Gap is under the
      // only-reliable bar so this hits the defensive-save supporting path.
      expect(
        _classify(
          _openingGame,
          moverBefore: 8,
          moverAfter: 32,
          bestMove: 'e2e4',
          alternativeMoverWin: 26, // 6pp ≥ kGreatSupportingPathMinGapPp, < 7.5
        ),
        GameMoveClassification.bestMove,
      );
    });

    test('advantage conversion where the alternative slips is Great', () {
      // Keeps a better-band edge; next line drops to competitive with a gap
      // under the only-reliable bar — conversion supporting path.
      expect(
        _classify(
          _openingGame,
          moverBefore: 78,
          moverAfter: 80,
          bestMove: 'e2e4',
          alternativeMoverWin: 74, // 6pp; alt competitive (< 75)
        ),
        GameMoveClassification.bestMove,
      );
    });

    test('Sitges quiet king conversion remains Great', () {
      expect(
        _classify(
          _sitgesKg7Game,
          moverBefore: 81,
          moverAfter: 94,
          bestMove: 'h7g7',
          alternativeMoverWin: 79,
        ),
        GameMoveClassification.bestMove,
      );
    });

    test('Sitges knight sacrifice remains Great', () {
      expect(
        _classify(
          _sitgesNg3Game,
          moverBefore: 86,
          moverAfter: 85,
          bestMove: 'h5g3',
          alternativeMoverWin: 6,
        ),
        GameMoveClassification.bestMove,
      );
    });

    test('Sitges tactical continuation captures earn no praise', () {
      expect(
        _classify(
          _sitgesRxe7Game,
          moverBefore: 14,
          moverAfter: 19,
          bestMove: 'a7e7',
          alternativeMoverWin: 0,
        ),
        isNull,
      );
      expect(
        _classify(
          _sitgesGxf4Game,
          moverBefore: 19,
          moverAfter: 15,
          bestMove: 'g3f4',
          alternativeMoverWin: 1,
        ),
        isNull,
      );
      expect(
        _classify(
          _sitgesBxg1Game,
          moverBefore: 82,
          moverAfter: 82,
          bestMove: 'd4g1',
          alternativeMoverWin: 70,
        ),
        isNull,
      );
    });

    test('Sitges saturated conversion stops positive labels after Nb5', () {
      expect(
        _classify(
          _sitgesQe3Game,
          moverBefore: 99,
          moverAfter: 99,
          bestMove: 'f4e3',
          alternativeMoverWin: 91,
        ),
        isNull,
      );
    });

    test('an attacked rook stepping away earns no symbol', () {
      expect(
        _classify(
          _retreatGame,
          moverBefore: 50,
          moverAfter: 52,
          bestMove: 'd5d8',
          alternativeMoverWin: 30, // a moat that would otherwise mean Best
        ),
        isNull,
      );
    });

    test('the only legal reply to a check earns no symbol', () {
      expect(
        _classify(
          _onlyMoveGame,
          moverBefore: 40,
          moverAfter: 42,
          bestMove: 'h8h7',
          alternativeMoverWin: 20,
        ),
        isNull,
      );
    });

    test('routine material recovery in a worse position earns no symbol', () {
      expect(
        _classify(
          _looseCaptureGame,
          moverBefore: 15,
          moverAfter: 18,
          bestMove: 'c8c6',
          alternativeMoverWin: 5,
        ),
        isNull,
      );
    });

    test('the praise floor is scoped to Great and Best, not Brilliant', () {
      // A capture below the floor loses its Best/Great claim...
      expect(
        _classify(
          _looseCaptureGame,
          moverBefore: 15,
          moverAfter: 18,
          bestMove: 'c8c6',
          alternativeMoverWin: 5,
        ),
        isNull,
      );
      // ...but the floor must never be the thing that decides Brilliant. That
      // verdict belongs to verifyBrilliantMove alone, which rejects this move
      // on its own terms (no material investment), not via the floor.
      expect(
        verifyBrilliantMove(
          index: 0,
          game: _looseCaptureGame,
          positions: _looseCapturePositions,
          winPercentages: const [85, 82],
          moverChange: 3,
          playedIsBest: true,
          alternativeWin: 95,
          alternativeGap: 13,
          simpleRecapture: false,
        ),
        isFalse,
      );
    });

    test('a recovery that escapes the losing band keeps its symbol', () {
      // Same routine-looking capture, but it drags the mover out of a lost
      // position — exactly the exception the suppression must not swallow.
      expect(
        _classify(
          _looseCaptureGame,
          moverBefore: 8,
          moverAfter: 45,
          bestMove: 'c8c6',
          alternativeMoverWin: 20,
        ),
        isNotNull,
      );
    });
  });

  group('suppression vetoes praise only, never the damage', () {
    test('a routine retreat that loses real ground is still a Mistake', () {
      expect(
        _classify(
          _retreatGame,
          moverBefore: 50,
          moverAfter: 35,
          bestMove: 'd5d6',
        ),
        GameMoveClassification.mistake,
      );
    });

    test('a routine capture that loses real ground is still an Inaccuracy', () {
      expect(
        _classify(
          _looseCaptureGame,
          moverBefore: 50,
          moverAfter: 43,
          bestMove: 'c8d8',
        ),
        GameMoveClassification.inaccuracy,
      );
    });
  });

  group('book moves', () {
    test('theory replaces praise and "no symbol" alike', () {
      for (final label in [
        null,
        GameMoveClassification.brilliant,
        GameMoveClassification.bestMove,
        GameMoveClassification.goodMove,
      ]) {
        expect(
          applyBookMoveOverride(label, 250),
          GameMoveClassification.bookMove,
          reason: '$label in a well-known line should read as Book',
        );
      }
    });

    test('theory never covers up an error', () {
      // A hundred players can walk into the same trap, so a popular move that
      // damages the position keeps its symbol.
      for (final label in [
        GameMoveClassification.inaccuracy,
        GameMoveClassification.mistake,
        GameMoveClassification.blunder,
        GameMoveClassification.missedWin,
      ]) {
        expect(applyBookMoveOverride(label, 5000), label);
      }
    });

    test('the threshold is a floor of ten games', () {
      expect(
        applyBookMoveOverride(null, kBookMoveMinGames - 1),
        isNull,
      );
      expect(
        applyBookMoveOverride(null, kBookMoveMinGames),
        GameMoveClassification.bookMove,
      );
    });

    test('an unknown count is not treated as out of book', () {
      // null means "we never found out" — it must leave the label untouched
      // rather than silently asserting the move is not theory.
      expect(
        applyBookMoveOverride(GameMoveClassification.brilliant, null),
        GameMoveClassification.brilliant,
      );
      expect(applyBookMoveOverride(null, 0), isNull);
    });

    test('the report labels opening moves Book and stops leaving theory', () {
      final game = ChessGame.fromPgn(
        'book',
        '[White "Ada"]\n[Black "Grace"]\n\n1. e4 e5 2. Nf3 *',
      );
      final positions = [
        for (var i = 0; i <= game.mainline.length; i++)
          GameReportPosition(
            fen: i == 0 ? game.startingFen : game.mainline[i - 1].fen,
            lines: [_line(cp: 20, moves: const ['g1f3'])],
          ),
      ];

      final report = buildGameAnalysisReport(
        game: game,
        fingerprint: 'book',
        positions: positions,
        // 1.e4 and 1...e5 are theory; the walk stopped before 2.Nf3.
        bookGameCounts: const [4000, 3000, null],
      );

      expect(
        report.moves.map((move) => move.classification).toList(),
        [
          GameMoveClassification.bookMove,
          GameMoveClassification.bookMove,
          isNot(GameMoveClassification.bookMove),
        ],
      );
      expect(report.count(GameMoveClassification.bookMove, white: true), 1);
      expect(report.count(GameMoveClassification.bookMove, white: false), 1);
    });
  });

  group('opening tree probe', () {
    test('a lone quiet ply does not close the book behind it', () async {
      // A move order can leave the database for one ply and transpose straight
      // back into a main line. The explorer counts that transposition, so the
      // walk must carry on and label the moves that follow it.
      final probed = <String>[];
      final controller = GameAnalysisReportController(
        evaluator: _stubEvaluator,
        bookLookup: (fen, uci, path) async {
          probed.add(uci);
          return uci == 'a7a6' ? 2 : 900;
        },
      );
      addTearDown(controller.dispose);

      await controller.analyze(
        ChessGame.fromPgn('probe', '1. e4 a6 2. Nf3 b6 3. Bc4 c6 *'),
      );

      expect(controller.state.status, GameReportStatus.completed);
      expect(probed, ['e2e4', 'a7a6', 'g1f3', 'b7b6', 'f1c4', 'c7c6']);
      final classifications = controller.state.report!.moves
          .map((move) => move.classification)
          .toList();
      expect(classifications[1], isNot(GameMoveClassification.bookMove));
      expect(
        [classifications[0], ...classifications.skip(2)],
        everyElement(GameMoveClassification.bookMove),
      );
    });

    test('the walk gives up after a run of moves out of book', () async {
      var probed = 0;
      final controller = GameAnalysisReportController(
        evaluator: _stubEvaluator,
        bookLookup: (fen, uci, path) async {
          probed++;
          return uci == 'e2e4' ? 900 : 1;
        },
      );
      addTearDown(controller.dispose);

      await controller.analyze(
        ChessGame.fromPgn(
          'dry',
          '1. e4 a6 2. Nf3 b6 3. Bc4 c6 4. d3 d6 5. Nc3 e6 6. Bg5 f6 '
              '7. Qd2 g6 8. h4 h6 *',
        ),
      );

      expect(controller.state.status, GameReportStatus.completed);
      // One theory move, then the dry streak ends it — rounded up to the last
      // full wave of concurrent lookups.
      expect(probed, lessThan(12));
      final moves = controller.state.report!.moves;
      expect(moves.first.classification, GameMoveClassification.bookMove);
      expect(
        moves.skip(1).map((move) => move.classification),
        everyElement(isNot(GameMoveClassification.bookMove)),
      );
    });

    test('the move line is handed to every lookup', () async {
      // Without the line the backend cannot rebuild a node past its indexed
      // opening window, and deep theory comes back empty.
      final paths = <List<String>>[];
      final controller = GameAnalysisReportController(
        evaluator: _stubEvaluator,
        bookLookup: (fen, uci, path) async {
          paths.add(path);
          return 900;
        },
      );
      addTearDown(controller.dispose);

      await controller.analyze(ChessGame.fromPgn('line', '1. e4 e5 2. Nf3 *'));

      expect(paths, [
        <String>[],
        ['e2e4'],
        ['e2e4', 'e7e5'],
      ]);
    });

    test('a game set up from a custom position is never probed', () async {
      // The gamebase reads a position's ply off the FEN's side-to-move and
      // fullmove number, so a custom setup would address the wrong ply on every
      // request. Such a game has no opening book at all.
      var probed = 0;
      final controller = GameAnalysisReportController(
        evaluator: _stubEvaluator,
        bookLookup: (fen, uci, path) async {
          probed++;
          return 5000;
        },
      );
      addTearDown(controller.dispose);

      await controller.analyze(_retreatGame);

      expect(controller.state.status, GameReportStatus.completed);
      expect(probed, 0);
      expect(
        controller.state.report!.moves.map((move) => move.classification),
        everyElement(isNot(GameMoveClassification.bookMove)),
      );
    });

    test('a castle matches the database spelling of the same move', () {
      // dartchess hands the board `e1h1`; the gamebase answers `e1g1`. Compared
      // raw they never matched, so every castle counted as zero games and book
      // detection died the first time either side castled.
      expect(gamebaseAggregateMatchesMove('e1g1', 'e1h1'), isTrue);
      expect(gamebaseAggregateMatchesMove('e1c1', 'e1a1'), isTrue);
      expect(gamebaseAggregateMatchesMove('e8g8', 'e8h8'), isTrue);
      expect(gamebaseAggregateMatchesMove('e8c8', 'e8a8'), isTrue);
      expect(gamebaseAggregateMatchesMove('g1f3', 'g1f3'), isTrue);
      expect(gamebaseAggregateMatchesMove('e1g1', 'e1c1'), isFalse);
    });

    test('the probe reaches real theory depth', () {
      // Handed the move line the gamebase keeps answering well past its
      // materialised view, and real theory runs past move fifteen, so the cap
      // is a runaway guard rather than the depth of book.
      expect(kBookProbeMaxPlies, greaterThanOrEqualTo(40));
    });

    test('a hanging tree never holds the report open', () async {
      final controller = GameAnalysisReportController(
        evaluator: _stubEvaluator,
        bookLookup: (fen, uci, path) => Completer<int?>().future,
      );
      addTearDown(controller.dispose);

      await controller.analyze(ChessGame.fromPgn('slow', '1. e4 e5 *'));

      expect(controller.state.status, GameReportStatus.completed);
      expect(
        controller.state.report!.moves.map((move) => move.classification),
        everyElement(isNot(GameMoveClassification.bookMove)),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a failing tree never fails the report', () async {
      final controller = GameAnalysisReportController(
        evaluator: _stubEvaluator,
        bookLookup: (fen, uci, path) async => throw StateError('gamebase down'),
      );
      addTearDown(controller.dispose);

      await controller.analyze(ChessGame.fromPgn('offline', '1. e4 e5 *'));

      expect(controller.state.status, GameReportStatus.completed);
      expect(
        controller.state.report!.moves.map((move) => move.classification),
        everyElement(isNot(GameMoveClassification.bookMove)),
      );
    });

    test('no tree configured leaves every move unlabelled by book', () async {
      final controller = GameAnalysisReportController(
        evaluator: _stubEvaluator,
      );
      addTearDown(controller.dispose);

      await controller.analyze(ChessGame.fromPgn('nobook', '1. e4 e5 *'));

      expect(controller.state.status, GameReportStatus.completed);
      expect(
        controller.state.report!.moves.map((move) => move.classification),
        everyElement(isNot(GameMoveClassification.bookMove)),
      );
    });
  });

  group('decided outcomes stay quiet while contested outcomes are judged', () {
    test('a compressed loss in a decisively lost position is unlabelled', () {
      // 12% -> 6% remains below the 23% decisive-loss ceiling.
      expect(
        _classify(_openingGame, moverBefore: 12, moverAfter: 6),
        isNull,
      );
    });

    test('a big cp swing while crushing stays unlabelled', () {
      // 97% -> 93% is a ~240cp swing worth 0.09 winning chances: under the bar.
      expect(
        _classify(
          _openingGame,
          moverBefore: 97,
          moverAfter: 93,
          replyUci: 'e7e6',
        ),
        isNull,
      );
    });

    test('handing over a contested game is a Blunder', () {
      expect(
        _classify(_openingGame, moverBefore: 60, moverAfter: 30),
        GameMoveClassification.blunder,
      );
    });
  });
}

// ── Fixtures ────────────────────────────────────────────────────────────────

/// Black rook on d5 attacked by the e4 pawn; Rd8 steps away.
const _retreatFen = '4k3/8/8/3r4/4P3/8/8/4K3 b - - 0 1';

/// Black is in check from Qa8 and Rg1 covers the g-file: Kh7 is the only move.
const _onlyMoveFen = 'Q6k/8/8/8/8/8/8/K5R1 b - - 0 1';

/// Black is down a rook and a bishop; Rxc6 takes an undefended bishop back and
/// is still materially worse afterwards.
const _looseCaptureFen = '2r1k3/8/2B5/8/8/8/8/R3K2R b - - 0 1';

/// Owner-reviewed Sitges regression positions from Nidhish–Asis, round 8.
const _sitgesNg3Fen =
    '5q2/R3r1bk/3p2p1/3P3n/2pBPp1p/2Nn3P/1P4QP/6RK b - - 11 37';
const _sitgesRxe7Fen =
    '5q2/R3r2k/3p2p1/3P4/2pbPp1p/2Nn2PP/1P4Q1/6RK w - - 0 39';
const _sitgesGxf4Fen = '8/4q2k/3p2p1/3P4/2pbPp1p/2Nn2PP/1P4Q1/6RK w - - 0 40';
const _sitgesBxg1Fen = '8/4q2k/3p2p1/3P4/2pbPP1p/2Nn3P/1P4Q1/6RK b - - 0 40';
const _sitgesKg7Fen = '8/7k/3p2p1/3P2q1/2p1Pn1p/2N2Q1P/1P6/7K b - - 3 43';
const _sitgesQe3Fen = '8/6k1/3p2p1/1N1P4/2p1Pq1p/3n3P/1P4Q1/6K1 b - - 11 47';

final _openingGame = ChessGame.fromPgn(
  'opening',
  '[White "Ada"]\n[Black "Grace"]\n\n1. e4 e5 *',
);

final _retreatGame = _gameFromFen(_retreatFen, '1... Rd8 *');
final _onlyMoveGame = _gameFromFen(_onlyMoveFen, '1... Kh7 *');
final _looseCaptureGame = _gameFromFen(_looseCaptureFen, '1... Rxc6 *');
final _sitgesNg3Game = _gameFromFen(_sitgesNg3Fen, '37... Ng3+ *');
final _sitgesRxe7Game = _gameFromFen(_sitgesRxe7Fen, '39. Rxe7+ *');
final _sitgesGxf4Game = _gameFromFen(_sitgesGxf4Fen, '40. gxf4 *');
final _sitgesBxg1Game = _gameFromFen(_sitgesBxg1Fen, '40... Bxg1 *');
final _sitgesKg7Game = _gameFromFen(_sitgesKg7Fen, '43... Kg7 *');
final _sitgesQe3Game = _gameFromFen(_sitgesQe3Fen, '47... Qe3+ *');

/// Positions for the loose-capture fixture, scored so the mover sits well above
/// the praise floor — isolating [verifyBrilliantMove]'s own verdict from it.
final _looseCapturePositions = [
  GameReportPosition(
    fen: _looseCaptureFen,
    lines: [
      _line(cp: -300, moves: const ['c8c6']),
      _line(cp: -600, moves: const ['c8d8']),
    ],
  ),
  GameReportPosition(
    fen: _looseCaptureGame.mainline.first.fen,
    lines: [_line(cp: -300, moves: const ['e1d2'])],
  ),
];

ChessGame _gameFromFen(String fen, String moves) => ChessGame.fromPgn(
  'fixture',
  '[SetUp "1"]\n[FEN "$fen"]\n\n$moves',
);

/// Classifies the first move of [game] from mover-relative winning chances.
///
/// Engine scores are derived from the same percentages so the centipawn
/// evidence the tactical override reads stays consistent with the win% the
/// tiers read — a mismatch between the two would make these tests meaningless.
GameMoveClassification? _classify(
  ChessGame game, {
  required double moverBefore,
  required double moverAfter,
  String bestMove = 'a2a3',
  double? alternativeMoverWin,
  String replyUci = 'z9z9',
  GameMoveClassification? previousMoveClassification,
}) {
  final isWhite = game.mainline.first.turn == ChessColor.white;
  double toWhite(double moverWin) => isWhite ? moverWin : 100 - moverWin;

  final whiteBefore = toWhite(moverBefore);
  final whiteAfter = toWhite(moverAfter);
  final alt = alternativeMoverWin;

  final positions = [
    GameReportPosition(
      // In production winPercentages[i] is read straight off
      // positions[i].bestLine, so the before-position must score the *before*
      // percentage. Scoring it with the after value would hide the centipawn
      // swing the tactical override exists to measure.
      fen: game.startingFen,
      lines: [
        _line(cp: _cpForWin(whiteBefore), moves: [bestMove]),
        if (alt != null)
          _line(cp: _cpForWin(toWhite(alt)), moves: const ['a7a6']),
      ],
    ),
    GameReportPosition(
      fen: game.mainline.first.fen,
      lines: [
        _line(cp: _cpForWin(whiteAfter), moves: [replyUci]),
      ],
    ),
  ];

  return classifyGameReportMove(
    index: 0,
    game: game,
    positions: positions,
    winPercentages: [whiteBefore, whiteAfter],
    previousMoveClassification: previousMoveClassification,
  );
}

/// Inverse of [gameReportWinPercentage], so a fixture can be written in the
/// percentages the product reasons about and still carry believable scores.
int _cpForWin(double whiteWin) {
  if (whiteWin >= 99) return 1000;
  if (whiteWin <= 1) return -1000;
  final wc = (whiteWin - 50) / 50;
  final ratio = (1 + wc) / (1 - wc);
  return (math.log(ratio) / 0.00368208).round().clamp(-1000, 1000);
}

GameReportLine _line({int cp = 0, List<String> moves = const ['a2a3']}) =>
    GameReportLine(moves: moves, depth: 16, centipawns: cp);

/// Flat evaluator: every position is a quiet +0.20, so classifications come
/// from the book rules under test rather than from engine swings.
Future<EnhancedCloudEval> _stubEvaluator(
  String fen, {
  required int depth,
  required int multiPv,
  required String ownerId,
  void Function(int reachedDepth, int knodes)? onProgress,
}) async => EnhancedCloudEval(
  fen: fen,
  knodes: 100,
  depth: depth,
  pvs: [Pv(moves: 'a2a3', cp: 20)],
  requestedMultiPv: multiPv,
);
