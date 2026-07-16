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

  test(
    'PV preview does not resolve the pointer that keys user-applied NAGs',
    () {
      final basePointer = resolveBoardMovePointerForAnnotations(
        pointer: const [3],
        isPvPreviewActive: false,
      );
      final previewPointer = resolveBoardMovePointerForAnnotations(
        pointer: const [3],
        isPvPreviewActive: true,
      );

      expect(basePointer, const [3]);
      expect(
        previewPointer,
        isNull,
        reason:
            'User NAGs are stored keyed by the encoded move pointer, which '
            'stays anchored to the played move during a PV preview — resolving '
            'it would pin the base move\'s annotation badge onto every '
            'previewed engine position.',
      );
    },
  );
}
