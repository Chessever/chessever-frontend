import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/move_position_facts.dart';
import 'package:flutter_test/flutter_test.dart';

/// A brutal finish used to be full of "?".
///
/// Both shapes came from the same place: [reportOutcomeAlreadySettled] did not
/// exist, so a *change in the shape of the evaluation* was read as damage even
/// when the result never moved. `_tacticalLossOverride` trips on a mate
/// announcement appearing or disappearing all on its own, and it runs after the
/// loss tiers where `_moreSevere` can only raise a verdict — so the garbage-time
/// softening the tiers already applied was silently undone.
void main() {
  group('a decided game hands out no errors', () {
    test('the winner taking material instead of mating is not a mistake', () {
      // White has a forced mate and plays a slow queen move instead. The mate
      // announcement disappears, the position is still completely winning.
      expect(
        _classify(
          _crushingWhite,
          playedUci: 'g2a2',
          engineBest: 'g2g7',
          before: _mate(7),
          after: _cp(2500),
          beforeWin: 100,
          afterWin: 97.5,
        ),
        isNull,
        reason:
            'a slower road to the same win is a choice, not damage — the mover '
            'never left the clearly-winning band',
      );
    });

    test('the loser being mated sooner is not a mistake', () {
      // Black is dead lost on centipawns; after the move the engine announces a
      // forced mate. No move Black had led anywhere better. Scores arrive
      // normalised to White, so these are positive while the *mover* is losing.
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
        isNull,
        reason:
            'the mover was already clearly losing and still is; there was no '
            'better move to have played',
      );
    });
  });

  group('the guard is band-scoped, not an amnesty for lopsided games', () {
    test('giving up a forced mate for merely better is still punished', () {
      // Mate in 7 traded for +400: that leaves the clearly-winning band, so it
      // is real damage and keeps its label.
      expect(
        _classify(
          _crushingWhite,
          playedUci: 'g2a2',
          engineBest: 'g2g7',
          before: _mate(7),
          after: _cp(400),
          beforeWin: 100,
          afterWin: 81.3,
        ),
        isNotNull,
      );
    });

    test('walking from a playable game into a forced mate is still punished', () {
      // Roughly balanced before, mated after — the outcome changed, so this is
      // exactly what the loss tiers exist for.
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

  group('reportOutcomeAlreadySettled', () {
    test('settled only when the band is decided and unchanged', () {
      expect(
        reportOutcomeAlreadySettled(moverBefore: 100, moverAfter: 97),
        isTrue,
      );
      expect(reportOutcomeAlreadySettled(moverBefore: 3, moverAfter: 0), isTrue);
      // Decided, then not decided any more.
      expect(
        reportOutcomeAlreadySettled(moverBefore: 100, moverAfter: 81),
        isFalse,
      );
      expect(
        reportOutcomeAlreadySettled(moverBefore: 3, moverAfter: 40),
        isFalse,
      );
      // Contested positions are never settled, in either direction.
      expect(
        reportOutcomeAlreadySettled(moverBefore: 55, moverAfter: 50),
        isFalse,
      );
      expect(
        reportOutcomeAlreadySettled(moverBefore: 50, moverAfter: 100),
        isFalse,
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
/// would be `playedIsBest` and never reach the override this covers.
final _hopelessBlack = ChessGame.fromPgn(
  'hopeless-black',
  '[FEN "7k/5ppp/8/8/8/8/8/K5QR b - - 0 1"]\n\n1... g5 *',
);

/// Engine scores reach the report normalised to White, which is why the "loser"
/// case above passes positive numbers for a losing Black mover — the classifier
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
    // A single engine line keeps this on the loss path: the positive labels all
    // require MultiPV alternatives, so this isolates the tiers and the tactical
    // override, which is where the bug lived.
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
