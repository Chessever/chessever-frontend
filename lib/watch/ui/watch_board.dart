import 'package:flutter/cupertino.dart';
import 'watch_widgets.dart';

List<String?>? watchFenSquares(String? fen) {
  if (fen == null) return null;
  final ranks = fen.split(' ').first.split('/');
  if (ranks.length != 8) return null;
  final squares = <String?>[];
  for (final rank in ranks) {
    final start = squares.length;
    for (final piece in rank.split('')) {
      final empty = int.tryParse(piece);
      if (empty != null && empty >= 1 && empty <= 8) {
        squares.addAll(List<String?>.filled(empty, null));
      } else if ('PNBRQKpnbrqk'.contains(piece)) {
        squares.add(piece);
      } else {
        return null;
      }
    }
    if (squares.length - start != 8) return null;
  }
  return squares;
}

Set<int> watchLastMoveSquares(String? move) {
  final result = <int>{};
  final matches = RegExp(r'[a-h][1-8]').allMatches(move ?? '');
  for (final match in matches) {
    final square = match.group(0)!;
    result.add((8 - int.parse(square[1])) * 8 + square.codeUnitAt(0) - 97);
  }
  return result;
}

class WatchBoard extends StatelessWidget {
  const WatchBoard({
    super.key,
    required this.fen,
    this.lastMove,
    this.flipped = false,
  });
  final String? fen;
  final String? lastMove;
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    final squares = watchFenSquares(fen);
    if (squares == null) return const WatchNote('Position not available yet.');
    final highlights = watchLastMoveSquares(lastMove);
    final position = <String>[];
    const names = {
      'p': 'pawn',
      'n': 'knight',
      'b': 'bishop',
      'r': 'rook',
      'q': 'queen',
      'k': 'king',
    };
    for (var i = 0; i < 64; i++) {
      final piece = squares[i];
      if (piece == null) continue;
      final color = piece == piece.toUpperCase() ? 'White' : 'Black';
      position.add(
        '$color ${names[piece.toLowerCase()]} '
        '${String.fromCharCode(97 + i % 8)}${8 - i ~/ 8}',
      );
    }
    return Semantics(
      label: 'Chess position',
      value: position.join(', '),
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Column(
              children: [
                for (var rank = 0; rank < 8; rank++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var file = 0; file < 8; file++)
                          Expanded(
                            child: _square(
                              squares,
                              flipped
                                  ? 63 - (rank * 8 + file)
                                  : rank * 8 + file,
                              highlights,
                              (rank + file).isEven,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _square(
    List<String?> squares,
    int index,
    Set<int> highlights,
    bool light,
  ) {
    final piece = squares[index];
    return ColoredBox(
      color: light ? WatchStyle.lightSquare : WatchStyle.darkSquare,
      child: ColoredBox(
        color: highlights.contains(index)
            ? WatchStyle.lastMove
            : const Color(0x00000000),
        child: piece == null
            ? const SizedBox.expand()
            : Image.asset(
                'packages/chessground/assets/piece_sets/cburnett/'
                '${piece == piece.toUpperCase() ? 'w' : 'b'}${piece.toUpperCase()}.webp',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
      ),
    );
  }
}
