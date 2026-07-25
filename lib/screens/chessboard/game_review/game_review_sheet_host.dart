import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_sheet.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Screen-scoped wiring for the non-modal Game Analysis sheet.
///
/// The sheet is rendered by [GameReviewSheetHost] as a sibling of the board
/// `PageView` — never inside a page — so a horizontal swipe between games does
/// not drag the report sideways, and no modal barrier is installed over the
/// board.
///
/// Two values travel through here:
/// * [target] — which board page (if any) currently has the sheet open.
/// * [anchorPixels] — how tall the sheet must be for its top edge to land just
///   under the board's bottom player row. Published by [GameReviewBoardAnchor]
///   from the real laid-out row, so the first snap step is measured rather than
///   guessed on every device.
class GameReviewSheetScope extends InheritedWidget {
  const GameReviewSheetScope({
    super.key,
    required this.target,
    required this.anchorPixels,
    required super.child,
  });

  final ValueNotifier<ChessBoardProviderParams?> target;
  final ValueNotifier<double?> anchorPixels;

  static GameReviewSheetScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameReviewSheetScope>();

  @override
  bool updateShouldNotify(GameReviewSheetScope oldWidget) =>
      oldWidget.target != target || oldWidget.anchorPixels != anchorPixels;
}

/// Measures [child] (the board's bottom player row) and publishes the sheet
/// height that would stop right underneath it.
///
/// Reports a **distance from the bottom of the window** rather than a raw
/// global offset: the board screen's `Scaffold` body is bottom-flush with the
/// window, so that distance is exactly the peek height the sheet needs.
class GameReviewBoardAnchor extends StatefulWidget {
  const GameReviewBoardAnchor({
    super.key,
    required this.enabled,
    required this.child,
  });

  /// Only the visible page should publish; off-screen `PageView` neighbours
  /// measure to the same coordinates and would fight over the value.
  final bool enabled;
  final Widget child;

  @override
  State<GameReviewBoardAnchor> createState() => _GameReviewBoardAnchorState();
}

class _GameReviewBoardAnchorState extends State<GameReviewBoardAnchor> {
  bool _measureScheduled = false;
  ValueNotifier<double?>? _anchorPixels;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolved here, not in the post-frame callback: inherited lookups belong
    // in build/didChangeDependencies, and the scope never changes anyway.
    _anchorPixels = GameReviewSheetScope.maybeOf(context)?.anchorPixels;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enabled && _anchorPixels != null) _scheduleMeasure();
    return widget.child;
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      final notifier = _anchorPixels;
      if (!mounted || !widget.enabled || notifier == null) return;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final rowBottom =
          renderObject.localToGlobal(Offset(0, renderObject.size.height)).dy;
      final windowHeight = MediaQuery.sizeOf(context).height;
      final peek = windowHeight - rowBottom - GameReviewSheetExtents.anchorGap;
      if (peek <= 0 || !peek.isFinite) return;
      final previous = notifier.value;
      // Sub-pixel churn would rebuild the sheet (and re-snap it) every frame.
      if (previous != null && (previous - peek).abs() < 0.5) return;
      notifier.value = peek;
    });
  }
}

/// Renders the open Game Analysis sheet above the board.
///
/// Returns a zero-size child when nothing is open, so a closed sheet costs no
/// layout and swallows no taps. While open, only the sheet's own rectangle is
/// hit-testable — the board above it stays fully interactive.
class GameReviewSheetHost extends StatelessWidget {
  const GameReviewSheetHost({
    super.key,
    required this.target,
    required this.anchorPixels,
    required this.currentGameId,
  });

  final ValueNotifier<ChessBoardProviderParams?> target;
  final ValueNotifier<double?> anchorPixels;

  /// Game the board is showing right now. The report belongs to one game, so
  /// swiping to another closes the sheet instead of showing a stale report.
  final String? currentGameId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChessBoardProviderParams?>(
      valueListenable: target,
      builder: (context, params, _) {
        if (params == null) return const SizedBox.shrink();
        if (currentGameId != null && params.game.gameId != currentGameId) {
          // Page moved on: close after this frame rather than mid-build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (target.value == params) target.value = null;
          });
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: ValueListenableBuilder<double?>(
            valueListenable: anchorPixels,
            builder: (context, peekPixels, _) {
              return _GameReviewSheetBinding(
                params: params,
                peekPixels: peekPixels,
                onClose: () => target.value = null,
              );
            },
          ),
        );
      },
    );
  }
}

/// Binds the sheet to the board page's providers: reads the live ply out of the
/// board and writes navigation back into it.
class _GameReviewSheetBinding extends ConsumerWidget {
  const _GameReviewSheetBinding({
    required this.params,
    required this.peekPixels,
    required this.onClose,
  });

  final ChessBoardProviderParams params;
  final double? peekPixels;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `select` down to a single int: the board publishes evaluation, clocks and
    // engine lines constantly, and none of that should rebuild the sheet.
    final activePly = ref.watch(
      chessBoardScreenProviderNew(params).select(gameReviewActivePly),
    );
    final reviewController = ref.watch(
      mobileGameReviewProvider(params).notifier,
    );
    return GameReviewSheet(
      controller: reviewController,
      game: params.game,
      activePly: activePly,
      peekPixels: peekPixels,
      onJumpToPly: (ply) {
        ref
            .read(chessBoardScreenProviderNew(params).notifier)
            .goToMovePointer(ply <= 0 ? const <Number>[] : <Number>[ply - 1]);
      },
      onClose: () {
        // Board eval was left running while the report was on screen; force a
        // refresh now that the sheet no longer owns the view.
        ref
            .read(chessBoardScreenProviderNew(params).notifier)
            .setGameReviewVisible(false);
        onClose();
      },
    );
  }
}

/// Report ply for the position the board is on.
///
/// Ply 0 is the starting position and ply *n* is the position after mainline
/// move *n*, matching [GameAnalysisReport.positions] and the pointer form
/// `[ply - 1]` used to navigate back. Returns `-1` inside an analysis variation,
/// which the report has no positions for — the sheet then holds its marker
/// instead of snapping it somewhere misleading.
int gameReviewActivePly(AsyncValue<ChessBoardStateNew> async) {
  final state = async.valueOrNull;
  if (state == null) return -1;
  if (!state.isAnalysisMode) return state.currentMoveIndex + 1;
  final analysis = state.analysisState;
  if (analysis.isInAnalysisVariation) return -1;
  return analysis.currentMoveIndex + 1;
}
