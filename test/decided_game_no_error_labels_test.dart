import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// A brutal finish used to be full of "?".
///
/// The cure is no longer a rule of our own. `?!`, `?` and `??` now come from the
/// lichess port, which measures damage in winning chances — and those compress so
/// hard near the edges that a decided game runs out of chances to lose all by
/// itself. A player already lost by nine pawns cannot shed another 0.1, and a
/// mate held in either direction is excluded by name rather than by band.
///
/// ChessEver deliberately overlays one product rule on the lichess judgment:
/// when the mover is decisively winning before and after the move, conversion
/// noise receives no negative symbol. For human review, +7 and +4 are both won.
void main() {
  group('a decided game hands out no errors', () {
    test('mating slower than necessary is not an error', () {
      // White has mate in 7 and plays a move that still mates, in 11. This is
      // lichess's `MateDelayed`, the one sequence it names and then judges
      // nothing for.
      expect(
        _classify(
          _crushingWhite,
          playedUci: 'g2a2',
          engineBest: 'g2g7',
          before: _mate(7),
          after: _mate(11),
          beforeWin: 100,
          afterWin: 100,
        ),
        isNull,
      );
    });

    test('being mated sooner is not an error', () {
      // Black is mated in 11 and plays into mate in 7. Scores arrive normalised
      // to White, so these are positive while the *mover* is the one losing.
      expect(
        _classify(
          _hopelessBlack,
          playedUci: 'g7g5',
          engineBest: 'h7h6',
          before: _mate(11),
          after: _mate(7),
          beforeWin: 100,
          afterWin: 100,
        ),
        isNull,
      );
    });

    test('drifting deeper into a lost game is not an error', () {
      // -15.00 to -30.00 for the mover: an enormous centipawn slide worth 0.008
      // winning chances, because the game was already gone.
      expect(
        _classify(
          _hopelessBlack,
          playedUci: 'g7g5',
          engineBest: 'h7h6',
          before: _cp(1500),
          after: _cp(3000),
          beforeWin: 97.5,
          afterWin: 97.5,
        ),
        isNull,
      );
    });

    test('easing off while still crushing is not an error', () {
      expect(
        _classify(
          _crushingWhite,
          playedUci: 'g2a2',
          engineBest: 'g2g7',
          before: _cp(1500),
          after: _cp(900),
          beforeWin: 97.5,
          afterWin: 96.5,
        ),
        isNull,
      );
    });
  });

  group('a decisive win retained receives no error', () {
    test('losing forced mate but retaining +4 receives no symbol', () {
      expect(
        _classify(
          _crushingWhite,
          playedUci: 'g2a2',
          engineBest: 'g2g7',
          before: _mate(7),
          after: _cp(400),
          beforeWin: 100,
          afterWin: gameReportWinPercentage(_cp(400)),
        ),
        isNull,
      );
    });

    test('easing from +7 to +3.3 receives no symbol', () {
      expect(
        _classify(
          _crushingWhite,
          playedUci: 'g2a2',
          engineBest: 'g2g7',
          before: _cp(700),
          after: _cp(330),
          beforeWin: gameReportWinPercentage(_cp(700)),
          afterWin: gameReportWinPercentage(_cp(330)),
        ),
        isNull,
      );
    });

    test('the same decisive-win rule is mover-relative for Black', () {
      expect(
        _classify(
          _hopelessBlack,
          playedUci: 'g7g5',
          engineBest: 'h7h6',
          before: _cp(-700),
          after: _cp(-330),
          beforeWin: gameReportWinPercentage(_cp(-700)),
          afterWin: gameReportWinPercentage(_cp(-330)),
        ),
        isNull,
      );
    });
  });

  group('a lost position can still receive lichess-softened errors', () {
    test('walking into mate from a lost game is only a Mistake', () {
      // `MateCreated` from -9.00 for the mover: worse than -7.00, so it is a
      // Mistake rather than a Blunder.
      expect(
        _classify(
          _hopelessBlack,
          playedUci: 'g7g5',
          engineBest: 'h7h6',
          before: _cp(900),
          after: _mate(6),
          beforeWin: 96.5,
          afterWin: 100,
        ),
        GameMoveClassification.mistake,
      );
    });

    test('walking into mate from a hopeless game is only an Inaccuracy', () {
      // Past -9.99 there is nothing left to lose, so the mark is the softest one.
      expect(
        _classify(
          _hopelessBlack,
          playedUci: 'g7g5',
          engineBest: 'h7h6',
          before: _cp(1100),
          after: _mate(6),
          beforeWin: 97.5,
          afterWin: 100,
        ),
        GameMoveClassification.inaccuracy,
      );
    });
  });

  group('a changed result is punished in full', () {
    test('giving up a forced mate below the decisive floor is a Blunder', () {
      expect(
        _classify(
          _crushingWhite,
          playedUci: 'g2a2',
          engineBest: 'g2g7',
          before: _mate(7),
          after: _cp(200),
          beforeWin: 100,
          afterWin: gameReportWinPercentage(_cp(200)),
        ),
        GameMoveClassification.blunder,
      );
    });

    test('walking from a playable game into a forced mate is a Blunder', () {
      expect(
        _classify(
          _crushingWhite,
          playedUci: 'g2a2',
          engineBest: 'g2g7',
          before: _cp(50),
          after: _mate(-5),
          beforeWin: 54.6,
          afterWin: 0,
        ),
        GameMoveClassification.blunder,
      );
    });
  });
}

/// White queen and king against a bare king: White to move, mate is forced.
final _crushingWhite = ChessGame.fromPgn(
  'crushing-white',
  '[FEN "7k/8/8/8/8/8/6Q1/6K1 w - - 0 1"]\n\n1. Qa2 *',
);

/// Black to move against queen and rook, with pawn moves still available so the
/// played move can differ from the engine's — a lone king with one legal move
/// would be the engine's own choice and would never be judged at all.
final _hopelessBlack = ChessGame.fromPgn(
  'hopeless-black',
  '[FEN "7k/5ppp/8/8/8/8/8/K5QR b - - 0 1"]\n\n1... g5 *',
);

/// Engine scores reach the report normalised to White, which is why the "loser"
/// cases above pass positive numbers for a losing Black mover — the judgment
/// applies the mover's sign itself.
GameReportLine _cp(int centipawns, {List<String> moves = const ['a2a3']}) =>
    GameReportLine(moves: moves, depth: 16, centipawns: centipawns);

GameReportLine _mate(int mate, {List<String> moves = const ['a2a3']}) =>
    GameReportLine(moves: moves, depth: 16, mate: mate);

GameMoveClassification? _classify(
  ChessGame game, {
  required String playedUci,
  required String engineBest,
  required GameReportLine before,
  required GameReportLine after,
  required double beforeWin,
  required double afterWin,
}) {
  expect(
    game.mainline.single.uci,
    playedUci,
    reason: 'fixture PGN must play the move under test',
  );
  return classifyGameReportMove(
    index: 0,
    game: game,
    // A single engine line keeps this on the judgment path: every positive label
    // needs a MultiPV alternative to beat.
    positions: [
      GameReportPosition(
        fen: game.startingFen,
        lines: [
          GameReportLine(
            moves: [engineBest],
            depth: before.depth,
            centipawns: before.centipawns,
            mate: before.mate,
          ),
        ],
      ),
      GameReportPosition(fen: game.mainline.single.fen, lines: [after]),
    ],
    winPercentages: [beforeWin, afterWin],
  );
}
