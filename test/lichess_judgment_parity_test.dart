import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/lichess_judgment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins `?!`, `?` and `??` to lichess's own rules, boundary by boundary.
///
/// Every expectation here is derived from the Scala, not from what feels right:
/// `CpAdvice` / `MateAdvice` / `MateSequence` in
/// `lila/modules/tree/src/main/Advice.scala`, the `hasVariation` gate in
/// `Analysis.infoAdvices`, and `WinPercent.winningChances` in
/// `scalachess/core/src/main/scala/eval.scala`. If one of these fails, the port
/// has drifted — go and read the Scala before changing a number.
void main() {
  group('winningChances', () {
    test('is lichess\'s curve', () {
      expect(lichessWinningChances(0), 0);
      // lila's own starting evaluation, +0.15.
      expect(lichessWinningChances(15), closeTo(0.027609, 1e-6));
      expect(lichessWinningChances(100), closeTo(0.182052, 1e-6));
      expect(lichessWinningChances(1000), closeTo(0.950895, 1e-6));
      expect(lichessWinningChances(-1000), closeTo(-0.950895, 1e-6));
    });

    test('clamps the result, not the centipawns', () {
      // The advice path calls winningChances directly and never ceils the score,
      // so +30.00 really is further from +10.00 here. Clamping the input instead
      // would move every threshold in a decided position.
      expect(
        lichessWinningChances(3000),
        greaterThan(lichessWinningChances(1000)),
      );
      expect(lichessWinningChances(100000), 1);
      expect(lichessWinningChances(-100000), -1);
    });
  });

  group('CpAdvice thresholds', () {
    // From dead level, the exact centipawn at which each verdict starts. The
    // table is 0.3 / 0.2 / 0.1 winning chances — half as many points as the
    // 0–100 win percentage the eval graph draws.
    test('Inaccuracy starts at 0.1 winning chances', () {
      expect(_advice(from: 0, to: -54), isNull);
      expect(_advice(from: 0, to: -55), LichessJudgement.inaccuracy);
    });

    test('Mistake starts at 0.2', () {
      expect(_advice(from: 0, to: -110), LichessJudgement.inaccuracy);
      expect(_advice(from: 0, to: -111), LichessJudgement.mistake);
    });

    test('Blunder starts at 0.3', () {
      expect(_advice(from: 0, to: -168), LichessJudgement.mistake);
      expect(_advice(from: 0, to: -169), LichessJudgement.blunder);
    });

    test('the mover\'s sign is applied, so Black is judged in mirror', () {
      // Scores are White-relative: +0.55 for White is Black losing 0.1.
      expect(_advice(from: 0, to: 55, moverIsWhite: false),
          LichessJudgement.inaccuracy);
      expect(_advice(from: 0, to: -55, moverIsWhite: false), isNull);
    });

    test('improving the position is never an error', () {
      expect(_advice(from: 0, to: 400), isNull);
      // White's score falling is Black gaining ground.
      expect(_advice(from: 400, to: 0, moverIsWhite: false), isNull);
    });

    test('a big edge still has enough left to lose to be judged', () {
      // +30.00 down to +7.00 is 0.14 winning chances. An implementation that
      // ceiled the score at ±10.00 first would see 0.09 and say nothing — this
      // is the case that tells the two apart.
      expect(_advice(from: 3000, to: 700), LichessJudgement.inaccuracy);
    });
  });

  group('the hasVariation gate', () {
    test('the engine\'s own move is never an error', () {
      // `infoAdvices` only asks for a judgment when the engine's line starts
      // with a different move: if there was nothing better to play, there is
      // nothing to punish, however far the evaluation fell.
      expect(
        lichessAdvice(
          previous: const CpScore(0),
          current: const CpScore(-900),
          moverIsWhite: true,
          engineBestUci: 'e2e4',
          playedUci: 'e2e4',
        ),
        isNull,
      );
    });

    test('a position the engine gave no line for is never judged', () {
      expect(
        lichessAdvice(
          previous: const CpScore(0),
          current: const CpScore(-900),
          moverIsWhite: true,
          engineBestUci: null,
          playedUci: 'e2e4',
        ),
        isNull,
      );
    });

    test('a missing score at either end is never judged', () {
      expect(
        lichessAdvice(
          previous: null,
          current: const CpScore(-900),
          moverIsWhite: true,
          engineBestUci: 'd2d4',
          playedUci: 'e2e4',
        ),
        isNull,
      );
    });
  });

  group('MateAdvice — a mate created against the mover', () {
    test('severity comes from how lost the mover already was', () {
      expect(_mateAdvice(fromCp: 50), LichessJudgement.blunder);
      expect(_mateAdvice(fromCp: -700), LichessJudgement.blunder);
      expect(_mateAdvice(fromCp: -701), LichessJudgement.mistake);
      expect(_mateAdvice(fromCp: -999), LichessJudgement.mistake);
      expect(_mateAdvice(fromCp: -1000), LichessJudgement.inaccuracy);
    });

    test('delivering mate is not an error', () {
      expect(
        _judge(const CpScore(0), const MateScore(4)),
        isNull,
      );
    });
  });

  group('MateAdvice — a forced mate thrown away', () {
    test('severity comes from what is left of the position', () {
      expect(_lostMateAdvice(toCp: 400), LichessJudgement.blunder);
      expect(_lostMateAdvice(toCp: 700), LichessJudgement.blunder);
      expect(_lostMateAdvice(toCp: 701), LichessJudgement.mistake);
      expect(_lostMateAdvice(toCp: 999), LichessJudgement.mistake);
      expect(_lostMateAdvice(toCp: 1000), LichessJudgement.inaccuracy);
    });

    test('trading your own mate for the opponent\'s is a Blunder', () {
      // A mate at both ends carries no centipawns, so both softening tests fall
      // through — `Score.cp.so(_.centipawns)` is zero.
      expect(
        _judge(const MateScore(3), const MateScore(-2)),
        LichessJudgement.blunder,
      );
    });
  });

  group('MateAdvice — the transitions lichess passes over in silence', () {
    test('a mate held, however much later', () {
      expect(_judge(const MateScore(3), const MateScore(9)), isNull);
    });

    test('being mated, however much sooner', () {
      expect(_judge(const MateScore(-9), const MateScore(-3)), isNull);
    });

    test('escaping a mate', () {
      expect(_judge(const MateScore(-4), const CpScore(-800)), isNull);
    });
  });

  group('glyphs', () {
    test('match lichess\'s move-assessment NAGs', () {
      expect(LichessJudgement.inaccuracy.glyph, '?!');
      expect(LichessJudgement.mistake.glyph, '?');
      expect(LichessJudgement.blunder.glyph, '??');
    });
  });

  group('the report feeds the judgment its own engine lines', () {
    final game = ChessGame.fromPgn('parity', '1. e4 *');

    test('scores come from the position before and after the move', () {
      expect(
        lichessJudgementForReportMove(
          index: 0,
          game: game,
          positions: _positions(before: 0, after: -169, engineBest: 'd2d4'),
        ),
        LichessJudgement.blunder,
      );
    });

    test('move one is measured against our real starting evaluation', () {
      // The one deliberate deviation: lichess compares the first move against a
      // fixed +0.15 because fishnet never evaluates the starting position. We do
      // evaluate it, so +0.60 down to level is judged on the 0.11 it really
      // cost, where lichess's placeholder baseline would have said nothing.
      expect(
        lichessJudgementForReportMove(
          index: 0,
          game: game,
          positions: _positions(before: 60, after: 0, engineBest: 'd2d4'),
        ),
        LichessJudgement.inaccuracy,
      );
    });

    test('an index off the end of the game is not judged', () {
      expect(
        lichessJudgementForReportMove(
          index: 5,
          game: game,
          positions: _positions(before: 0, after: -900, engineBest: 'd2d4'),
        ),
        isNull,
      );
    });
  });
}

LichessJudgement? _advice({
  required int from,
  required int to,
  bool moverIsWhite = true,
}) => _judge(CpScore(from), CpScore(to), moverIsWhite: moverIsWhite);

/// `MateCreated`: the mover was on centipawns and is now the one being mated.
LichessJudgement? _mateAdvice({required int fromCp}) =>
    _judge(CpScore(fromCp), const MateScore(-5));

/// `MateLost`: the mover had a forced mate and gave it up for centipawns.
LichessJudgement? _lostMateAdvice({required int toCp}) =>
    _judge(const MateScore(6), CpScore(toCp));

LichessJudgement? _judge(
  EngineScore previous,
  EngineScore current, {
  bool moverIsWhite = true,
}) => lichessAdvice(
  previous: previous,
  current: current,
  moverIsWhite: moverIsWhite,
  // Any move other than the one played, so the gate is open and the rules under
  // test are what decide.
  engineBestUci: 'd2d4',
  playedUci: 'e2e4',
);

List<GameReportPosition> _positions({
  required int before,
  required int after,
  required String engineBest,
}) => [
  GameReportPosition(
    fen: ChessGame.fromPgn('parity', '1. e4 *').startingFen,
    lines: [
      GameReportLine(moves: [engineBest], depth: 12, centipawns: before),
    ],
  ),
  GameReportPosition(
    fen: ChessGame.fromPgn('parity', '1. e4 *').mainline.first.fen,
    lines: [
      GameReportLine(moves: const ['e7e5'], depth: 12, centipawns: after),
    ],
  ),
];
