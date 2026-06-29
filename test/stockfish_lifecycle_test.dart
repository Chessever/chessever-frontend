import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

  tearDown(() {
    StockfishSingleton().dispose();
  });

  test(
    'disposeAsync completes queued evaluation futures as cancelled',
    () async {
      final stockfish = StockfishSingleton();
      final queued = stockfish.debugEnqueueQueuedEvaluationForTest(
        fen: fen,
        multiPV: 2,
      );

      await stockfish.disposeAsync();

      final result = await queued.timeout(const Duration(milliseconds: 100));
      expect(result.fen, fen);
      expect(result.isCancelled, isTrue);
      expect(result.requestedMultiPv, 2);
    },
  );
}
