// import 'dart:math';
// import 'package:bishop/bishop.dart' as bishop;
// import 'package:square_bishop/square_bishop.dart';
// import 'package:squares/squares.dart';

// class ChessViewModel {
//   late bishop.Game game;
//   late SquaresState state;
//   int player = Squares.white;
//   bool aiThinking = false;
//   bool flipBoard = false;
//   bool simulatingPgn = false;
//   int currentMoveIndex = 0;
//   late List<String> pgnMoves;

//   void resetGame([bool notify = true]) {
//     const samplePgn = '''
//   [Event "Example Game"]
//   [Site "?"]
//   [Date "2024.06.25"]
//   [Round "?"]
//   [White "White"]
//   [Black "Black"]
//   [Result "*"]

//   1. e4 f5 2. Nh3 Nc6 3. Bb5 a6 b7
//   ''';

//     game = bishop.Game.fromPgn(samplePgn);
//     _extractPgnMoves(samplePgn);
//     state = game.squaresState(player);
//     currentMoveIndex = 0;
//     simulatingPgn = false;
//   }

//   void _extractPgnMoves(String pgn) {
//     String movesSection = pgn.replaceAll(RegExp(r'\[.*?\]'), '');
//     movesSection = movesSection.replaceAll(RegExp(r'\{.*?\}'), '');

//     final movePattern = RegExp(
//       r'\b([KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?|O-O(?:-O)?)[+#]?\b',
//     );

//     pgnMoves =
//         movePattern
//             .allMatches(movesSection)
//             .map((m) => m.group(1))
//             .where((move) => move != null && move != '*' && !move.contains('.'))
//             .cast<String>()
//             .toList();
//   }

//   Future<void> simulatePgnMoves(Function(void Function()) setState) async {
//     if (simulatingPgn) return;

//     setState(() {
//       simulatingPgn = true;
//       currentMoveIndex = 0;
//     });

//     resetGame(false);

//     for (int i = 0; i < pgnMoves.length; i++) {
//       if (!simulatingPgn) break;

//       try {
//         final legalMoves = game.generateLegalMoves();
//         bishop.Move? targetMove;

//         for (final move in legalMoves) {
//           if (game.toAlgebraic(move) == pgnMoves[i]) {
//             targetMove = move;
//             break;
//           }
//         }

//         if (targetMove != null) {
//           bool success = game.makeMove(targetMove);
//           if (success) {
//             setState(() {
//               state = game.squaresState(player);
//               currentMoveIndex = i + 1;
//             });

//             await Future.delayed(const Duration(milliseconds: 500));
//           } else {
//             break;
//           }
//         } else {
//           break;
//         }
//       } catch (e) {
//         break;
//       }
//     }

//     setState(() => simulatingPgn = false);
//   }

//   void stopSimulation(Function(void Function()) setState) {
//     setState(() => simulatingPgn = false);
//   }

//   void toggleBoard(Function(void Function()) setState) {
//     setState(() => flipBoard = !flipBoard);
//   }

//   Future<void> makeMove(Move move, Function(void Function()) setState) async {
//     if (simulatingPgn) return;

//     bool result = game.makeSquaresMove(move);
//     if (result) {
//       setState(() => state = game.squaresState(player));
//     }
//     if (state.state == PlayState.theirTurn && !aiThinking) {
//       setState(() => aiThinking = true);
//       await Future.delayed(
//         Duration(milliseconds: Random().nextInt(4750) + 250),
//       );
//       game.makeRandomMove();
//       setState(() {
//         aiThinking = false;
//         state = game.squaresState(player);
//       });
//     }
//   }
// }

import 'dart:async';
import 'dart:convert';
import 'package:bishop/bishop.dart' as bishop;
import 'package:flutter/services.dart';
import 'package:square_bishop/square_bishop.dart';
import 'package:squares/squares.dart';

class ChessViewModel {
  late bishop.Game game;
  late SquaresState state;
  int player = Squares.white;
  bool simulatingPgn = false;
  int currentMoveIndex = 0;
  List<String> pgnMoves = [];
  Timer? _simulationTimer;

  ChessViewModel() {
    resetGame();
    _loadMockMoves();
  }

  Future<void> _loadMockMoves() async {
    try {
      final jsonString = await rootBundle.loadString(
        'lib/screens/chessboard/utils/moves.json',
      );
      final jsonData = jsonDecode(jsonString);
      pgnMoves = List<String>.from(jsonData['pgnMoves']);
      print('Successfully loaded ${pgnMoves.length} moves from JSON');
    } catch (e) {
      print('Error loading mock moves: $e');
      pgnMoves = [
        "e4",
        "e5",
        "Nf3",
        "Nc6",
        "Bb5",
        "a6",
        "Ba4",
        "Nf6",
        "O-O",
        "Be7",
        "Re1",
        "b5",
        "Bb3",
        "d6",
        "c3",
        "O-O",
        "h3",
        "Nb8",
        "d4",
        "Nbd7",
      ];
      print('Using default moves instead');
    }
  }

  void resetGame([List<String>? moves]) {
    game = bishop.Game();
    state = game.squaresState(player);
    currentMoveIndex = 0;
    simulatingPgn = false;
    if (moves != null) pgnMoves = moves;
    _simulationTimer?.cancel();
  }

  Future<void> simulatePgnMoves({
    required void Function() notifyUpdate, // Changed parameter
    Duration moveDelay = const Duration(
      milliseconds: 1000,
    ), // Slower for visibility
  }) async {
    if (simulatingPgn || pgnMoves.isEmpty) {
      print(
        'Simulation not started: ${simulatingPgn ? "Already simulating" : "No moves"}',
      );
      return;
    }

    simulatingPgn = true;
    currentMoveIndex = 0;

    // Reset the game but keep the current moves
    game = bishop.Game();
    state = game.squaresState(player);
    notifyUpdate(); // Notify UI immediately

    _simulationTimer = Timer.periodic(moveDelay, (timer) {
      if (currentMoveIndex >= pgnMoves.length || !simulatingPgn) {
        timer.cancel();
        simulatingPgn = false;
        notifyUpdate();
        print('Simulation completed or stopped');
        return;
      }

      final currentMove = pgnMoves[currentMoveIndex];
      print('Attempting move ${currentMoveIndex + 1}: $currentMove');

      try {
        final move = _findMove(currentMove);
        if (move != null) {
          print('Found move: ${game.toAlgebraic(move)}');
          bool success = game.makeMove(move);
          if (success) {
            print('Move successful');
            // Update state immediately
            state = game.squaresState(player);
            currentMoveIndex++;
            notifyUpdate(); // Notify UI of update
          } else {
            print('Move failed to execute');
            timer.cancel();
            simulatingPgn = false;
            notifyUpdate();
          }
        } else {
          print('Could not find matching move for: $currentMove');
          print(
            'Available moves: ${game.generateLegalMoves().map((m) => game.toAlgebraic(m)).toList()}',
          );
          timer.cancel();
          simulatingPgn = false;
          notifyUpdate();
        }
      } catch (e) {
        print('Error during move execution: $e');
        timer.cancel();
        simulatingPgn = false;
        notifyUpdate();
      }
    });
  }

  bishop.Move? _findMove(String algebraic) {
    try {
      var moves = game.generateLegalMoves();

      print('Looking for move: "$algebraic"');

      // First try using the bishop library's built-in parsing
      try {
        var parsedMove = game.getMove(algebraic);
        if (parsedMove != null && moves.contains(parsedMove)) {
          print('Found via bishop parsing: ${game.toAlgebraic(parsedMove)}');
          return parsedMove;
        }
      } catch (e) {
        print('Bishop parsing failed: $e');
      }

      // The library returns coordinate notation, so we need to convert
      // Standard algebraic to coordinate notation mapping
      bishop.Move? foundMove = _convertAlgebraicToCoordinate(algebraic, moves);
      if (foundMove != null) {
        print(
          'Found via coordinate conversion: ${game.toAlgebraic(foundMove)}',
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
        String moveStr = game.toAlgebraic(move);
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
        String moveStr = game.toAlgebraic(move);
        if (moveStr.length >= 4) {
          String toFile = moveStr[2];
          String toRank = moveStr[3];

          if (toFile == targetFile && toRank == targetRank) {
            // Check if this could be the right piece type
            // This is a simple heuristic - you might need to refine this
            return move;
          }
        }
      }
    }
    // Handle castling
    else if (algebraic == "O-O" || algebraic == "0-0") {
      // Look for king-side castling (e1g1 for white, e8g8 for black)
      for (var move in moves) {
        String moveStr = game.toAlgebraic(move);
        if (moveStr == "e1g1" || moveStr == "e8g8") {
          return move;
        }
      }
    } else if (algebraic == "O-O-O" || algebraic == "0-0-0") {
      // Look for queen-side castling
      for (var move in moves) {
        String moveStr = game.toAlgebraic(move);
        if (moveStr == "e1c1" || moveStr == "e8c8") {
          return move;
        }
      }
    }

    return null;
  }

  void stopSimulation() {
    _simulationTimer?.cancel();
    simulatingPgn = false;
  }

  Future<void> makeMove(Move move, void Function() notifyUpdate) async {
    if (simulatingPgn) return;

    if (game.makeSquaresMove(move)) {
      state = game.squaresState(player);
      notifyUpdate();
    }
  }
}
