import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';

void main() {
  test(
    'a legal mating PV cannot carry the opposite winner or a scalar score',
    () {
      const fen = '7k/8/5KQ1/8/8/8/8/8 w - - 0 1';
      GameReportPosition p({int? cp, int? mate}) => GameReportPosition(
        fen: fen,
        lines: [
          GameReportLine(
            moves: ['g6g7'],
            depth: 18,
            centipawns: cp,
            mate: mate,
          ),
        ],
        search: const GameReportSearchEvidence(
          engineId: 'SF18',
          searchId: 'capture',
          complete: true,
        ),
      );
      expect(
        gameReportSnapshotIsCoherent(
          p(mate: 1),
          minDepth: 18,
          requireNative: true,
        ),
        isTrue,
      );
      expect(
        gameReportSnapshotIsCoherent(
          p(mate: -1),
          minDepth: 18,
          requireNative: true,
        ),
        isFalse,
      );
      expect(
        gameReportSnapshotIsCoherent(
          p(cp: 500),
          minDepth: 18,
          requireNative: true,
        ),
        isFalse,
      );
    },
  );
}
