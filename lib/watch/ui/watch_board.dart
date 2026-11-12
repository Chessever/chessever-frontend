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

/// Readable last move from the relay's UCI and the position after it:
/// `e5f7` → `Ne5–f7`, `e1g1` → `O-O`, `e7e8q` → `e7–e8=Q`. Capture and check
/// are unknowable without the previous position, so they are left out rather
/// than guessed. Returns the input unchanged when it is not UCI.
String? watchLastMoveLabel(String? fen, String? uci) {
  if (uci == null) return null;
  final m = RegExp(r'^([a-h][1-8])([a-h][1-8])([qrbn])?$').firstMatch(uci);
  if (m == null) return uci;
  final from = m.group(1)!, to = m.group(2)!, promo = m.group(3);
  final squares = watchFenSquares(fen);
  final moved = squares?[(8 - int.parse(to[1])) * 8 + to.codeUnitAt(0) - 97];
  final kind = moved?.toUpperCase();
  if (kind == 'K' && from[1] == to[1]) {
    final delta = to.codeUnitAt(0) - from.codeUnitAt(0);
    if (delta == 2) return 'O-O';
    if (delta == -2) return 'O-O-O';
  }
  final letter = kind == null || kind == 'P' || promo != null ? '' : kind;
  return '$letter$from–$to${promo == null ? '' : '=${promo.toUpperCase()}'}';
}

/// VoiceOver reading of a position, grouped by side with the king first:
/// "White: king g2, queen f6, pawns f2, g3, h2. Black: …".
String watchPositionDescription(List<String?> squares) {
  const order = ['k', 'q', 'r', 'b', 'n', 'p'];
  const names = {
    'k': ('king', 'king'),
    'q': ('queen', 'queens'),
    'r': ('rook', 'rooks'),
    'b': ('bishop', 'bishops'),
    'n': ('knight', 'knights'),
    'p': ('pawn', 'pawns'),
  };
  String side(bool white) {
    final parts = <String>[];
    for (final kind in order) {
      final at = <String>[];
      for (var i = 0; i < 64; i++) {
        final piece = squares[i];
        if (piece == (white ? kind.toUpperCase() : kind)) {
          at.add('${String.fromCharCode(97 + i % 8)}${8 - i ~/ 8}');
        }
      }
      if (at.isEmpty) continue;
      at.sort();
      final (one, many) = names[kind]!;
      parts.add('${at.length == 1 ? one : many} ${at.join(', ')}');
    }
    return '${white ? 'White' : 'Black'}: ${parts.join(', ')}.';
  }

  return '${side(true)} ${side(false)}';
}

/// The side a player has, drawn with the board's own Cburnett king so the
/// rows speak the same visual language as the position above them.
class WatchSideMark extends StatelessWidget {
  const WatchSideMark({super.key, required this.white, this.size = 15});
  final bool white;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'packages/chessground/assets/piece_sets/cburnett/'
    '${white ? 'w' : 'b'}K.webp',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
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
    return Semantics(
      label: 'Chess position',
      value: watchPositionDescription(squares),
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
