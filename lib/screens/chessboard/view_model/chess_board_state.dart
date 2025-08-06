import 'dart:async';
import 'package:chess/chess.dart' as chess;
import 'package:advanced_chess_board/chess_board_controller.dart';

// Cleaned up State class for chess board
class ChessBoardState {
  final chess.Chess game;
  final ChessBoardController chessBoardController;
  final List<String> allMoves;
  final List<String> sanMoves;
  final int currentMoveIndex;
  final bool isPlaying;
  final bool isBoardFlipped;
  final double evaluations;
  final Timer? autoPlayTimer;

  ChessBoardState({
    required this.game,
    required this.chessBoardController,
    required this.allMoves,
    required this.sanMoves,
    required this.currentMoveIndex,
    required this.isPlaying,
    required this.isBoardFlipped,
    required this.evaluations,
    this.autoPlayTimer,
  });

  ChessBoardState copyWith({
    chess.Chess? game,
    ChessBoardController? chessBoardController,
    List<String>? allMoves,
    List<String>? sanMoves,
    int? currentMoveIndex,
    bool? isPlaying,
    bool? isBoardFlipped,
    double? evaluations,
    Timer? autoPlayTimer,
  }) {
    return ChessBoardState(
      game: game ?? this.game,
      chessBoardController: chessBoardController ?? this.chessBoardController,
      allMoves: allMoves ?? this.allMoves,
      sanMoves: sanMoves ?? this.sanMoves,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      evaluations: evaluations ?? this.evaluations,
      autoPlayTimer: autoPlayTimer ?? this.autoPlayTimer,
    );
  }

  void dispose() {
    chessBoardController.dispose();
    autoPlayTimer?.cancel();
  }
}