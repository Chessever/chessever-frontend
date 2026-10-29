import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/live_game_position_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveFreshestGameFen', () {
    const afterE4 =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
    const afterE4E5 =
        'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
    const pgnAfterE4 = '''
[Event "Test"]

1. e4 *
''';
    const pgnAfterE4E5 = '''
[Event "Test"]

1. e4 e5 *
''';

    test('uses PGN when PGN and last_move prove FEN is one ply stale', () {
      final fen = resolveFreshestGameFen(
        fen: afterE4,
        pgn: pgnAfterE4E5,
        lastMove: 'e7e5',
      );

      expect(fen, afterE4E5);
    });

    test('keeps FEN when PGN is behind the advertised last move', () {
      final fen = resolveFreshestGameFen(
        fen: afterE4E5,
        pgn: pgnAfterE4,
        lastMove: 'e7e5',
      );

      expect(fen, afterE4E5);
    });

    test('uses PGN when local FEN is missing', () {
      final fen = resolveFreshestGameFen(
        fen: null,
        pgn: pgnAfterE4E5,
        lastMove: 'e7e5',
      );

      expect(fen, afterE4E5);
    });

    test(
      'uses PGN when ply count shows it is newer even without last_move',
      () {
        final fen = resolveFreshestGameFen(
          fen: afterE4,
          pgn: pgnAfterE4E5,
          lastMove: null,
        );

        expect(fen, afterE4E5);
      },
    );
  });

  group('recorded final evaluation', () {
    // 1. e4 e5 2. Nf3 Nc6, the way a saved report writes its moves.
    const afterNc6 =
        'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';
    String report(String lastEval) =>
        '''
[Event "Test"]

1. e4 { [%eval 0.30] [%clk 0:02:23] } 1... e5 { [%eval 0.25] } 2. Nf3 \$1 { [%eval 0.31] } 2... Nc6 { $lastEval [%clk 0:02:09] } 1-0
''';

    test('the snapshot keeps the eval written after the last move', () {
      final end = resolveFinalPositionFromPgn(report('[%eval -1.36,24]'))!;

      expect(end.fen, afterNc6);
      expect(end.finalEval?.pawns, -1.36);
      expect(end.finalEval?.depth, 24);
    });

    test('a last move without an eval records none, whatever came before', () {
      expect(resolveFinalPositionFromPgn(report(''))!.finalEval, isNull);
    });

    test('recordedEvalAt reads pawns and mates from White\'s side', () {
      final pawns = recordedEvalAt(
        pgn: report('[%eval 1.36]'),
        fen: afterNc6,
      )!.pvs.single;
      expect(
        (pawns.cp, pawns.isMate, pawns.whitePerspective),
        (136, false, true),
      );

      final mate = recordedEvalAt(
        pgn: report('[%eval #-3]'),
        fen: afterNc6,
      )!.pvs.single;
      expect((mate.cp, mate.isMate, mate.mate), (-100000, true, -3));
    });

    test('recordedEvalAt answers only for the position the PGN ends on', () {
      // The same position written by another source (clocks, en passant).
      expect(
        recordedEvalAt(
          pgn: report('[%eval 1.36]'),
          fen:
              'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 1',
        ),
        isNotNull,
      );
      // One ply earlier: the eval is not about this board.
      expect(
        recordedEvalAt(
          pgn: report('[%eval 1.36]'),
          fen: 'r1bqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
        ),
        isNull,
      );
      expect(recordedEvalAt(pgn: report('[%eval #0]'), fen: afterNc6), isNull);
      expect(recordedEvalAt(pgn: null, fen: afterNc6), isNull);
    });
  });
}
