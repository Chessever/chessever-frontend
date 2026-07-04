import 'package:chessever2/screens/chessboard/utils/engine_arrow_visibility.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldSuppressEngineArrowsForPosition', () {
    test('returns true for final checkmate positions', () {
      const mateFen =
          'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3';
      final matePosition = Chess.fromSetup(Setup.parseFen(mateFen));

      expect(matePosition.isCheckmate, isTrue);
      expect(shouldSuppressEngineArrowsForPosition(matePosition), isTrue);
    });

    test('returns false for playable checked positions', () {
      const checkedFen =
          'rnb1kbnr/pppp1ppp/8/4p3/7q/5P2/PPPPP1PP/RNBQKBNR w KQkq - 1 3';
      final checkedPosition = Chess.fromSetup(Setup.parseFen(checkedFen));

      expect(checkedPosition.isCheck, isTrue);
      expect(checkedPosition.isCheckmate, isFalse);
      expect(shouldSuppressEngineArrowsForPosition(checkedPosition), isFalse);
    });
  });
}
