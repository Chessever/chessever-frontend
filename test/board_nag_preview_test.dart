import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PV preview does not reuse the base move NAG on previewed positions',
    () {
      final game = ChessGame.fromPgn('nag-preview', r'''
[Event "NAG preview"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 $10 *
''');

      final baseMove = resolveBoardMoveForAnnotations(
        game: game,
        pointer: const [3],
        isPvPreviewActive: false,
      );
      final previewMove = resolveBoardMoveForAnnotations(
        game: game,
        pointer: const [3],
        isPvPreviewActive: true,
      );

      expect(baseMove?.san, 'Nc6');
      expect(baseMove?.nags, contains(10));
      expect(
        previewMove,
        isNull,
        reason:
            'A PV position is not the annotated base move, so its board badge '
            'must not inherit that move\'s NAG.',
      );
    },
  );
}
