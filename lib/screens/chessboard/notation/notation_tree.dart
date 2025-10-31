import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'notation_pointer.dart';

class NotationNode {
  final NotationId id; // pointer-like path: e.g., "0/2/0"
  final String san;
  final String uci;
  final int ply; // 0-based ply index from start of game
  final int moveNumber; // human move number
  final bool isWhiteMove;
  final bool isMainline;
  final String fenBefore;
  final String fenAfter;
  final List<List<NotationNode>> variations; // sibling branches starting here

  const NotationNode({
    required this.id,
    required this.san,
    required this.uci,
    required this.ply,
    required this.moveNumber,
    required this.isWhiteMove,
    required this.isMainline,
    required this.fenBefore,
    required this.fenAfter,
    required this.variations,
  });
}

class NotationTreeBuilder {
  static List<NotationNode> build(ChessGameNavigatorState state) {
    final List<NotationNode> result = [];
    final startFen = state.game.startingFen;
    _buildLine(
      out: result,
      line: state.game.mainline,
      fenBefore: startFen,
      isMainline: true,
      basePrefix: '',
      startPly: 0,
    );
    return result;
  }

  static void _buildLine({
    required List<NotationNode> out,
    required ChessLine line,
    required String fenBefore,
    required bool isMainline,
    required NotationId basePrefix,
    required int startPly,
  }) {
    int ply = startPly;
    for (int i = 0; i < line.length; i++) {
      final move = line[i];
      final id = basePrefix.isEmpty ? '$i' : '$basePrefix/$i';
      final node = NotationNode(
        id: id,
        san: move.san,
        uci: move.uci,
        ply: ply,
        moveNumber: move.num,
        isWhiteMove: move.turn == ChessColor.white,
        isMainline: isMainline,
        fenBefore: fenBefore,
        fenAfter: move.fen,
        variations: const [],
      );
      out.add(node);

      // Collect variations branching at this next move index
      final moveVariations = move.variations ?? const <ChessLine>[];
      if (moveVariations.isNotEmpty) {
        final List<List<NotationNode>> varNodes = [];
        for (int v = 0; v < moveVariations.length; v++) {
          final varLine = moveVariations[v];
          final List<NotationNode> varList = [];
          // Variations branch at this ply: their head id should be '${id}/${v}/0'
          final varPrefix = basePrefix.isEmpty ? '${i}/$v' : '$basePrefix/$i/$v';
          _buildLine(
            out: varList,
            line: varLine,
            fenBefore: fenBefore, // branch from same fenBefore at divergence
            isMainline: false,
            basePrefix: varPrefix,
            startPly: ply,
          );
          varNodes.add(varList);
        }
        out[out.length - 1] = NotationNode(
          id: node.id,
          san: node.san,
          uci: node.uci,
          ply: node.ply,
          moveNumber: node.moveNumber,
          isWhiteMove: node.isWhiteMove,
          isMainline: node.isMainline,
          fenBefore: node.fenBefore,
          fenAfter: node.fenAfter,
          variations: varNodes,
        );
      }

      fenBefore = move.fen;
      ply += 1;
    }
  }
}
