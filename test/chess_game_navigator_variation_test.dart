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

  test('promoteVariationToMainline replaces parent continuation', () {
    final promotedLine = [
      move(
        'c5',
        variations: [
          [move('d4')],
        ],
      ),
      move('Nc3'),
    ];
    final game = ChessGame(
      gameId: 'g1',
      startingFen: 'fen',
      metadata: const {},
      mainline: [
        move('e4', variations: [promotedLine]),
        move('e5'),
        move('Nf3'),
      ],
    );
    final navigator = ChessGameNavigator(game);

    navigator.promoteVariationToMainline([0, 0, 0]);

    final updated = navigator.state.game.mainline;
    expect(updated.map((m) => m.san), ['e4', 'c5', 'Nc3']);
    for (final move in updated) {
      expect(move.variations, isNull);
    }
    expect(navigator.state.movePointer, equals(<int>[1]));
  });

  test('promoteVariationToMainline promotes nested variations one level', () {
    final deepVariation = [move('d4')];
    final firstVariation = [
      move('c5', variations: [deepVariation]),
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

    navigator.promoteVariationToMainline([0, 0, 0, 0, 0]);

    final e4 = navigator.state.game.mainline.first;
    expect(e4.variations, isNotNull);
    final promotedVariation = e4.variations!.first;
    expect(promotedVariation.map((m) => m.san), ['c5', 'd4']);
    for (final move in promotedVariation) {
      expect(move.variations, isNull);
    }
    expect(navigator.state.movePointer, equals(<int>[0, 0, 1]));
  });
}
