import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Evaluation bar shown beside the active chess board.
/// It reflects the evaluation managed by the board provider and keeps the last
/// known value while the engine continues deepening.
class EvaluationBarWidget extends StatefulWidget {
  final double width;
  final double height;
  final bool isFlipped;
  final double? evaluation;
  final int? mate;
  final bool isEvaluating;

  const EvaluationBarWidget({
    required this.width,
    required this.height,
    required this.isFlipped,
    required this.evaluation,
    required this.mate,
    required this.isEvaluating,
    super.key,
  });

  @override
  State<EvaluationBarWidget> createState() => _EvaluationBarWidgetState();
}

class _EvaluationBarWidgetState extends State<EvaluationBarWidget> {
  double? _lastEval;
  int? _lastMate;
  bool _shouldAnimate = false;

  @override
  void initState() {
    super.initState();
    _lastEval = widget.evaluation;
    _lastMate = widget.mate;
  }

  @override
  void didUpdateWidget(covariant EvaluationBarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousEval = _lastEval;
    if (widget.evaluation != null) {
      _shouldAnimate =
          previousEval == null || (widget.evaluation! - previousEval).abs() >= 0.1;
      _lastEval = widget.evaluation;
    } else {
      _shouldAnimate = false;
    }
    if (widget.mate != null) {
      _lastMate = widget.mate;
    }
  }

  double _whiteRatio(double eval) => (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;

  @override
  Widget build(BuildContext context) {
    final hasEval = widget.evaluation != null || _lastEval != null;
    final displayEval = widget.evaluation ?? _lastEval ?? 0.0;
    final displayMate = widget.mate ?? _lastMate ?? 0;
    final showLoading = widget.isEvaluating && !hasEval;

    final whiteRatio = _whiteRatio(displayEval);
    final blackRatio = 1.0 - whiteRatio;
    final whiteHeight = whiteRatio * widget.height;
    final blackHeight = blackRatio * widget.height;

    final topHeight = widget.isFlipped ? whiteHeight : blackHeight;
    final bottomHeight = widget.isFlipped ? blackHeight : whiteHeight;
    final topColor = widget.isFlipped ? kWhiteColor : kPopUpColor;
    final bottomColor = widget.isFlipped ? kPopUpColor : kWhiteColor;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration:
                  _shouldAnimate ? const Duration(milliseconds: 300) : Duration.zero,
              curve: Curves.easeInOut,
              width: widget.width,
              height: topHeight,
              color: topColor,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration:
                  _shouldAnimate ? const Duration(milliseconds: 300) : Duration.zero,
              curve: Curves.easeInOut,
              width: widget.width,
              height: bottomHeight,
              color: bottomColor,
            ),
          ),
          Center(
            child: Container(width: widget.width, height: 2, color: kRedColor),
          ),
          Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 1.w, vertical: 0.5.h),
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2.br),
              ),
              child: Text(
                showLoading
                    ? '...'
                    : (displayEval.abs() >= 10.0 && displayMate != 0)
                        ? '#${displayMate.abs()}'
                        : displayEval.abs().toStringAsFixed(1),
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

/// Evaluation widget used on game cards (still watches the cascade provider).
class EvaluationBarWidgetForGames extends ConsumerWidget {
  final double width;
  final double height;
  final String fen;
  final PlayerView playerView;

  const EvaluationBarWidgetForGames({
    required this.width,
    required this.height,
    required this.fen,
    required this.playerView,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(
          cascadeEvalProvider(
            CascadeEvalParams(fen: fen, multiPV: 1),
          ),
        )
        .when(
          loading: () {
            return SkeletonWidget(
              child: _Bars(
                width: width,
                height: height,
                whiteHeight: height * 0.5,
                blackHeight: height * 0.5,
                evaluation: 0.0,
                isEvaluating: true,
                playerView: playerView,
                isFlipped: false,
              ),
            );
          },
          error: (_, __) {
            return SkeletonWidget(
              child: _Bars(
                width: width,
                height: height,
                whiteHeight: height * 0.5,
                blackHeight: height * 0.5,
                evaluation: 0.0,
                playerView: playerView,
                isFlipped: false,
              ),
            );
          },
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
                  playerView: playerView,
                  isFlipped: false,
                ),
              );
            }

            final eval = pv.cp / 100.0;
            final isMate = pv.isMate && pv.mate != null;
            final mate = pv.mate ?? 0;

            return _Bars(
              width: width,
              height: height,
              whiteHeight: _getWhiteHeight(eval, height),
              blackHeight: _getBlackHeight(eval, height),
              evaluation: eval,
              isMate: isMate,
              mate: mate,
              playerView: playerView,
              isFlipped: false,
            );
          },
        );
  }

  double _getWhiteHeight(double eval, double totalHeight) {
    final ratio = ((eval.clamp(-5.0, 5.0)) + 5) / 10;
    return ratio * totalHeight;
  }

  double _getBlackHeight(double eval, double totalHeight) {
    return totalHeight - _getWhiteHeight(eval, totalHeight);
  }
}

class _Bars extends StatelessWidget {
  final double width;
  final double height;
  final double whiteHeight;
  final double blackHeight;
  final double evaluation;
  final PlayerView playerView;
  final bool isFlipped;
  final bool isEvaluating;
  final bool isMate;
  final int mate;

  const _Bars({
    required this.width,
    required this.height,
    required this.whiteHeight,
    required this.blackHeight,
    required this.evaluation,
    required this.playerView,
    required this.isFlipped,
    this.isEvaluating = false,
    this.isMate = false,
    this.mate = 0,
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
            child: Container(
              width: width,
              height: isFlipped ? whiteHeight : blackHeight,
              color: isFlipped ? kWhiteColor : kPopUpColor,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: width,
              height: isFlipped ? blackHeight : whiteHeight,
              color: isFlipped ? kPopUpColor : kWhiteColor,
            ),
          ),
          Center(
            child: Container(width: width, height: 2, color: kRedColor),
          ),
          Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 1.w, vertical: 0.5.h),
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2.br),
              ),
              child: Text(
                isEvaluating && evaluation == 0.0
                    ? '...'
                    : (isMate && mate != 0)
                        ? '#${mate.abs()}'
                        : evaluation.abs().toStringAsFixed(1),
                maxLines: 1,
                textAlign: TextAlign.center,
                style: AppTypography.textSmRegular.copyWith(
                  color: Colors.white,
                  fontSize:
                      playerView == PlayerView.gridView ? 0.2.f : 1.5.f,
                  fontWeight:
                      playerView == PlayerView.gridView
                          ? FontWeight.w300
                          : FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
