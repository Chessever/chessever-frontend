import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:dartchess/dartchess.dart';

class ChessBoardStateNew {
  final Position? position;
  final Position? startingPosition;
  final Move? lastMove;
  final List<Move> allMoves;
  final List<String> moveSans;
  final int currentMoveIndex;
  final bool isPlaying;
  final bool isBoardFlipped;
  final bool isLoadingMoves;
  final double evaluation;
  final GamesTourModel game;
  final String? pgnData; 
  
  // Computed properties
  bool get canMoveForward => currentMoveIndex < allMoves.length - 1;
  bool get canMoveBackward => currentMoveIndex >= 0;
  bool get isAtStart => currentMoveIndex == -1;
  bool get isAtEnd => currentMoveIndex == allMoves.length - 1;
  int get totalMoves => allMoves.length;

  const ChessBoardStateNew({
    this.position,
    this.startingPosition,
    this.lastMove,
    this.allMoves = const [],
    this.moveSans = const [],
    this.currentMoveIndex = -1,
    this.isPlaying = false,
    this.isBoardFlipped = false,
    this.isLoadingMoves = false,
    this.evaluation = 0,
    required this.game,
    this.pgnData
  });

  ChessBoardStateNew copyWith({
    Position? position,
    Position? startingPosition,
    Move? lastMove,
    List<Move>? allMoves,
    List<String>? moveSans,
    int? currentMoveIndex,
    bool? isPlaying,
    bool? isBoardFlipped,
    bool? isLoadingMoves,
    double? evaluation,
    GamesTourModel? game,
    String? pgnData,
  }) {
    return ChessBoardStateNew(
      position: position ?? this.position,
      startingPosition: startingPosition ?? this.startingPosition,
      lastMove: lastMove ?? this.lastMove,
      allMoves: allMoves ?? this.allMoves,
      moveSans: moveSans ?? this.moveSans,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      isLoadingMoves: isLoadingMoves ?? this.isLoadingMoves,
      evaluation: evaluation ?? 0,
      game: game ?? this.game,
      pgnData: pgnData ?? this.pgnData,
    );
  }
}