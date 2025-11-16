import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';

class NotationVariationNode {
  final String id;
  final ChessMovePointer parentPointer;
  final int variationIndex;
  final int depth;
  final List<NotationMoveNode> moves;

  const NotationVariationNode({
    required this.id,
    required this.parentPointer,
    required this.variationIndex,
    required this.depth,
    required this.moves,
  });
}

class NotationMoveNode {
  final ChessMove move;
  final ChessMovePointer pointer;
  final int ply;
  final int moveNumber;
  final bool isWhiteMove;
  final bool showMoveNumber;
  final bool showEllipsis;
  final bool isMainline;
  final int depth;
  final List<NotationVariationNode> variations;

  const NotationMoveNode({
    required this.move,
    required this.pointer,
    required this.ply,
    required this.moveNumber,
    required this.isWhiteMove,
    required this.showMoveNumber,
    required this.showEllipsis,
    required this.isMainline,
    required this.depth,
    required this.variations,
  });
}

class NotationTree {
  final List<NotationMoveNode> mainline;
  final int startingPly;

  const NotationTree({required this.mainline, required this.startingPly});
}

class NotationTreeBuilder {
  static NotationTree build(ChessGame game) {
    final startingPly = _startingPly(game.startingFen);
    final mainline = _buildLine(
      line: game.mainline,
      pointerPrefix: const [],
      startPly: startingPly,
      isMainline: true,
      depth: 0,
    );
    return NotationTree(mainline: mainline, startingPly: startingPly);
  }

  static List<NotationMoveNode> _buildLine({
    required ChessLine line,
    required ChessMovePointer pointerPrefix,
    required int startPly,
    required bool isMainline,
    required int depth,
  }) {
    final nodes = <NotationMoveNode>[];
    var ply = startPly;

    for (var i = 0; i < line.length; i++) {
      final pointer = [...pointerPrefix, i];
      final move = line[i];
      final moveNumber = (ply ~/ 2) + 1;
      final isWhiteMove = ply.isEven;
      final showNumber = isWhiteMove || i == 0;
      final showEllipsis = !isWhiteMove && i == 0;

      final variations = <NotationVariationNode>[];
      final moveVariations = move.variations ?? const <ChessLine>[];
      for (var v = 0; v < moveVariations.length; v++) {
        final variationLine = moveVariations[v];
        final variationMoves = _buildLine(
          line: variationLine,
          pointerPrefix: [...pointer, v],
          startPly: ply + 1,
          isMainline: false,
          depth: depth + 1,
        );
        variations.add(
          NotationVariationNode(
            id: NotationPointer.variationId(pointer, v),
            parentPointer: List<Number>.of(pointer),
            variationIndex: v,
            depth: depth + 1,
            moves: variationMoves,
          ),
        );
      }

      nodes.add(
        NotationMoveNode(
          move: move,
          pointer: List<Number>.of(pointer),
          ply: ply,
          moveNumber: moveNumber,
          isWhiteMove: isWhiteMove,
          showMoveNumber: showNumber,
          showEllipsis: showEllipsis,
          isMainline: isMainline,
          depth: depth,
          variations: variations,
        ),
      );
      ply++;
    }

    return nodes;
  }

  static int _startingPly(String startingFen) {
    final parts = startingFen.split(' ');
    if (parts.length < 6) {
      return 0;
    }
    final turn = parts[1];
    final fullmove = int.tryParse(parts[5]) ?? 1;
    final base = (fullmove - 1) * 2;
    return turn == 'w' ? base : base + 1;
  }
}

String notationGameSignature(ChessGame game) {
  final buffer = StringBuffer(game.startingFen);
  _appendLineSignature(game.mainline, buffer);
  return buffer.toString();
}

void _appendLineSignature(ChessLine line, StringBuffer buffer) {
  for (final move in line) {
    buffer.write(move.uci);
    final variations = move.variations ?? const <ChessLine>[];
    if (variations.isEmpty) continue;
    buffer.write('[');
    for (final variation in variations) {
      buffer.write('{');
      _appendLineSignature(variation, buffer);
      buffer.write('}');
    }
    buffer.write(']');
  }
}

String exportGameToPgn(ChessGame game) {
  final buffer = StringBuffer();
  final headers =
      game.metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in headers) {
    final value = entry.value?.toString() ?? '';
    buffer.writeln('[${entry.key} "$value"]');
  }
  buffer.writeln();

  final moves =
      _lineToPgn(
        line: game.mainline,
        startPly: NotationTreeBuilder._startingPly(game.startingFen),
      ).trim();
  if (moves.isNotEmpty) {
    buffer.write(moves);
    buffer.write(' ');
  }
  buffer.write('*');
  return buffer.toString();
}

String _lineToPgn({
  required ChessLine line,
  required int startPly,
  bool isVariation = false,
}) {
  if (line.isEmpty) return '';
  final buffer = StringBuffer();
  var ply = startPly;

  for (var i = 0; i < line.length; i++) {
    final move = line[i];
    final moveNumber = (ply ~/ 2) + 1;
    final isWhiteMove = ply.isEven;
    final showNumber = isWhiteMove || i == 0;

    if (showNumber) {
      final bool suppressBlackNumber = isVariation && !isWhiteMove && i == 0;
      if (suppressBlackNumber) {
        buffer.write('... ');
      } else {
        buffer.write(isWhiteMove ? '$moveNumber. ' : '$moveNumber... ');
      }
    }

    buffer.write('${move.san} ');

    final variations = move.variations ?? const <ChessLine>[];
    for (final variation in variations) {
      final variationText =
          _lineToPgn(
            line: variation,
            startPly: ply + 1,
            isVariation: true,
          ).trim();
      if (variationText.isNotEmpty) {
        buffer.write('($variationText) ');
      }
    }

    ply++;
  }

  return buffer.toString();
}
