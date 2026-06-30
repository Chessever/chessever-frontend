import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int _mateCpSentinel = 100_000;

@visibleForTesting
double normalizePvToProgressValue(Pv? pv) {
  if (pv == null) return 0.5;

  final sign = pv.whitePerspective ? 1 : -1;
  final eval =
      pv.cp.abs() == _mateCpSentinel
          ? ((pv.cp * sign) > 0 ? 10.0 : -10.0)
          : ((pv.cp * sign) / 100.0);

  return (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;
}

class ChessProgressBar extends ConsumerStatefulWidget {
  const ChessProgressBar({
    required this.gamesTourModel,
    this.allowStockfishFallback = true,
    super.key,
  }) : isReversedMode = false;

  const ChessProgressBar.reversedMode({
    required this.gamesTourModel,
    this.allowStockfishFallback = true,
    super.key,
  }) : isReversedMode = true;

  final GamesTourModel gamesTourModel;
  final bool isReversedMode;
  final bool allowStockfishFallback;

  @override
  ConsumerState<ChessProgressBar> createState() => _ChessProgressBarState();
}

class _ChessProgressBarState extends ConsumerState<ChessProgressBar> {
  double oldEval = 0.5; // start at neutral midpoint

  @override
  Widget build(BuildContext context) {
    // Chess progress bar only needs 1 PV for evaluation.
    // Use the game-card cascade so card surfaces hit local/Gamebase first and
    // only fall back to low-priority Stockfish when allowed.
    final fen = widget.gamesTourModel.fen ?? '';
    final evalAsync =
        widget.allowStockfishFallback
            ? ref.watch(gameCardEvalWithStockfishFallbackProvider(fen))
            : ref.watch(gameCardEvalCacheOnlyProvider(fen));

    final evaluation = evalAsync.when(
      loading: () => oldEval,
      error: (error, stack) => oldEval,
      data: (cloud) {
        final pv = cloud.pvs.firstOrNull;
        final normalized = normalizePvToProgressValue(pv);
        oldEval = normalized; // save for next frame
        return normalized;
      },
    );

    // Adjust for reversed mode (invert the evaluation visually)
    final displayEval = widget.isReversedMode ? (1.0 - evaluation) : evaluation;

    // The bar's two halves are *piece colours*, not theme colours: the
    // foreground = white side's share, background = black side's share.
    // Dark theme used `surface`/`textPrimary` because both happen to be
    // black/white-shaped in dark mode, but in light mode that flips and
    // shows white advantage as a dark pixel block. Force literal piece
    // colours in light theme; dark theme keeps the original tokens so its
    // appearance is unchanged.
    final barBg =
        context.isLightTheme ? kMoveStatBlackColor : context.colors.surface;
    final barFg =
        context.isLightTheme ? kMoveStatWhiteColor : context.colors.textPrimary;

    return SizedBox(
      width: 48.w,
      height: 12.h,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background
          Container(
            width: 48.w,
            height: 12.h,
            decoration: BoxDecoration(
              color: barBg,
              borderRadius: BorderRadius.circular(4.br),
            ),
          ),

          // Foreground progress (white advantage)
          Align(
            alignment:
                widget.isReversedMode
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: (48.w * displayEval).clamp(0.0, 48.w),
              height: 12.h,
              decoration: BoxDecoration(
                color: barFg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(
                    widget.isReversedMode && displayEval < 0.99 ? 0 : 4.br,
                  ),
                  bottomLeft: Radius.circular(
                    widget.isReversedMode && displayEval < 0.99 ? 0 : 4.br,
                  ),
                  topRight: Radius.circular(
                    !widget.isReversedMode && displayEval < 0.99 ? 0 : 4.br,
                  ),
                  bottomRight: Radius.circular(
                    !widget.isReversedMode && displayEval < 0.99 ? 0 : 4.br,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
