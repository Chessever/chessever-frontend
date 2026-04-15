import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';

ChessMove move(String san, ChessColor turn, {List<ChessLine>? variations}) {
  return ChessMove(
    num: 1,
    fen: 'fen',
    san: san,
    uci: san,
    turn: turn,
    variations: variations,
  );
}

void main() {
  final d4 = move('d4', ChessColor.white);
  final c5 = move('c5', ChessColor.black);
  final e5 = move('e5', ChessColor.black);
  final Nf3 = move('Nf3', ChessColor.white);
  final Nc3 = move('Nc3', ChessColor.white);

  final mainline = [
    move('e4', ChessColor.white, variations: [
      [d4],
      [c5, Nc3],
    ]),
    e5,
    Nf3,
  ];

  final pointers = [
    [0],
    [1],
    [0, 0, 0], // d4
    [0, 1, 0], // c5
    [0, 1, 1], // Nc3
  ];

  for (final pointer in pointers) {
    final path = <ChessMove>[];
    List<ChessMove>? currentList = mainline;
    ChessMove? currentMove;

    for (var i = 0; i < pointer.length; i++) {
      final index = pointer[i];
      if (i.isEven) {
        path.addAll(currentList!.take(index + 1));
        currentMove = currentList[index];
        if (i == pointer.length - 1) break;
      } else {
        final variation = currentMove!.variations![index];
        if (variation.isNotEmpty) {
          final firstVariationMove = variation.first;
          if (firstVariationMove.turn == currentMove.turn) {
            path.removeLast();
          }
        }
        currentList = variation;
      }
    }
    print('Pointer $pointer => Path: ${path.map((m) => m.san).join(' ')}');
  }
}
