import 'dart:math';
import 'package:bishop/bishop.dart' as bishop;
import 'package:square_bishop/square_bishop.dart';
import 'package:squares/squares.dart';

class ChessViewModel {
  late bishop.Game game;
  late SquaresState state;
  int player = Squares.white;
  bool aiThinking = false;
  bool flipBoard = false;
  bool simulatingPgn = false;
  int currentMoveIndex = 0;
  late List<String> pgnMoves;

  void resetGame([bool notify = true]) {
    const samplePgn = '''
  [Event "Example Game"]
  [Site "?"]
  [Date "2024.06.25"]
  [Round "?"]
  [White "White"]
  [Black "Black"]
  [Result "*"]

  1. e4 f5 2. Nh3 Nc6 3. Bb5 a6 b7 
  ''';

    game = bishop.Game.fromPgn(samplePgn);
    _extractPgnMoves(samplePgn);
    state = game.squaresState(player);
    currentMoveIndex = 0;
    simulatingPgn = false;
  }

  void _extractPgnMoves(String pgn) {
    String movesSection = pgn.replaceAll(RegExp(r'\[.*?\]'), '');
    movesSection = movesSection.replaceAll(RegExp(r'\{.*?\}'), '');

    final movePattern = RegExp(
      r'\b([KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?|O-O(?:-O)?)[+#]?\b',
    );

    pgnMoves =
        movePattern
            .allMatches(movesSection)
            .map((m) => m.group(1))
            .where((move) => move != null && move != '*' && !move.contains('.'))
            .cast<String>()
            .toList();
  }

  Future<void> simulatePgnMoves(Function(void Function()) setState) async {
    if (simulatingPgn) return;

    setState(() {
      simulatingPgn = true;
      currentMoveIndex = 0;
    });

    resetGame(false);

    for (int i = 0; i < pgnMoves.length; i++) {
      if (!simulatingPgn) break;

      try {
        final legalMoves = game.generateLegalMoves();
        bishop.Move? targetMove;

        for (final move in legalMoves) {
          if (game.toAlgebraic(move) == pgnMoves[i]) {
            targetMove = move;
            break;
          }
        }

        if (targetMove != null) {
          bool success = game.makeMove(targetMove);
          if (success) {
            setState(() {
              state = game.squaresState(player);
              currentMoveIndex = i + 1;
            });

            await Future.delayed(const Duration(milliseconds: 500));
          } else {
            break;
          }
        } else {
          break;
        }
      } catch (e) {
        break;
      }
    }

    setState(() => simulatingPgn = false);
  }

  void stopSimulation(Function(void Function()) setState) {
    setState(() => simulatingPgn = false);
  }

  void toggleBoard(Function(void Function()) setState) {
    setState(() => flipBoard = !flipBoard);
  }

  Future<void> makeMove(Move move, Function(void Function()) setState) async {
    if (simulatingPgn) return;

    bool result = game.makeSquaresMove(move);
    if (result) {
      setState(() => state = game.squaresState(player));
    }
    if (state.state == PlayState.theirTurn && !aiThinking) {
      setState(() => aiThinking = true);
      await Future.delayed(
        Duration(milliseconds: Random().nextInt(4750) + 250),
      );
      game.makeRandomMove();
      setState(() {
        aiThinking = false;
        state = game.squaresState(player);
      });
    }
  }
}
