import 'dart:async';
import 'package:bishop/bishop.dart' as bishop;

// State class for chess board
class ChessBoardState {
  final List<bishop.Game> games;
  final List<List<String>> allMoves;
  final List<List<String>> sanMoves;
  final List<int> currentMoveIndex;
  final List<bool> isPlaying;
  final List<bool> isBoardFlipped;
  final List<double> evaluations;
  final Timer? autoPlayTimer;

  ChessBoardState({
    required this.games,
    required this.allMoves,
    required this.sanMoves,
    required this.currentMoveIndex,
    required this.isPlaying,
    required this.isBoardFlipped,
    required this.evaluations,
    this.autoPlayTimer,
  });

  ChessBoardState copyWith({
    List<bishop.Game>? games,
    List<List<String>>? allMoves,
    List<List<String>>? sanMoves,
    List<int>? currentMoveIndex,
    List<bool>? isPlaying,
    List<bool>? isBoardFlipped,
    List<double>? evaluations,
    Timer? autoPlayTimer,
  }) {
    return ChessBoardState(
      games: games ?? this.games,
      allMoves: allMoves ?? this.allMoves,
      sanMoves: sanMoves ?? this.sanMoves,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      evaluations: evaluations ?? this.evaluations,
      autoPlayTimer: autoPlayTimer ?? this.autoPlayTimer,
    );
  }
}