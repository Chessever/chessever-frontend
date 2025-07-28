import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EvaluationBarWidget extends ConsumerWidget {
  final double width;
  final double height;
  final double evaluation;
  final bool isFlipped;
  final int index;

  const EvaluationBarWidget({
    required this.width,
    required this.height,
    required this.evaluation,
    required this.isFlipped,
    required this.index,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height:
                  height *
                  (isFlipped
                      ? ref
                          .read(chessBoardScreenProvider(index).notifier)
                          .getWhiteRatio(evaluation)
                      : ref
                          .read(chessBoardScreenProvider(index).notifier)
                          .getBlackRatio(evaluation)),
              color: isFlipped ? kWhiteColor : kPopUpColor,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height:
                  height *
                  (isFlipped
                      ? ref
                          .read(chessBoardScreenProvider(index).notifier)
                          .getBlackRatio(evaluation)
                      : ref
                          .read(chessBoardScreenProvider(index).notifier)
                          .getWhiteRatio(evaluation)),
              color: isFlipped ? kPopUpColor : kWhiteColor,
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(height: 4.h, color: kRedColor),
          ),
        ],
      ),
    );
  }
}

class EvaluationBarWidgetForGames extends ConsumerWidget {
  final double width;
  final double height;
  final String fen; // FEN is the only thing we need

  const EvaluationBarWidgetForGames({
    required this.width,
    required this.height,
    required this.fen,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evalAsync = ref.watch(cascadeEvalProvider(fen));

    final evaluation = evalAsync.when(
      loading: () => 0.0,
      error: (_, __) => 0.0,
      data: (cloud) {
        final pv = cloud.pvs.firstOrNull;
        print(pv?.cp ?? 0);
        return pv == null ? 0.0 : (pv.cp * 10 / 100).clamp(-10, 10) / 10;
      },
    );

    // Split point between -1 and 1 mapped to 0..height
    final whiteHeight = ((1 - evaluation) / 2) * height;
    final blackHeight = height - whiteHeight;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // White side (top)
          Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: width,
              height: whiteHeight,
              color: kPopUpColor,
            ),
          ),
          // Black side (bottom)
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: width,
              height: blackHeight,
              color: kPopUpColor,
            ),
          ),
          // Middle marker
          Align(
            alignment: Alignment.center,
            child: Container(
              width: width,
              height: 4,
              color: kRedColor,
            ),
          ),
        ],
      ),
    );
  }
}
