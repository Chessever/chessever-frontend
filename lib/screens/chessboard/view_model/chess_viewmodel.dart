import 'dart:async';
import 'dart:convert';
import 'package:bishop/bishop.dart' as bishop;
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:square_bishop/square_bishop.dart';
import 'package:squares/squares.dart';

// State classes
class ChessGameState {
  final bishop.Game game;
  final SquaresState squaresState;
  final int player;
  final bool simulatingPgn;
  final int currentMoveIndex;
  final List<String> pgnMoves;
  final bool isLoading;
  final String? error;

  const ChessGameState({
    required this.game,
    required this.squaresState,
    this.player = Squares.white,
    this.simulatingPgn = false,
    this.currentMoveIndex = 0,
    this.pgnMoves = const [],
    this.isLoading = false,
    this.error,
  });

  ChessGameState copyWith({
    bishop.Game? game,
    SquaresState? squaresState,
    int? player,
    bool? simulatingPgn,
    int? currentMoveIndex,
    List<String>? pgnMoves,
    bool? isLoading,
    String? error,
  }) {
    return ChessGameState(
      game: game ?? this.game,
      squaresState: squaresState ?? this.squaresState,
      player: player ?? this.player,
      simulatingPgn: simulatingPgn ?? this.simulatingPgn,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      pgnMoves: pgnMoves ?? this.pgnMoves,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// Chess ViewModel as a StateNotifier
class ChessViewModel extends StateNotifier<ChessGameState> {
  Timer? _simulationTimer;

  ChessViewModel() : super(_createInitialState()) {
    _loadMockMoves();
  }

  static ChessGameState _createInitialState() {
    final game = bishop.Game();
    return ChessGameState(
      game: game,
      squaresState: game.squaresState(Squares.white),
    );
  }

  // Add these methods to your ChessViewModel class

  void goToNextMove() {
    if (state.simulatingPgn ||
        state.currentMoveIndex >= state.pgnMoves.length) {
      return;
    }

    final currentMove = state.pgnMoves[state.currentMoveIndex];
    final move = _findMove(currentMove);

    if (move != null && state.game.makeMove(move)) {
      state = state.copyWith(
        squaresState: state.game.squaresState(state.player),
        currentMoveIndex: state.currentMoveIndex + 1,
      );
    }
  }

  void goToPreviousMove() {
    if (state.simulatingPgn || state.currentMoveIndex <= 0) {
      return;
    }

    // Rebuild the game state up to the previous move
    final game = bishop.Game();
    final targetIndex = state.currentMoveIndex - 1;

    for (int i = 0; i < targetIndex; i++) {
      final moveStr = state.pgnMoves[i];
      final move = _findMoveForGame(game, moveStr);
      if (move != null) {
        game.makeMove(move);
      }
    }

    state = state.copyWith(
      game: game,
      squaresState: game.squaresState(state.player),
      currentMoveIndex: targetIndex,
    );
  }

  // Helper method to find moves for any game state
  bishop.Move? _findMoveForGame(bishop.Game game, String algebraic) {
    try {
      var moves = game.generateLegalMoves();

      // Try using the bishop library's built-in parsing
      try {
        var parsedMove = game.getMove(algebraic);
        if (parsedMove != null && moves.contains(parsedMove)) {
          return parsedMove;
        }
      } catch (e) {
        // Silent fail, try coordinate conversion
      }

      // Use the same coordinate conversion logic
      return _convertAlgebraicToCoordinateForGame(game, algebraic, moves);
    } catch (e) {
      print('Error in _findMoveForGame: $e');
      return null;
    }
  }

  bishop.Move? _convertAlgebraicToCoordinateForGame(
    bishop.Game game,
    String algebraic,
    List<bishop.Move> moves,
  ) {
    // Simple pawn moves like "e4"
    if (algebraic.length == 2 &&
        algebraic[0].toLowerCase().contains(RegExp(r'[a-h]')) &&
        algebraic[1].contains(RegExp(r'[1-8]'))) {
      String targetFile = algebraic[0].toLowerCase();
      String targetRank = algebraic[1];

      for (var move in moves) {
        String moveStr = game.toAlgebraic(move);
        if (moveStr.length >= 4) {
          String toFile = moveStr[2];
          String toRank = moveStr[3];
          String fromFile = moveStr[0];

          if (toFile == targetFile &&
              toRank == targetRank &&
              fromFile == targetFile) {
            return move;
          }
        }
      }
    }
    // Handle piece moves like "Nf3"
    else if (algebraic.length == 3) {
      String targetFile = algebraic[1].toLowerCase();
      String targetRank = algebraic[2];

      for (var move in moves) {
        String moveStr = game.toAlgebraic(move);
        if (moveStr.length >= 4) {
          String toFile = moveStr[2];
          String toRank = moveStr[3];

          if (toFile == targetFile && toRank == targetRank) {
            return move;
          }
        }
      }
    }
    // Handle castling
    else if (algebraic == "O-O" || algebraic == "0-0") {
      for (var move in moves) {
        String moveStr = game.toAlgebraic(move);
        if (moveStr == "e1g1" || moveStr == "e8g8") {
          return move;
        }
      }
    } else if (algebraic == "O-O-O" || algebraic == "0-0-0") {
      for (var move in moves) {
        String moveStr = game.toAlgebraic(move);
        if (moveStr == "e1c1" || moveStr == "e8c8") {
          return move;
        }
      }
    }

    return null;
  }

  Future<void> _loadMockMoves() async {
    state = state.copyWith(isLoading: true);

    try {
      final jsonString = await rootBundle.loadString('../utils/moves.json');
      final jsonData = jsonDecode(jsonString);
      final moves = List<String>.from(jsonData['pgnMoves']);

      state = state.copyWith(pgnMoves: moves, isLoading: false, error: null);

      print('Successfully loaded ${moves.length} moves from JSON');
    } catch (e) {
      print('Error loading mock moves: $e');

      final defaultMoves = [
        "e4", // 1. e4
        "e5", // 1... e5
        "f3", // 2. Nf3
        "Nc6", // 2... Nc6
        "Bb5", // 3. Bb5 (Ruy Lopez)
        "a6", // 3... a6
      ];

      state = state.copyWith(
        pgnMoves: defaultMoves,
        isLoading: false,
        error: null,
      );

      print('Using default moves instead');
    }
  }

  void resetGame([List<String>? moves]) {
    _simulationTimer?.cancel();

    final game = bishop.Game();
    state = ChessGameState(
      game: game,
      squaresState: game.squaresState(state.player),
      player: state.player,
      pgnMoves: moves ?? state.pgnMoves,
    );
  }

  Future<void> simulatePgnMoves({
    Duration moveDelay = const Duration(milliseconds: 1000),
  }) async {
    if (state.simulatingPgn || state.pgnMoves.isEmpty) {
      print(
        'Simulation not started: ${state.simulatingPgn ? "Already simulating" : "No moves"}',
      );
      return;
    }

    // Reset the game and start simulation
    final game = bishop.Game();
    state = state.copyWith(
      game: game,
      squaresState: game.squaresState(state.player),
      simulatingPgn: true,
      currentMoveIndex: 0,
    );

    _simulationTimer = Timer.periodic(moveDelay, (timer) {
      if (state.currentMoveIndex >= state.pgnMoves.length ||
          !state.simulatingPgn) {
        timer.cancel();
        state = state.copyWith(simulatingPgn: false);
        print('Simulation completed or stopped');
        return;
      }

      final currentMove = state.pgnMoves[state.currentMoveIndex];
      print('Attempting move ${state.currentMoveIndex + 1}: $currentMove');

      try {
        final move = _findMove(currentMove);
        if (move != null) {
          print('Found move: ${state.game.toAlgebraic(move)}');
          bool success = state.game.makeMove(move);
          if (success) {
            print('Move successful');
            state = state.copyWith(
              squaresState: state.game.squaresState(state.player),
              currentMoveIndex: state.currentMoveIndex + 1,
            );
          } else {
            print('Move failed to execute');
            timer.cancel();
            state = state.copyWith(simulatingPgn: false);
          }
        } else {
          print('Could not find matching move for: $currentMove');
          print(
            'Available moves: ${state.game.generateLegalMoves().map((m) => state.game.toAlgebraic(m)).toList()}',
          );
          timer.cancel();
          state = state.copyWith(simulatingPgn: false);
        }
      } catch (e) {
        print('Error during move execution: $e');
        timer.cancel();
        state = state.copyWith(simulatingPgn: false);
      }
    });
  }

  bishop.Move? _findMove(String algebraic) {
    try {
      var moves = state.game.generateLegalMoves();
      print('Looking for move: "$algebraic"');

      // First try using the bishop library's built-in parsing
      try {
        var parsedMove = state.game.getMove(algebraic);
        if (parsedMove != null && moves.contains(parsedMove)) {
          print(
            'Found via bishop parsing: ${state.game.toAlgebraic(parsedMove)}',
          );
          return parsedMove;
        }
      } catch (e) {
        print('Bishop parsing failed: $e');
      }

      // The library returns coordinate notation, so we need to convert
      bishop.Move? foundMove = _convertAlgebraicToCoordinate(algebraic, moves);
      if (foundMove != null) {
        print(
          'Found via coordinate conversion: ${state.game.toAlgebraic(foundMove)}',
        );
        return foundMove;
      }

      print('Could not find move for: $algebraic');
      return null;
    } catch (e) {
      print('Error in _findMove: $e');
      return null;
    }
  }

  bishop.Move? _convertAlgebraicToCoordinate(
    String algebraic,
    List<bishop.Move> moves,
  ) {
    // Handle different types of moves

    // Simple pawn moves like "e4" -> look for "e2e4" or "e7e4" etc.
    if (algebraic.length == 2 &&
        algebraic[0].toLowerCase().contains(RegExp(r'[a-h]')) &&
        algebraic[1].contains(RegExp(r'[1-8]'))) {
      String targetFile = algebraic[0].toLowerCase();
      String targetRank = algebraic[1];

      for (var move in moves) {
        String moveStr = state.game.toAlgebraic(move);
        if (moveStr.length >= 4) {
          String toFile = moveStr[2];
          String toRank = moveStr[3];

          // Check if this move goes to our target square
          if (toFile == targetFile && toRank == targetRank) {
            // For pawn moves, the from-file should match the to-file
            String fromFile = moveStr[0];
            if (fromFile == targetFile) {
              return move;
            }
          }
        }
      }
    }
    // Handle piece moves like "Nf3" -> look for knight moves to f3
    else if (algebraic.length == 3) {
      String piece = algebraic[0].toUpperCase();
      String targetFile = algebraic[1].toLowerCase();
      String targetRank = algebraic[2];

      for (var move in moves) {
        String moveStr = state.game.toAlgebraic(move);
        if (moveStr.length >= 4) {
          String toFile = moveStr[2];
          String toRank = moveStr[3];

          if (toFile == targetFile && toRank == targetRank) {
            // Check if this could be the right piece type
            return move;
          }
        }
      }
    }
    // Handle castling
    else if (algebraic == "O-O" || algebraic == "0-0") {
      // Look for king-side castling (e1g1 for white, e8g8 for black)
      for (var move in moves) {
        String moveStr = state.game.toAlgebraic(move);
        if (moveStr == "e1g1" || moveStr == "e8g8") {
          return move;
        }
      }
    } else if (algebraic == "O-O-O" || algebraic == "0-0-0") {
      // Look for queen-side castling
      for (var move in moves) {
        String moveStr = state.game.toAlgebraic(move);
        if (moveStr == "e1c1" || moveStr == "e8c8") {
          return move;
        }
      }
    }

    return null;
  }

  void stopSimulation() {
    _simulationTimer?.cancel();
    state = state.copyWith(simulatingPgn: false);
  }

  Future<void> makeMove(Move move) async {
    if (state.simulatingPgn) return;

    if (state.game.makeSquaresMove(move)) {
      state = state.copyWith(
        squaresState: state.game.squaresState(state.player),
      );
    }
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }
}

// Provider
final chessViewModelProvider =
    StateNotifierProvider<ChessViewModel, ChessGameState>((ref) {
      return ChessViewModel();
    });

// UI State Providers
final flipBoardProvider = StateProvider<bool>((ref) => false);
