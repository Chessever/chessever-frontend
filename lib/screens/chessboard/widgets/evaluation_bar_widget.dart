import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
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
          // Evaluation number display
          Align(
            alignment: Alignment.center,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 1.w, vertical: 0.5.h),
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2.br),
              ),
              child: Text(
                evaluation.abs() >= 10.0
                    ? (evaluation > 0 ? "M" : "-M") // Show "M" or "-M" for mate
                    : evaluation
                        .toString()
                        .characters
                        .take(4)
                        .string, // Show negative values directly
                maxLines: 1,
                textAlign: TextAlign.center,
                style: AppTypography.textSmRegular.copyWith(
                  color: Colors.white,
                  fontSize: 3.5.f,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
    return ref
        .watch(cascadeEvalProvider(fen))
        .when(
          loading: () {
            return SkeletonWidget(
              child: _Bars(
                width: width,
                height: height,
                whiteHeight: height * 0.5,
                blackHeight: height * 0.5,
                evaluation: 0.0,
              ),
            );
          },
          error:
              (_, _) => SkeletonWidget(
                child: _Bars(
                  width: width,
                  height: height,
                  whiteHeight: height * 0.5,
                  blackHeight: height * 0.5,
                  evaluation: 0.0,
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
                  evaluation: 0.0,
                ),
              );
            }

            // Handle evaluation based on cp value
            double evaluation;
            if (pv.cp.abs() == 100000) {
              // This is a mate score (converted from mate in X moves)
              evaluation = pv.cp > 0 ? 10.0 : -10.0;
            } else {
              // Normal centipawn score - convert to pawn units
              evaluation = pv.cp / 100.0;
            }

            // Calculate ratios (fixed to sum to 1.0)
            final normalized = (evaluation.clamp(-5.0, 5.0) + 5.0) / 10.0;
            final whiteRatio = normalized;
            final blackRatio = 1.0 - whiteRatio;

            return _Bars(
              width: width,
              height: height,
              blackHeight: blackRatio * height,
              whiteHeight: whiteRatio * height,
              evaluation: evaluation,
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
    required this.evaluation,
    super.key,
  });

  final double width;
  final double height;
  final double whiteHeight;
  final double blackHeight;
  final double evaluation;

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
          Container(width: width, height: 2, color: kRedColor),
          // Add evaluation number display
          Align(
            alignment: Alignment.center,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 1.w, vertical: 0.5.h),
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2.br),
              ),
              child: Text(
                evaluation.abs() >= 10.0
                    ? (evaluation > 0 ? "M" : "-M") // Show "M" or "-M" for mate
                    : evaluation
                        .toString()
                        .characters
                        .take(4)
                        .string, // Show negative values directly
                textAlign: TextAlign.center,
                maxLines: 1,
                style: AppTypography.textSmRegular.copyWith(
                  color: Colors.white,
                  fontSize: 1.5.f,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
