import 'dart:async';
import 'package:dartchess/dartchess.dart' as chess;

// Enhanced State class with clear semantics
class ChessBoardState {
  final chess.Game baseGame; // The complete game loaded from PGN
  final chess.Game currentGame; // Current position of the board
  final List<String> uciMoves; // UCI format moves (e2e4)
  final List<String> sanMoves; // SAN format moves (e4)
  final int currentMoveIndex; // 0 = start, 1 = after first move, etc.
  final bool isPlaying;
  final bool isBoardFlipped;
  final double evaluations;
  final Timer? autoPlayTimer;
  final bool isLoadingMoves;

  ChessBoardState({
    required this.baseGame,
    required this.currentGame,
    required this.uciMoves,
    required this.sanMoves,
    required this.currentMoveIndex,
    required this.isPlaying,
    required this.isBoardFlipped,
    required this.evaluations,
    this.autoPlayTimer,
    this.isLoadingMoves = false,
  });

  // Convenience getters
  chess.Game get currentPosition => currentGame;
  int get totalMoves => uciMoves.length;
  bool get canMoveForward => currentMoveIndex < totalMoves;
  bool get canMoveBackward => currentMoveIndex > 0;
  bool get isAtStart => currentMoveIndex == 0;
  bool get isAtEnd => currentMoveIndex == totalMoves;

  // Get current last move for highlighting (null if at start)
  String? get currentLastMoveUci =>
      currentMoveIndex > 0 ? uciMoves[currentMoveIndex - 1] : null;

  String? get currentLastMoveSan =>
      currentMoveIndex > 0 ? sanMoves[currentMoveIndex - 1] : null;

  // Parse UCI move for highlighting
  (String?, String?) get lastMoveSquares {
    final uci = currentLastMoveUci;
    if (uci != null && uci.length >= 4) {
      return (uci.substring(0, 2), uci.substring(2, 4));
    }
    return (null, null);
  }

  ChessBoardState copyWith({
    chess.Game? baseGame,
    chess.Game? currentGame,
    List<String>? uciMoves,
    List<String>? sanMoves,
    int? currentMoveIndex,
    bool? isPlaying,
    bool? isBoardFlipped,
    double? evaluations,
    Timer? autoPlayTimer,
    bool? isLoadingMoves,
  }) {
    return ChessBoardState(
      baseGame: baseGame ?? this.baseGame,
      currentGame: currentGame ?? this.currentGame,
      uciMoves: uciMoves ?? this.uciMoves,
      sanMoves: sanMoves ?? this.sanMoves,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      evaluations: evaluations ?? this.evaluations,
      autoPlayTimer: autoPlayTimer ?? this.autoPlayTimer,
      isLoadingMoves: isLoadingMoves ?? this.isLoadingMoves,
    );
  }

  void dispose() {
    autoPlayTimer?.cancel();
  }
}
