import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

class EvaluationBar extends StatelessWidget {
  final double width;
  final double height;
  final int index;
  final ChessBoardState state;
  final ChessBoardScreenNotifier notifier;
  final bool isFlipped;

  const EvaluationBar({
    required this.width,
    required this.height,
    required this.index,
    required this.state,
    required this.notifier,
    required this.isFlipped,
  });

  @override
  Widget build(BuildContext context) {
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
                      ? notifier.getWhiteRatio(state.evaluations[index])
                      : notifier.getBlackRatio(state.evaluations[index])),
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
                      ? notifier.getBlackRatio(state.evaluations[index])
                      : notifier.getWhiteRatio(state.evaluations[index])),
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
