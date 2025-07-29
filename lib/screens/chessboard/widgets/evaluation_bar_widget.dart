import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
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
  final String fen;

  const EvaluationBarWidgetForGames({
    required this.width,
    required this.height,
    required this.fen,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var whiteHeight = ((1 - 0.5) / 2) * height;
    var blackHeight = height - whiteHeight;

    return ref
        .watch(cascadeEvalProvider(fen))
        .when(
          loading: () {
            return SkeletonWidget(
              child: _Bars(
                width: width,
                height: height,
                whiteHeight: whiteHeight,
                blackHeight: blackHeight,
              ),
            );
          },
          error:
              (_, _) => SkeletonWidget(
                child: _Bars(
                  width: width,
                  height: height,
                  whiteHeight: whiteHeight,
                  blackHeight: blackHeight,
                ),
              ),
          data: (cloud) {
            final pv = cloud.pvs.firstOrNull;
            if (pv == null) {
              return SkeletonWidget(
                child: _Bars(
                  width: width,
                  height: height,
                  whiteHeight: height * 0.5,
                  blackHeight: height * 0.5,
                ),
              );
            }

            final cpRaw = pv.cp;

            final normalized = (cpRaw.clamp(-5.0, 5.0) + 5.0) / 10.0;

            final whiteRatio = (normalized * 0.99).clamp(0.01, 0.99);

            final blackRatio = 0.99 - whiteRatio;

            return _Bars(
              width: width,
              height: height,
              blackHeight: blackRatio * height,
              whiteHeight: whiteRatio * height,
            );
          },
        );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({
    required this.width,
    required this.height,
    required this.whiteHeight,
    required this.blackHeight,
    super.key,
  });

  final double width;
  final double height;
  final double whiteHeight;
  final double blackHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: width,
              height: blackHeight,
              color: kPopUpColor,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: width,
              height: whiteHeight,
              color: kWhiteColor,
            ),
          ),
          Container(
            width: width,
            height: 2,
            color: kRedColor,
          ),
        ],
      ),
    );
  }
}
