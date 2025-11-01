import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';

/// Represents a single move node in the notation tree
class NotationNode {
  /// Unique identifier for this node, derived from its pointer path (e.g., "0/2/0")
  final String id;

  /// Standard algebraic notation (e.g., "Nf3", "e4")
  final String san;

  /// UCI notation (e.g., "e2e4")
  final String uci;

  /// Ply number (half-move count, starting from 0)
  final int ply;

  /// Move number (full-move count, e.g., 1, 2, 3...)
  final int moveNumber;

  /// True if this is White's move
  final bool isWhiteMove;

  /// True if this node is on the mainline path
  final bool isMainline;

  /// FEN position before this move
  final String fenBefore;

  /// FEN position after this move
  final String fenAfter;

  /// Clock time for this move (optional)
  final String? clockTime;

  /// Nested variations: each inner list is a complete variation line branching at this node
  /// Empty if no variations exist
  final List<List<NotationNode>> children;

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
    this.clockTime,
    this.children = const [],
  });

  NotationNode copyWith({
    String? id,
    String? san,
    String? uci,
    int? ply,
    int? moveNumber,
    bool? isWhiteMove,
    bool? isMainline,
    String? fenBefore,
    String? fenAfter,
    String? clockTime,
    List<List<NotationNode>>? children,
  }) {
    return NotationNode(
      id: id ?? this.id,
      san: san ?? this.san,
      uci: uci ?? this.uci,
      ply: ply ?? this.ply,
      moveNumber: moveNumber ?? this.moveNumber,
      isWhiteMove: isWhiteMove ?? this.isWhiteMove,
      isMainline: isMainline ?? this.isMainline,
      fenBefore: fenBefore ?? this.fenBefore,
      fenAfter: fenAfter ?? this.fenAfter,
      clockTime: clockTime ?? this.clockTime,
      children: children ?? this.children,
    );
  }

  @override
  String toString() => 'NotationNode($id: $san)';
}

/// Builds a notation tree from a ChessGameNavigatorState
class NotationTreeBuilder {
  /// Build a list of notation nodes from the navigator state
  /// Returns the mainline as a flat list where each node may have nested variations
  static List<NotationNode> fromNavigatorState(
    ChessGameNavigatorState navigatorState,
  ) {
    final game = navigatorState.game;
    final startingFen = game.startingFen;

    return _buildLine(
      line: game.mainline,
      startingFen: startingFen,
      pointerPrefix: [],
      isMainline: true,
      startingPly: 0,
    );
  }

  /// Recursively build a line of notation nodes
  static List<NotationNode> _buildLine({
    required ChessLine line,
    required String startingFen,
    required List<int> pointerPrefix,
    required bool isMainline,
    required int startingPly,
  }) {
    if (line.isEmpty) return [];

    final nodes = <NotationNode>[];
    String currentFen = startingFen;
    int ply = startingPly;

    for (int moveIndex = 0; moveIndex < line.length; moveIndex++) {
      final move = line[moveIndex];
      final pointer = [...pointerPrefix, moveIndex];
      final nodeId = pointer.join('/');

      // Build child variations if they exist
      final childVariations = <List<NotationNode>>[];
      if (move.variations != null && move.variations!.isNotEmpty) {
        for (int varIndex = 0; varIndex < move.variations!.length; varIndex++) {
          final variation = move.variations![varIndex];
          // Variation starts from the current FEN (before this move)
          final variationNodes = _buildLine(
            line: variation,
            startingFen: currentFen,
            pointerPrefix: [...pointer, varIndex],
            isMainline: false,
            startingPly: ply,
          );
          if (variationNodes.isNotEmpty) {
            childVariations.add(variationNodes);
          }
        }
      }

      final node = NotationNode(
        id: nodeId,
        san: move.san,
        uci: move.uci,
        ply: ply,
        moveNumber: move.num,
        isWhiteMove: move.turn == ChessColor.white,
        isMainline: isMainline,
        fenBefore: currentFen,
        fenAfter: move.fen,
        clockTime: move.clockTime,
        children: childVariations,
      );

      nodes.add(node);

      // Update current FEN and ply for next iteration
      currentFen = move.fen;
      ply++;
    }

    return nodes;
  }

  /// Get a flattened list of all nodes (DFS traversal)
  static List<NotationNode> flattenTree(List<NotationNode> rootNodes) {
    final result = <NotationNode>[];

    void traverse(NotationNode node) {
      result.add(node);
      for (final variation in node.children) {
        for (final varNode in variation) {
          traverse(varNode);
        }
      }
    }

    for (final node in rootNodes) {
      traverse(node);
    }

    return result;
  }

  /// Find a node by its ID in the tree
  static NotationNode? findNodeById(List<NotationNode> rootNodes, String id) {
    for (final node in rootNodes) {
      if (node.id == id) return node;

      // Search in variations
      for (final variation in node.children) {
        final found = findNodeById(variation, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Convert a pointer to a node ID string
  static String pointerToId(ChessMovePointer pointer) {
    return pointer.join('/');
  }

  /// Convert a node ID to a pointer
  static ChessMovePointer idToPointer(String id) {
    if (id.isEmpty) return [];
    return id.split('/').map(int.parse).toList();
  }
}
