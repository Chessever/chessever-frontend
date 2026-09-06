import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/utils/pgn_export_utils.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';
import 'package:chessever2/screens/chessboard/notation/pgn_move_number_repair.dart';
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
  /// Every variation id in [game], in the exact form [build] assigns them.
  /// Lets a view remember which branches existed at one moment: the navigator
  /// appends new branches, so ids taken here keep pointing at the same lines.
  static Set<String> variationIds(ChessGame game) {
    final ids = <String>{};
    void visit(ChessLine line, ChessMovePointer prefix) {
      for (var i = 0; i < line.length; i++) {
        final pointer = [...prefix, i];
        final variations = line[i].variations ?? const <ChessLine>[];
        for (var v = 0; v < variations.length; v++) {
          ids.add(NotationPointer.variationId(pointer, v));
          visit(variations[v], [...pointer, v]);
        }
      }
    }

    visit(game.mainline, const []);
    return ids;
  }

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

String? variationAlternativeToText(
  NotationVariationNode variation,
  Map<String, NotationMoveNode> pointerMap,
) {
  if (variation.parentPointer.isEmpty) return null;

  final alternativeToPointer = List<Number>.of(variation.parentPointer);
  alternativeToPointer[alternativeToPointer.length - 1]++;
  final alternativeToId = NotationPointer.encode(alternativeToPointer);
  final alternativeTo = pointerMap[alternativeToId];
  if (alternativeTo == null) return null;

  final dots = alternativeTo.isWhiteMove ? '.' : '...';
  final cleanSan = alternativeTo.move.san.replaceAll(RegExp(r'[!?]+$'), '');
  return 'Alt to ${alternativeTo.moveNumber}$dots$cleanSan';
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
  final pgn =
      PgnGame<PgnNodeData>(
        headers: headers,
        moves: root,
        comments: const [],
      ).makePgn();
  return _withRepairedMoveNumbers(pgn);
}

/// dartchess omits the `N...` indicator on a black move that follows a comment.
/// Repair the movetext only — headers are already canonical.
String _withRepairedMoveNumbers(String pgn) {
  final separator = pgn.indexOf('\n\n');
  if (separator == -1) return restoreBlackMoveNumbers(pgn);
  final headers = pgn.substring(0, separator + 2);
  return headers + restoreBlackMoveNumbers(pgn.substring(separator + 2));
}

const _standardStartingFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

Map<String, String> _buildPgnHeaders(ChessGame game) {
  final headers = <String, String>{};

  for (final entry in game.metadata.entries) {
    headers[entry.key] = entry.value?.toString() ?? '';
  }

  final hasCustomStart =
      game.startingFen.trim().isNotEmpty &&
      game.startingFen.trim() != _standardStartingFen;
  final hasFenHeader = (headers['FEN']?.trim().isNotEmpty ?? false);

  if (hasCustomStart || hasFenHeader) {
    headers['SetUp'] = '1';
    headers.putIfAbsent('FEN', () => game.startingFen);
  }

  return canonicalPgnHeaders(headers);
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

  // One comment carries both machine tags, `[%eval]` first, exactly as Lichess
  // and chess.com write them. Splitting them across two `{}` blocks is legal
  // but not what any producer emits, and readers that keep a single comment
  // per move then drop whichever one lost the race — that is how our clocks
  // went missing in ChessBase.
  final tags = <String>[
    if (move.eval?.isNotEmpty ?? false) '[%eval ${move.eval}]',
    if (move.clockTime?.isNotEmpty ?? false) '[%clk ${move.clockTime}]',
  ];
  if (tags.isNotEmpty) comments.add(tags.join(' '));

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
