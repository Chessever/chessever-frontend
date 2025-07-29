import 'dart:async';
import 'package:bishop/bishop.dart' as bishop;
import 'package:square_bishop/square_bishop.dart' as square_bishop;
import 'package:squares/squares.dart' as square;

// State class for chess board
class ChessBoardState {
  final bishop.Game game;
  final square_bishop.SquaresState squaresState;
  final List<String> allMoves;
  final List<String> sanMoves;
  final int currentMoveIndex;
  final bool isPlaying;
  final bool isBoardFlipped;
  final double evaluations;
  final Timer? autoPlayTimer;
  final int? lastUpdatedGameIndex;
  final DateTime? lastUpdateTime;

  ChessBoardState({
    required this.game,
    required this.squaresState,
    required this.allMoves,
    required this.sanMoves,
    required this.currentMoveIndex,
    required this.isPlaying,
    required this.isBoardFlipped,
    required this.evaluations,
    this.autoPlayTimer,
    this.lastUpdatedGameIndex,
    this.lastUpdateTime,
  });

  ChessBoardState copyWith({
    bishop.Game? game,
    square_bishop.SquaresState? squaresState,
    List<String>? allMoves,
    List<String>? sanMoves,
    int? currentMoveIndex,
    bool? isPlaying,
    bool? isBoardFlipped,
    double? evaluations,
    Timer? autoPlayTimer,
    bool? isConnected,
    String? lastError,
    int? lastUpdatedGameIndex,
    DateTime? lastUpdateTime,
  }) {
    return ChessBoardState(
      game: game ?? this.game,
      allMoves: allMoves ?? this.allMoves,
      sanMoves: sanMoves ?? this.sanMoves,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      evaluations: evaluations ?? this.evaluations,
      autoPlayTimer: autoPlayTimer ?? this.autoPlayTimer,
      lastUpdatedGameIndex: lastUpdatedGameIndex,
      lastUpdateTime: lastUpdateTime,
      squaresState: squaresState ?? this.squaresState,
    );
  }
}
