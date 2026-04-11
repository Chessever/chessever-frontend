import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';
import 'package:dartchess/dartchess.dart'
    show PgnChildNode, PgnGame, PgnNode, PgnNodeData;

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
  final root = PgnNode<PgnNodeData>();
  _appendLineToPgnNode(root, game.mainline);

  final headers = _buildPgnHeaders(game);
  return PgnGame<PgnNodeData>(
    headers: headers,
    moves: root,
    comments: const [],
  ).makePgn();
}

const _standardStartingFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

Map<String, String> _buildPgnHeaders(ChessGame game) {
  final sortedEntries =
      game.metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  final headers = <String, String>{};

  for (final entry in sortedEntries) {
    headers[entry.key] = entry.value?.toString() ?? '';
  }

  headers.putIfAbsent('Result', () => '*');

  final hasCustomStart =
      game.startingFen.trim().isNotEmpty &&
      game.startingFen.trim() != _standardStartingFen;
  final hasFenHeader = (headers['FEN']?.trim().isNotEmpty ?? false);

  if (hasCustomStart || hasFenHeader) {
    headers['SetUp'] = '1';
    headers.putIfAbsent('FEN', () => game.startingFen);
  }

  return headers;
}

void _appendLineToPgnNode(PgnNode<PgnNodeData> parent, ChessLine line) {
  if (line.isEmpty) return;

  final headMove = line.first;
  final headNode = PgnChildNode<PgnNodeData>(_toPgnNodeData(headMove));
  parent.children.add(headNode);
  _appendChildrenToPgnNode(headNode, line, moveIndex: 0);
}

void _appendChildrenToPgnNode(
  PgnNode<PgnNodeData> parent,
  ChessLine line, {
  required int moveIndex,
}) {
  final move = line[moveIndex];

  if (moveIndex + 1 < line.length) {
    _appendLineToPgnNode(parent, line.sublist(moveIndex + 1));
  }

  for (final variation in move.variations ?? const <ChessLine>[]) {
    _appendLineToPgnNode(parent, variation);
  }
}

PgnNodeData _toPgnNodeData(ChessMove move) {
  final comments = <String>[];

  if (move.clockTime?.isNotEmpty ?? false) {
    comments.add('[%clk ${move.clockTime}]');
  }

  if (move.eval?.isNotEmpty ?? false) {
    comments.add('[%eval ${move.eval}]');
  }

  for (final comment in move.comments ?? const <String>[]) {
    if (comment.startsWith('[%clk') || comment.startsWith('[%eval')) {
      continue;
    }
    comments.add(comment);
  }

  return PgnNodeData(
    san: move.san,
    comments: comments.isEmpty ? null : comments,
    nags: move.nags,
  );
}
