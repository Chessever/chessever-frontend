import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/notation/next_move_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextMoveOptionsAt', () {
    // 1. e4 e5 (1... c5 2. Nf3) 2. Nf3 (2. Bc4 Bc5) Nc6
    // PGN convention: variations of move X are alternatives to X's
    // continuation, so e4 carries the c5 line and e5 carries the Bc4 line.
    final game = ChessGame.fromPgn(
      'test',
      '1. e4 e5 (1... c5 2. Nf3) 2. Nf3 (2. Bc4 Bc5) Nc6 *',
    );

    test('single continuation yields one option', () {
      final options = nextMoveOptionsAt(game, const []);
      expect(options.length, 1);
      expect(options.first.move.san, 'e4');
      expect(options.first.isLineContinuation, isTrue);
      expect(options.first.pointer, [0]);
    });

    test('fork after e4 offers continuation first, then variation head', () {
      final options = nextMoveOptionsAt(game, const [0]);
      expect(options.map((o) => o.move.san).toList(), ['e5', 'c5']);
      expect(options[0].isLineContinuation, isTrue);
      expect(options[0].pointer, [1]);
      expect(options[1].isLineContinuation, isFalse);
      expect(options[1].pointer, [0, 0, 0]);
    });

    test('fork after e5 resolves variation pointer on the previous move', () {
      final options = nextMoveOptionsAt(game, const [1]);
      expect(options.map((o) => o.move.san).toList(), ['Nf3', 'Bc4']);
      expect(options[1].pointer, [1, 0, 0]);
    });

    test('inside a variation the same rules apply', () {
      // After 1... c5 (pointer [0, 0, 0]) the only next move is 2. Nf3.
      final options = nextMoveOptionsAt(game, const [0, 0, 0]);
      expect(options.length, 1);
      expect(options.first.move.san, 'Nf3');
      expect(options.first.pointer, [0, 0, 1]);
    });

    test('end of a line yields no options', () {
      final options = nextMoveOptionsAt(game, const [1, 0, 1]);
      expect(options, isEmpty);
    });

    test(
      'same-mover variation of the next move surfaces as an option here',
      () {
        // Navigator-created alternatives to move N are attached to move N
        // itself (same mover), e.g. an alternative first move. They are
        // playable from the position BEFORE that move.
        final e4 = game.mainline.first;
        final d4 = ChessMove(
          num: 1,
          fen: 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1',
          san: 'd4',
          uci: 'd2d4',
          turn: ChessColor.black,
        );
        final patched = game.copyWith(
          mainline: [
            e4.copyWith(
              variations: [
                ...e4.variations ?? const <ChessLine>[],
                [d4],
              ],
              overrideVariations: true,
            ),
            ...game.mainline.sublist(1),
          ],
        );

        final atStart = nextMoveOptionsAt(patched, const []);
        expect(atStart.map((o) => o.move.san).toList(), ['e4', 'd4']);
        expect(atStart[1].pointer, [0, 1, 0]);

        // And it must NOT leak into the options after e4.
        final afterE4 = nextMoveOptionsAt(patched, const [0]);
        expect(afterE4.map((o) => o.move.san).toList(), ['e5', 'c5']);
      },
    );

    test('duplicate ucis are deduped', () {
      final e4 = game.mainline.first;
      final duplicateE5 = game.mainline[1];
      final patched = game.copyWith(
        mainline: [
          e4.copyWith(
            variations: [
              ...e4.variations ?? const <ChessLine>[],
              [duplicateE5],
            ],
            overrideVariations: true,
          ),
          ...game.mainline.sublist(1),
        ],
      );
      final options = nextMoveOptionsAt(patched, const [0]);
      expect(options.map((o) => o.move.san).toList(), ['e5', 'c5']);
    });

    test('invalid pointer yields no options', () {
      expect(nextMoveOptionsAt(game, const [9]), isEmpty);
      expect(nextMoveOptionsAt(game, const [0, 5, 0]), isEmpty);
    });
  });

  group('balanceIntoRows', () {
    test('fits a single row when under the cap', () {
      expect(balanceIntoRows([1, 2, 3], 4), [
        [1, 2, 3],
      ]);
    });

    test('splits evenly instead of leaving a sparse last row', () {
      expect(balanceIntoRows([1, 2, 3, 4, 5], 4), [
        [1, 2, 3],
        [4, 5],
      ]);
      expect(balanceIntoRows([1, 2, 3, 4, 5, 6, 7, 8], 4), [
        [1, 2, 3, 4],
        [5, 6, 7, 8],
      ]);
      expect(balanceIntoRows(List.generate(9, (i) => i), 4), [
        [0, 1, 2],
        [3, 4, 5],
        [6, 7, 8],
      ]);
    });

    test('handles empty input', () {
      expect(balanceIntoRows(<int>[], 4), isEmpty);
    });
  });
}
