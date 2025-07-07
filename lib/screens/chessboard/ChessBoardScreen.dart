import 'package:chessever2/screens/chessboard/view_model/chess_viewmodel.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_appbar.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/player_info_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart'; // Add this import

class ChessScreen extends ConsumerWidget {
  const ChessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chessState = ref.watch(chessViewModelProvider);
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardColorEnum = ref
        .read(boardSettingsRepository)
        .getBoardColorEnum(boardSettingsValue.boardColor);

    return Scaffold(
      appBar: ChessMatchAppBar(
        title: 'Magnus vs Nakamura',
        onBackPressed: () {
          Navigator.pop(context);
        },
        onSettingsPressed: () {
          // Handle settings button press
        },
        onMoreOptionsPressed: () {
          // Handle share button press
        },
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Player information - Top (Black)
              PlayerInfoWidget(
                name: 'GM Nakamura, Hikaru',
                rating: '2804',
                time: '01:04:11',
                isTop: true,
              ),

              const SizedBox(height: 8),

              // Chess board
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                  // child: ChessBoardWidget(boardColor: boardColorEnum),
                ),
              ),

              const SizedBox(height: 8),

              // Player information - Bottom (White)
              PlayerInfoWidget(
                name: 'GM Carlsen, Magnus',
                rating: '2837',
                time: '00:45:36',
                isTop: false,
              ),

              const SizedBox(height: 16),

              // Moves section
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Moves display
                    _buildMovesText(context, chessState),
                  ],
                ),
              ),

              // Add bottom padding to ensure content doesn't get hidden behind bottom buttons
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const ChessBoardBottomNavBar(),
    );
  }

  Widget _buildMovesText(BuildContext context, ChessGameState chessState) {
    if (chessState.pgnMoves.isEmpty) {
      return Text(
        'No moves loaded',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        ),
        textAlign: TextAlign.center,
      );
    }

    final moves = chessState.pgnMoves;
    final currentMoveIndex = chessState.currentMoveIndex;

    List<InlineSpan> spans = [];

    for (int i = 0; i < moves.length; i += 2) {
      final moveNumber = (i ~/ 2) + 1;
      final whiteMove = moves[i];
      final blackMove = i + 1 < moves.length ? moves[i + 1] : null;

      // Move number
      spans.add(
        TextSpan(
          text: '$moveNumber. ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      );

      // White move
      spans.add(
        TextSpan(
          text: '$whiteMove ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color:
                i < currentMoveIndex
                    ? Theme.of(context).colorScheme.primary
                    : (i == currentMoveIndex
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface),
            fontWeight:
                i == currentMoveIndex ? FontWeight.bold : FontWeight.normal,
            backgroundColor:
                i == currentMoveIndex
                    ? Theme.of(
                      context,
                    ).colorScheme.errorContainer.withOpacity(0.3)
                    : null,
          ),
        ),
      );

      // Black move (if exists)
      if (blackMove != null) {
        spans.add(
          TextSpan(
            text: '$blackMove ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color:
                  i + 1 < currentMoveIndex
                      ? Theme.of(context).colorScheme.primary
                      : (i + 1 == currentMoveIndex
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurface),
              fontWeight:
                  i + 1 == currentMoveIndex
                      ? FontWeight.bold
                      : FontWeight.normal,
              backgroundColor:
                  i + 1 == currentMoveIndex
                      ? Theme.of(
                        context,
                      ).colorScheme.errorContainer.withOpacity(0.3)
                      : null,
            ),
          ),
        );
      }

      // Add new line after every 4 move pairs for better readability
      if (i > 0 && (i ~/ 2) % 4 == 0) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return RichText(text: TextSpan(children: spans), textAlign: TextAlign.left);
  }
}
