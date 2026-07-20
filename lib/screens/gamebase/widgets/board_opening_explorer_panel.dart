import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_move_line.dart';
import 'package:chessever2/screens/gamebase/widgets/move_statistics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opening explorer panel for the chess board screen's swipeable bottom area.
///
/// Mirrors the bottom-panel page 0 of the standalone gamebase explorer
/// screen (`MoveStatisticsPanel` — the table with figurine moves, win/draw/
/// loss bar, game count, list-icon → games bottom sheet, last-played date)
/// so the two contexts stay visually identical.
///
/// The wrapper is responsible for pumping the chess board's current FEN +
/// playline into `gamebaseExplorerProvider` so the table reflects the user's
/// position, and for routing taps back into the chess board's analysis state
/// instead of advancing the explorer's standalone exploration cursor.
class BoardOpeningExplorerPanel extends HookConsumerWidget {
  const BoardOpeningExplorerPanel({
    super.key,
    required this.state,
    required this.onMoveSelected,
  });

  final ChessBoardStateNew state;
  final void Function(String uci) onMoveSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisState = state.analysisState;
    final currentPosition = analysisState.position;
    final currentFen = currentPosition.fen;
    final startingFen = resolveExplorerStartingFen(analysisState);
    final lineToCurrent = resolveExplorerMoveLine(analysisState);
    final lineKey = lineToCurrent.join(' ');

    useEffect(() {
      Future.microtask(() {
        ref
            .read(gamebaseExplorerProvider.notifier)
            .setPositionWithMoves(
              currentFen,
              lineToCurrent,
              startingFen: startingFen,
            );
      });
      return null;
    }, [currentFen, lineKey, startingFen]);

    return MoveStatisticsPanel(onMove: onMoveSelected);
  }
}
