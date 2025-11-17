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
      mainline: [move('e4', variations: [variation])],
    );
    final navigator = ChessGameNavigator(game);

    expect(navigator.state.game.mainline[0].variations?.length, 1);

    navigator.deleteVariationAtPointer([0, 0, 0]);

    expect(navigator.state.game.mainline[0].variations, isNull);
  });
}
