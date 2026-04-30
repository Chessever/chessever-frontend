import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:flutter_test/flutter_test.dart';

ChessMove move(String san, {List<ChessLine>? variations}) {
  return ChessMove(
    num: 1,
    fen: 'fen',
    san: san,
    uci: san,
    turn: ChessColor.white,
    variations: variations,
  );
}

void main() {
  test('deleteVariationAtPointer removes variation branch', () {
    final variation = [move('Nf3')];
    final game = ChessGame(
      gameId: 'g1',
      startingFen: 'fen',
      metadata: const {},
      mainline: [
        move('e4', variations: [variation]),
      ],
    );
    final navigator = ChessGameNavigator(game);

    expect(navigator.state.game.mainline[0].variations?.length, 1);

    navigator.deleteVariationAtPointer([0, 0, 0]);

    expect(navigator.state.game.mainline[0].variations, isNull);
  });

  test('deleteContinuationAfterPointer clears all moves at root', () {
    final game = ChessGame(
      gameId: 'g1',
      startingFen: 'fen',
      metadata: const {},
      mainline: [move('e4'), move('e5')],
    );
    final navigator = ChessGameNavigator(game);

    navigator.goToTail();
    expect(navigator.state.movePointer, equals(<int>[1]));

    navigator.deleteContinuationAfterPointer(const []);

    expect(navigator.state.game.mainline, isEmpty);
    expect(navigator.state.movePointer, isEmpty);
  });

  test(
    'promoteVariationToMainline preserves other variations and mainline continuation',
    () {
      final promotedLine = [
        move(
          'c5',
          variations: [
            [move('d4')],
          ],
        ),
        move('Nc3'),
      ];
      final otherVariation = [move('d4')];

      final game = ChessGame(
        gameId: 'g1',
        startingFen: 'fen',
        metadata: const {},
        mainline: [
          move('e4', variations: [promotedLine, otherVariation]),
          move('e5'),
          move('Nf3'),
        ],
      );
      final navigator = ChessGameNavigator(game);

      navigator.promoteVariationToMainline([0, 0, 0]);

      final updated = navigator.state.game.mainline;
      expect(updated.map((m) => m.san), ['e4', 'c5', 'Nc3']);

      final e4 = updated[0];
      expect(e4.variations, isNotNull);
      // Should have 3 variations:
      // 0: old mainline [e5, Nf3]
      // 1: otherVariation [d4]
      expect(e4.variations!.length, 2);
      expect(e4.variations![0].map((m) => m.san), ['e5', 'Nf3']);
      expect(e4.variations![1].map((m) => m.san), ['d4']);

      final c5 = updated[1];
      expect(c5.variations, isNotNull);
      expect(c5.variations!.first.map((m) => m.san), ['d4']);

      expect(navigator.state.movePointer, equals(<int>[1]));
    },
  );

  test(
    'promoteVariationToMainline promotes nested variations one level and preserves siblings',
    () {
      final deepVariation = [move('d4')];
      final siblingVariation = [move('a6')];
      final firstVariation = [
        move('c5', variations: [deepVariation, siblingVariation]),
        move('Nc6'),
      ];
      final game = ChessGame(
        gameId: 'g1',
        startingFen: 'fen',
        metadata: const {},
        mainline: [
          move('e4', variations: [firstVariation]),
        ],
      );
      final navigator = ChessGameNavigator(game);

      // Promote 'd4' (variation index 0 of move 'c5' in firstVariation)
      navigator.promoteVariationToMainline([0, 0, 0, 0, 0]);

      final e4 = navigator.state.game.mainline.first;
      expect(e4.variations, isNotNull);
      final firstVar = e4.variations!.first;

      // firstVar (the promoted one) should now be e4 -> c5 -> d4
      expect(firstVar.map((m) => m.san), ['c5', 'd4']);

      final c5 = firstVar[0];
      expect(c5.variations, isNotNull);
      // c5 should have 2 variations:
      // 0: old continuation [Nc6]
      // 1: sibling variation [a6]
      expect(c5.variations!.length, 2);
      expect(c5.variations![0].map((m) => m.san), ['Nc6']);
      expect(c5.variations![1].map((m) => m.san), ['a6']);

      expect(navigator.state.movePointer, equals(<int>[0, 0, 1]));
    },
  );
}
