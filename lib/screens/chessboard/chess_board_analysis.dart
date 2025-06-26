import 'package:chessever2/screens/chessboard/view_model/chess_viewmodel.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessScreen extends HookConsumerWidget {
  const ChessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewModel = useMemoized(() => ChessViewModel());
    final forceRebuild = useState(0); // Keep for forcing rebuilds
    final flipBoard = useState(false);

    // Create a proper update callback
    void updateUI() {
      forceRebuild.value = forceRebuild.value + 1;
    }

    useEffect(() {
      viewModel.resetGame();
      return () {
        // Cleanup timer when widget is disposed
        viewModel.stopSimulation();
      };
    }, []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Game'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Settings navigation
            },
          ),
        ],
      ),
      body: Consumer(
        builder: (context, ref, child) {
          final boardSettingsValue = ref.watch(boardSettingsProvider);

          if (boardSettingsValue == null) {
            return const Center(child: CircularProgressIndicator());
          } else {
            final settings = boardSettingsValue as BoardSettings;
            final boardColorEnum = ref
                .read(boardSettingsRepository)
                .getBoardColorEnum(settings.boardColor);
            return _buildChessBoard(
              context,
              viewModel,
              updateUI,
              flipBoard,
              boardColorEnum,
              settings,
            );
          }
        },
      ),
    );
  }

  Widget _buildChessBoard(
    BuildContext context,
    ChessViewModel viewModel,
    VoidCallback updateUI,
    ValueNotifier<bool> flipBoard,
    BoardColor boardColor,
    BoardSettings settings,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ChessBoardWidget(
                  viewModel: viewModel,
                  setState: updateUI, // Pass the callback directly
                  flipBoard: flipBoard.value,
                  boardColor: boardColor,
                  pieceStyle: settings.pieceStyle.toString(),
                ),
              ),
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
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _buildActionButton(
                context,
                icon: Icons.refresh,
                label: 'New Game',
                onPressed: () {
                  viewModel.resetGame();
                  updateUI();
                },
              ),
              _buildActionButton(
                context,
                icon: viewModel.simulatingPgn ? Icons.stop : Icons.play_arrow,
                label: viewModel.simulatingPgn ? 'Stop' : 'Simulate',
                onPressed: viewModel.simulatingPgn
                    ? () {
                        viewModel.stopSimulation();
                        updateUI();
                      }
                    : () async {
                        await viewModel.simulatePgnMoves(
                          notifyUpdate: updateUI, // Pass the callback
                        );
                        updateUI();
                      },
              ),
              _buildActionButton(
                context,
                icon: Icons.rotate_left,
                label: 'Flip Board',
                onPressed: () {
                  flipBoard.value = !flipBoard.value;
                  updateUI();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Theme: ${boardColor.toString().split('.').last}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 120,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
        onPressed: onPressed,
      ),
    );
  }
}