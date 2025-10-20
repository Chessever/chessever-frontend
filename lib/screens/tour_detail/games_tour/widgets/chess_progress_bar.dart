import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessProgressBar extends ConsumerStatefulWidget {
  const ChessProgressBar({required this.gamesTourModel, super.key})
    : isReversedMode = false;

  const ChessProgressBar.reversedMode({required this.gamesTourModel, super.key})
    : isReversedMode = true;

  final GamesTourModel gamesTourModel;
  final bool isReversedMode;

  @override
  ConsumerState<ChessProgressBar> createState() => _ChessProgressBarState();
}

class _ChessProgressBarState extends ConsumerState<ChessProgressBar> {
  double oldEval = 0.5; // start at neutral midpoint

  @override
  Widget build(BuildContext context) {
    final evalAsync = ref.watch(
      cascadeEvalProvider(widget.gamesTourModel.fen ?? ''),
    );

    final evaluation = evalAsync.when(
      loading: () => oldEval,
      error: (error, stack) => oldEval,
      data: (cloud) {
        final pv = cloud.pvs.firstOrNull;
        double eval;

        // Handle mate scores
        if (pv?.cp.abs() == 100000) {
          eval = (pv?.cp ?? 0) > 0 ? 10.0 : -10.0;
        } else {
          eval = (pv?.cp ?? 0) / 100.0;
        }

        // Normalize between 0 and 1
        final normalized = (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;
        oldEval = normalized; // save for next frame
        return normalized;
      },
    );

    // Adjust for reversed mode (invert the evaluation visually)
    final displayEval = widget.isReversedMode ? (1.0 - evaluation) : evaluation;

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
              color: kBlack2Color,
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
                color: kWhiteColor,
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
