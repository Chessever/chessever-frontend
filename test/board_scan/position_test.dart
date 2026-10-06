import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/board_scan/board_scan_position.dart';
import 'package:chessever2/board_scan/board_scan_image.dart';

void main() {
  test('FEN keeps sparse ranks and colour, with no invented move history', () {
    final squares = {for (final square in boardScanSquares) square: '-'};
    squares['a8'] = 'bR';
    squares['h1'] = 'wK';
    squares['d4'] = 'wN';
    expect(
      BoardScanPosition(squares: squares).fen(blackToMove: true),
      'r7/8/8/8/3N4/8/8/7K b - - 0 1',
    );
    expect(
      () => BoardScanPosition(squares: {...squares}..remove('e4')),
      throwsFormatException,
    );
  });
  test(
    'perspective projection matches all corners and rejects crossed handles',
    () {
      final corners = [
        const Offset(.2, .1),
        const Offset(.8, .2),
        const Offset(.95, .9),
        const Offset(.05, .85),
      ];
      final h = boardScanHomography(corners);
      for (final pair in [
        (Offset.zero, corners[0]),
        (const Offset(1, 0), corners[1]),
        (const Offset(1, 1), corners[2]),
        (const Offset(0, 1), corners[3]),
      ]) {
        final p = boardScanProject(h, pair.$1.dx, pair.$1.dy);
        expect(p.dx, closeTo(pair.$2.dx, 1e-9));
        expect(p.dy, closeTo(pair.$2.dy, 1e-9));
      }
      expect(
        validBoardScanCorners([corners[0], corners[2], corners[1], corners[3]]),
        false,
      );
    },
  );
}
