import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_move_line.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: the board swipe explorer went blank ("No move statistics for
/// this position") whenever the user was inside an analysis *variation*, e.g.
/// playing 11.Be3 off the Liu–Acs mainline (which continues 11.Bd2).
///
/// Root cause: `pathFromPointer` / `fullMovePath` classified replace-vs-continue
/// with `ChessMove.turn`, but that field is inconsistent — PGN-parsed moves
/// store the *mover*, navigator-created moves store *who is next*. A
/// continuation (Be3 after h6) compared equal and dropped the parent move,
/// yielding a line that no longer replayed to the board FEN → empty aggregates.
/// Fixed by classifying on FEN side-to-move.
void main() {
  const pgn = '''
1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 Nc6 6. Bg5 Bd7 7. Qd2 a6
8. O-O-O e6 9. f3 Nxd4 10. Qxd4 h6 11. Bd2 Qc7 12. Kb1 *
''';

  test('a variation branch ships the full line that replays to the board', () {
    final nav = ChessGameNavigator(ChessGame.fromPgn('g1', pgn));
    // Sit on 10...h6 (ply 20, index 19), then play the sideline 11.Be3 (g5e3)
    // instead of the mainline 11.Bd2 — a continuation branch off h6.
    nav.goToMovePointerUnchecked(<Number>[19]);
    expect(nav.state.currentMove?.san, 'h6');
    nav.makeOrGoToMove('g5e3');

    final navState = nav.state;
    final targetFen = navState.currentFen;

    // Mirror _syncAnalysisFromNavigator into an AnalysisBoardState.
    final analysis = AnalysisBoardState(
      game: navState.game,
      movePointer: navState.movePointer,
      position: Position.setupPosition(Rule.chess, Setup.parseFen(targetFen)),
      startingPosition: Chess.initial,
      allMoves:
          navState.fullMovePath
              .map((m) => Move.parse(m.uci))
              .whereType<Move>()
              .toList(),
    );

    final line = resolveExplorerMoveLine(analysis);

    expect(line.length, 21, reason: '20 mainline plies + Be3, h6 not dropped');
    expect(line[19], 'h7h6', reason: 'the parent move must survive');
    expect(line.last, 'g5e3');

    // The whole point: replaying the line from the start must land on the
    // board FEN, so the aggregates query is answerable instead of empty.
    Position pos = Chess.initial;
    for (final uci in line) {
      final mv = NormalMove.fromUci(uci);
      expect(pos.isLegal(mv), true, reason: 'every ply must be legal: $uci');
      pos = pos.play(mv);
    }
    String key(String fen) => fen.split(' ').take(4).join(' ');
    expect(key(pos.fen), key(targetFen), reason: 'line must reach the board');
  });
}
