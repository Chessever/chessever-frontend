import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
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
  final double evaluation;

  const EvaluationBarWidgetForGames({
    required this.width,
    required this.height,
    required this.evaluation,
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
              height: height / 2,
              color: kPopUpColor,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: height / 2,
              color: kPopUpColor,
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
