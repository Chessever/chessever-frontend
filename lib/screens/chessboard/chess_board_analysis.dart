import 'package:chessever2/screens/chessboard/view_model/chess_viewmodel.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:flutter/material.dart';

class ChessScreen extends StatefulWidget {
  const ChessScreen({super.key});

  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen> {
  late ChessViewModel viewModel;

  @override
  void initState() {
    super.initState();
    viewModel = ChessViewModel();
    viewModel.resetGame(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chess Game')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: ChessBoardWidget(
                viewModel: viewModel,
                setState: setState,
                flipBoard: viewModel.flipBoard,
              ),
            ),
            const SizedBox(height: 16),
            if (viewModel.simulatingPgn)
              Text(
                'Simulating PGN... Move ${viewModel.currentMoveIndex}/${viewModel.pgnMoves.length}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () {
                    viewModel.resetGame();
                    setState(() {});
                  },
                  child: const Text('New Game'),
                ),
                ElevatedButton(
                  onPressed: viewModel.simulatingPgn
                      ? () => viewModel.stopSimulation(setState)
                      : () => viewModel.simulatePgnMoves(setState),
                  child: Text(
                    viewModel.simulatingPgn ? 'Stop Simulation' : 'Simulate PGN',
                  ),
                ),
                IconButton(
                  onPressed: () => viewModel.toggleBoard(setState),
                  icon: const Icon(Icons.rotate_left),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}