// lib/views/in_game_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:chess/chess.dart' as chess_logic;
import '../models/game.dart';

class InGameView extends StatefulWidget {
  final BroadcastGame game; // Receive selected game

  const InGameView({super.key, required this.game});

  @override
  State<InGameView> createState() => _InGameViewState();
}

class _InGameViewState extends State<InGameView> {
  ChessBoardController controller = ChessBoardController();
  late chess_logic.Chess _chessGame;

  @override
  void initState() {
    super.initState();
    _chessGame = chess_logic.Chess(); // Start with a default board

    // Try to load the game state from the passed Game object's moves
    // The 'chess' package can load Standard Algebraic Notation (SAN)
    try {
      // Split moves and apply them one by one
      // final movesList = widget.game.moves.split(' ');
      final movesList = []; // todo
      for (final moveSan in movesList) {
        if (moveSan.trim().isNotEmpty) {
           // The chess package's move method takes SAN
           _chessGame.move(moveSan);
        }
      }
      // Load the final position into the board controller
      controller.loadFen(_chessGame.fen);
    } catch (e) {
       print("Error loading game moves into chess engine: $e");
       // If loading fails, the board remains in the initial state
       // Optionally show an error message to the user
       WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not load game history.')),
             );
          }
       });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.game.players[0]), // todo
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ChessBoard(
            controller: controller,
            boardColor: BoardColor.brown,
            boardOrientation: PlayerColor.white,
            // Disable board interaction for now, as we are just viewing
            enableUserMoves: false,
          ),
        ),
      ),
    );
  }
}