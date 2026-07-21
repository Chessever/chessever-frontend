import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: back-arrow inside a variation must step one half-move (one ply),
/// not a full move. Free `_previousPointer` always recursed after popping the
/// variation head, so leaving a **continuation** (e.g. 11.Be3 after 10...h6)
/// jumped parent → parent−1. Fixed by classifying alternative vs continuation
/// with FEN side-to-move (same as `fullMovePath`).
void main() {
  const pgn = '''
1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 Nc6 6. Bg5 Bd7 7. Qd2 a6
8. O-O-O e6 9. f3 Nxd4 10. Qxd4 h6 11. Bd2 Qc7 12. Kb1 *
''';

  String fenKey(String fen) => fen.split(' ').take(4).join(' ');

  test(
    'mainline goToPreviousMove steps one half-move: [n] → [n-1]',
    () {
      final nav = ChessGameNavigator(ChessGame.fromPgn('g1', pgn));
      // Mainline: e4 c5 Nf3 d6 … — index 3 is 2...d6
      nav.goToMovePointerUnchecked(<Number>[3]);
      expect(nav.state.currentMove?.san, 'd6');
      final fenBefore = nav.state.currentFen;

      nav.goToPreviousMove();

      expect(nav.state.movePointer, <Number>[2]);
      expect(nav.state.currentMove?.san, 'Nf3');
      // One ply earlier must differ from the position we left.
      expect(fenKey(nav.state.currentFen), isNot(fenKey(fenBefore)));
    },
  );

  test(
    'mid-variation goToPreviousMove decrements last index by one',
    () {
      final nav = ChessGameNavigator(ChessGame.fromPgn('g1', pgn));
      // Sit on 10...h6, play continuation 11.Be3 then extend one more ply.
      nav.goToMovePointerUnchecked(<Number>[19]);
      expect(nav.state.currentMove?.san, 'h6');
      nav.makeOrGoToMove('g5e3'); // Be3
      final afterBe3Pointer = List<Number>.of(nav.state.movePointer);
      expect(afterBe3Pointer.last, 0);
      // Append a black reply in the variation (e.g. ...Qc7 is mainline; use a6
      // already played — play ...Be7 as a legal black move if needed).
      // From Be3 position black to move; ...Qc7 would be c7c7 illegal. Use g7g5.
      nav.makeOrGoToMove('g7g5');
      expect(nav.state.movePointer.last, 1);

      final midFen = nav.state.currentFen;
      nav.goToPreviousMove();

      expect(nav.state.movePointer, afterBe3Pointer);
      expect(nav.state.currentMove?.san, 'Be3');
      expect(fenKey(nav.state.currentFen), isNot(fenKey(midFen)));
    },
  );

  test(
    'continuation variation head: previous is parent branch point (not parent−1)',
    () {
      final nav = ChessGameNavigator(ChessGame.fromPgn('g1', pgn));
      // 10...h6 then sideline 11.Be3 (continuation off black's h6).
      nav.goToMovePointerUnchecked(<Number>[19]);
      final parentPointer = List<Number>.of(nav.state.movePointer);
      final parentFen = nav.state.currentFen;
      expect(nav.state.currentMove?.san, 'h6');

      nav.makeOrGoToMove('g5e3');
      expect(nav.state.movePointer.last, 0);
      expect(nav.state.movePointer.length, greaterThanOrEqualTo(3));
      expect(nav.state.currentMove?.san, 'Be3');
      final variationFen = nav.state.currentFen;

      nav.goToPreviousMove();

      // Must land on h6 (parent), NOT on Qxd4 (parent−1).
      expect(nav.state.movePointer, parentPointer);
      expect(nav.state.currentMove?.san, 'h6');
      expect(fenKey(nav.state.currentFen), fenKey(parentFen));
      expect(fenKey(nav.state.currentFen), isNot(fenKey(variationFen)));
    },
  );

  test(
    'alternative variation head: previous is before parent (start or parent−1)',
    () {
      // Short game so we can branch 1.d4 as alternative to 1.e4.
      const shortPgn = '''
1. e4 e5 2. Nf3 *
''';
      final nav = ChessGameNavigator(ChessGame.fromPgn('g2', shortPgn));
      // At start, play 1.d4 — stored as variation of the first mainline move.
      nav.goToHead();
      nav.makeOrGoToMove('d2d4');
      expect(nav.state.movePointer.length, greaterThanOrEqualTo(3));
      expect(nav.state.movePointer.last, 0);
      expect(nav.state.currentMove?.san, 'd4');
      final d4Fen = nav.state.currentFen;

      nav.goToPreviousMove();

      // Alternative replaces e4: one half-move back is the starting position.
      expect(nav.state.movePointer, isEmpty);
      expect(nav.state.currentMove, isNull);
      expect(fenKey(nav.state.currentFen), fenKey(nav.state.game.startingFen));
      expect(fenKey(nav.state.currentFen), isNot(fenKey(d4Fen)));
    },
  );

  test(
    'continuation after a mainline ply: previous lands on that ply (not earlier)',
    () {
      const shortPgn = '''
1. e4 e5 2. Nf3 *
''';
      final nav = ChessGameNavigator(ChessGame.fromPgn('g3', shortPgn));
      // Sit on 1.e4, play 1...c5 (continuation branch off e4, not same-side alt).
      nav.goToMovePointerUnchecked(<Number>[0]);
      expect(nav.state.currentMove?.san, 'e4');
      final parentFen = nav.state.currentFen;

      nav.makeOrGoToMove('c7c5');
      expect(nav.state.movePointer.length, greaterThanOrEqualTo(3));
      expect(nav.state.currentMove?.san, 'c5');

      nav.goToPreviousMove();

      // Half-move back from ...c5 is 1.e4 — must not skip to the start.
      expect(nav.state.movePointer, <Number>[0]);
      expect(nav.state.currentMove?.san, 'e4');
      expect(fenKey(nav.state.currentFen), fenKey(parentFen));
    },
  );
}
