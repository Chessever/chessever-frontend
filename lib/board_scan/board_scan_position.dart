final boardScanSquares = <String>[
  for (var rank = 8; rank >= 1; rank--)
    for (final file in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) '$file$rank',
];
final _pieceCode = RegExp(r'^(-|[wb][PNBRQK])$');

class BoardScanPosition {
  BoardScanPosition({
    required Map<String, String> squares,
    this.warnings = const [],
  }) : squares = Map.unmodifiable(squares) {
    if (squares.length != 64 ||
        boardScanSquares.any((s) => !_pieceCode.hasMatch(squares[s] ?? ''))) {
      throw const FormatException('The board image could not be fully read.');
    }
  }

  final Map<String, String> squares;
  final List<String> warnings;

  String fen({bool blackToMove = false}) {
    final rows = <String>[];
    for (var rank = 8; rank >= 1; rank--) {
      final row = StringBuffer();
      var empty = 0;
      for (final file in 'abcdefgh'.split('')) {
        final piece = squares['$file$rank']!;
        if (piece == '-') {
          empty++;
          continue;
        }
        if (empty > 0) row.write(empty);
        empty = 0;
        row.write(piece[0] == 'w' ? piece[1] : piece[1].toLowerCase());
      }
      if (empty > 0) row.write(empty);
      rows.add(row.toString());
    }
    return '${rows.join('/')} ${blackToMove ? 'b' : 'w'} - - 0 1';
  }
}
