import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_move_line.dart';
import 'package:chessever2/screens/gamebase/widgets/move_statistics_panel.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Board swipe opening explorer — **desktop `NotationOpeningPanel` contract**.
///
/// Desktop (`board_pane.dart`):
/// ```
/// lineUcis = pathFromPointer(chessGame, pointer).map((m) => m.uci)
/// setPositionWithMoves(currentFen, lineUcis, startingFen: chessGame.startingFen)
/// ```
///
/// This widget only sanitises and pumps; the board call site owns the line.
class BoardOpeningExplorerPanel extends HookConsumerWidget {
  const BoardOpeningExplorerPanel({
    super.key,
    required this.currentFen,
    required this.startingFen,
    required this.lineUcis,
    required this.onMoveSelected,
  });

  factory BoardOpeningExplorerPanel.fromBoardState({
    Key? key,
    required ChessBoardStateNew state,
    required void Function(String uci) onMoveSelected,
  }) {
    final analysis = state.analysisState;
    return BoardOpeningExplorerPanel(
      key: key,
      currentFen: analysis.position.fen,
      startingFen: resolveExplorerStartingFen(analysis) ?? Chess.initial.fen,
      lineUcis: resolveExplorerMoveLine(analysis),
      onMoveSelected: onMoveSelected,
    );
  }

  final String currentFen;
  final String startingFen;
  final List<String> lineUcis;
  final void Function(String uci) onMoveSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Desktop `_OpeningExplorerPage._syncProvider` sanitise — exact same regex.
    final sanitised =
        lineUcis
            .map((m) => m.trim().toLowerCase())
            .where((m) => RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(m))
            .toList(growable: false);
    final lineKey = sanitised.join(' ');

    useEffect(() {
      Future.microtask(() {
        if (kDebugMode) {
          debugPrint(
            '[BoardOpeningExplorer] sync fen=${currentFen.split(' ').take(2).join(' ')} '
            'line=${sanitised.length} start=${startingFen.split(' ').take(2).join(' ')}',
          );
        }
        final notifier = ref.read(gamebaseExplorerProvider.notifier);
        // Unscoped board explorer: drop sticky filters without a premature fetch.
        notifier.disableLocalPlayerTree();
        if (ref.read(gamebaseExplorerProvider).hasActiveFilters) {
          notifier.clearFilters(fetch: false);
        }
        // Desktop: setPositionWithMoves(currentFen, sanitised, startingFen: …)
        notifier.setPositionWithMoves(
          currentFen,
          sanitised,
          startingFen: startingFen,
        );
      });
      return null;
    }, [currentFen, lineKey, startingFen]);

    // Board scaffold uses extendBody + a translucent bottom nav while this
    // panel is open. Pad the list so the last moves / game rows can scroll
    // fully clear of the bar (and the home indicator).
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final navHeight =
        kBottomNavigationBarHeight + (ResponsiveHelper.isTablet ? 14.0 : 0.0);
    final listBottomPadding = safeBottom + navHeight + 20;

    return MoveStatisticsPanel(
      onMove: onMoveSelected,
      listBottomPadding: listBottomPadding,
    );
  }
}
