import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quick share row offers FEN while PGN stays outside the row', () {
    expect(shareGameQuickActionLabels, [
      'Share Image',
      'Share GIF',
      'Copy FEN',
    ]);
    expect(shareGameQuickActionLabels, isNot(contains('Copy PGN')));
  });

  test(
    'copies the exact current position FEN without surrounding whitespace',
    () {
      const fen = '8/8/8/3k4/8/4K3/8/8 w - - 12 48';

      expect(sharePositionFenForClipboard('  $fen\n'), fen);
    },
  );
}
