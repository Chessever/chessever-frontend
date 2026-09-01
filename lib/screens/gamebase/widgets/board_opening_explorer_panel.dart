import 'package:chessever2/screens/chessboard/game_review/game_review_sheet.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_sheet_host.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart'
    show showExplorerFilterSheet;
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
    final sanitised = lineUcis
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
        // The board uses the same filter scope and sheet as the standalone
        // explorer. Keep filters when the position changes so every filter/sort
        // combination remains active while the user plays through the line.
        notifier.disableLocalPlayerTree();
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

    // Inline game cards page one at a time, each landing whole against this
    // panel's top edge — the edge right under the board's bottom player row.
    // That page height is the row's already-measured distance to the bottom of
    // the window (the same anchor the Game Analysis sheet stops at), because
    // once the games strip pins, the engine lines and the move-table header
    // above it have collapsed away. Tablet landscape puts the panel beside the
    // board instead of under it, so the anchor means nothing there.
    final pagesGames =
        !(ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape);
    final anchorPixels = GameReviewSheetScope.maybeOf(context)?.anchorPixels;
    final hasActiveFilters = ref.watch(
      gamebaseExplorerProvider.select((state) => state.hasActiveFilters),
    );
    void openFilters() => showExplorerFilterSheet(context);

    if (!pagesGames || anchorPixels == null) {
      return MoveStatisticsPanel(
        onMove: onMoveSelected,
        onFilter: openFilters,
        hasActiveFilters: hasActiveFilters,
        listBottomPadding: listBottomPadding,
      );
    }

    return ValueListenableBuilder<double?>(
      valueListenable: anchorPixels,
      builder: (context, anchor, _) {
        return MoveStatisticsPanel(
          onMove: onMoveSelected,
          onFilter: openFilters,
          hasActiveFilters: hasActiveFilters,
          listBottomPadding: listBottomPadding,
          gamesPageHeight:
              anchor == null ? null : anchor + GameReviewSheetExtents.anchorGap,
        );
      },
    );
  }
}
