import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/game_review/server_game_report.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'wire diagnostics survive without reclassifying authoritative server labels',
    () {
      final game = ChessGame.fromPgn('wire', '1. e4 *');
      final payload = <String, dynamic>{
        'fingerprint': gameReportFingerprint(game),
        'positions': [
          for (final fen in gameReportFens(game))
            {
              'fen': fen,
              'evaluation': {
                'moves': ['e2e4'],
                'depth': 18,
                'centipawns': 0,
              },
              'search': {
                'engineId': 'Stockfish 18',
                'searchId': fen,
                'complete': true,
              },
              'uncertainty': 'native_confirmation_report_budget',
            },
        ],
        'moves': [
          {
            'ply': 1,
            'san': 'e4',
            'uci': 'e2e4',
            'isWhite': true,
            'classification': 'bookMove',
            'evaluation': {'moves': [], 'depth': 18, 'centipawns': 0},
          },
        ],
        'accuracy': {'white': 100, 'black': 100},
      };
      final report = gameAnalysisReportFromServerJson(payload, game: game);
      expect(
        report.positions.first.uncertainty,
        'native_confirmation_report_budget',
      );
      expect(report.positions.first.search?.engineId, 'Stockfish 18');
      expect(
        report.moves.first.classification,
        GameMoveClassification.bookMove,
      );
    },
  );

  test('cache round trip preserves native search identity and uncertainty', () {
    const p = GameReportPosition(
      fen: '7k/8/8/8/8/8/8/K7 w - - 0 1',
      lines: [
        GameReportLine(moves: ['a1b1'], depth: 18, centipawns: 0),
      ],
      search: GameReportSearchEvidence(
        engineId: 'native-test',
        searchId: 'search-1',
        complete: true,
      ),
      uncertainty: 'native_confirmation_timeout',
    );
    final report = GameAnalysisReport(
      fingerprint: 'native',
      positions: const [p],
      moves: const [],
      whiteAccuracy: 100,
      blackAccuracy: 100,
      generatedAt: DateTime.utc(2026),
    );
    final decoded = gameAnalysisReportFromJson(
      gameAnalysisReportToJson(report),
    )!;
    expect(decoded.positions.single.search?.engineId, 'native-test');
    expect(decoded.positions.single.search?.searchId, 'search-1');
    expect(decoded.positions.single.search?.complete, true);
    expect(decoded.positions.single.uncertainty, 'native_confirmation_timeout');
  });
}
