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

  group('board handoff gate', () {
    test('a running board search below the handoff depth blocks the report', () {
      final stockfish = StockfishSingleton();
      stockfish.debugSetRunningBoardSearchForTest(
        fen: fen,
        reachedDepth: StockfishSingleton.boardHandoffDepth - 1,
      );

      expect(stockfish.hasActiveBoardWork, isTrue);
      expect(stockfish.hasBlockingBoardWork, isTrue);
    });

    test('reaching the handoff depth lets the report interleave', () {
      final stockfish = StockfishSingleton();
      stockfish.debugSetRunningBoardSearchForTest(
        fen: fen,
        reachedDepth: StockfishSingleton.boardHandoffDepth,
      );

      // The board still owns the engine — it just no longer blocks.
      expect(stockfish.hasActiveBoardWork, isTrue);
      expect(stockfish.hasBlockingBoardWork, isFalse);
    });

    test('a queued board search blocks whatever depth the running one reached', () {
      final stockfish = StockfishSingleton();
      stockfish.debugSetRunningBoardSearchForTest(
        fen: fen,
        reachedDepth: StockfishSingleton.boardHandoffDepth + 12,
      );
      stockfish.debugEnqueueQueuedEvaluationForTest(
        fen: fen,
        isCurrentPosition: true,
      );

      expect(stockfish.hasBlockingBoardWork, isTrue);
    });

    test('queued background work never blocks the board', () {
      final stockfish = StockfishSingleton();
      stockfish.debugEnqueueQueuedEvaluationForTest(fen: fen);

      expect(stockfish.hasActiveBoardWork, isFalse);
      expect(stockfish.hasBlockingBoardWork, isFalse);
    });

    test('waitForBoardIdle returns once the board crosses the handoff depth', () async {
      final stockfish = StockfishSingleton();
      stockfish.debugSetRunningBoardSearchForTest(fen: fen, reachedDepth: 6);

      var released = false;
      final wait = stockfish.waitForBoardIdle().then((_) => released = true);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        released,
        isFalse,
        reason: 'report must wait while the board is still shallow',
      );

      stockfish.debugAdvanceBoardDepthForTest(
        StockfishSingleton.boardHandoffDepth,
      );
      await wait.timeout(const Duration(seconds: 2));
      expect(released, isTrue);
    });
  });

  group('bestmove detection', () {
    test('matches with and without leading whitespace', () {
      expect(
        StockfishSingleton.debugIsBestmoveLineForTest('bestmove e2e4 ponder e7e5'),
        isTrue,
      );
      expect(
        StockfishSingleton.debugIsBestmoveLineForTest('  \tbestmove (none)'),
        isTrue,
      );
      expect(
        StockfishSingleton.debugIsBestmoveLineForTest('bestmove a2a3\r'),
        isTrue,
      );
    });

    test('does not match info or readyok traffic', () {
      expect(
        StockfishSingleton.debugIsBestmoveLineForTest(
          'info depth 22 multipv 1 score cp 31 pv e2e4 e7e5',
        ),
        isFalse,
      );
      expect(StockfishSingleton.debugIsBestmoveLineForTest('readyok'), isFalse);
      expect(StockfishSingleton.debugIsBestmoveLineForTest(''), isFalse);
    });
  });
}
