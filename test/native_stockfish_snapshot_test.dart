import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'completed iteration does not mix depth18 PV1 with depth17 alternatives',
    () {
      final batch = StockfishReportIteration(3);
      for (var rank = 1; rank <= 3; rank++) {
        batch.add(
          'info depth 17 multipv $rank score cp ${40 - rank} pv ${['e2e4', 'd2d4', 'c2c4'][rank - 1]}',
        );
      }
      expect(batch.depth, 17);
      batch.add('info depth 18 multipv 1 score cp 90 pv e2e4');
      expect(batch.depth, 17);
      expect(batch.pvs.first.cp, 39);
      batch.add('info depth 18 multipv 2 score cp 30 pv d2d4');
      batch.add('info depth 18 multipv 3 score cp 20 pv c2c4');
      expect(batch.depth, 18);
      expect(batch.pvs.map((p) => p.cp), [90, 30, 20]);
    },
  );
  test(
    'bound-only, unscored, partial and depthless traffic cannot claim completion',
    () {
      final batch = StockfishReportIteration(2);
      batch.add('info depth 18 multipv 1 score cp 10 lowerbound pv e2e4');
      batch.add('info depth 18 multipv 2 score cp 5 pv d2d4');
      batch.add('info multipv 1 score cp 20 pv e2e4');
      expect(batch.depth, 0);
      expect(batch.pvs, isEmpty);
    },
  );
  test(
    'mate sign and actual completed depth are preserved without fallback',
    () {
      final batch = StockfishReportIteration(1);
      batch.add('info depth 4 score mate -3 pv e2e4');
      expect(batch.depth, 4);
      expect(batch.pvs.single.mate, -3);
      expect(batch.pvs.single.isMate, true);
    },
  );
  test('confirmation go enforces time depth and node bounds together', () {
    expect(
      stockfishGoCommand(
        depth: 18,
        searchDuration: const Duration(seconds: 12),
        maxDepth: 18,
        maxNodes: 6000000,
      ),
      'go movetime 12000 depth 18 nodes 6000000',
    );
    expect(
      stockfishGoCommand(
        depth: 12,
        searchDuration: const Duration(milliseconds: 500),
        maxDepth: 12,
      ),
      'go movetime 500 depth 12',
    );
    expect(stockfishGoCommand(depth: 15), 'go depth 15');
  });
}
