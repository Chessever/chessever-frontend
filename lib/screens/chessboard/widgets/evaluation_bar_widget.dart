import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EvaluationBarWidget extends ConsumerStatefulWidget {
  final double width;
  final double height;
  final double? evaluation; // Made nullable to handle loading state
  final bool isFlipped;
  final int index;
  final int mate;
  final bool isEvaluating; // Add flag to show loading during evaluation

  const EvaluationBarWidget({
    required this.width,
    required this.height,
    required this.evaluation,
    required this.isFlipped,
    required this.index,
    required this.mate,
    this.isEvaluating = false, // Default to false for backward compatibility
    super.key,
  });

  @override
  ConsumerState<EvaluationBarWidget> createState() =>
      _EvaluationBarWidgetState();
}

class _EvaluationBarWidgetState extends ConsumerState<EvaluationBarWidget> {
  double? _lastValidEvaluation;
  static final Map<String, double> _globalEvaluationCache = {};

  /// Converts evaluation to white advantage ratio
  /// eval: -5 to +5 (negative = black advantage, positive = white advantage)
  /// returns: 0.0 to 1.0 (0.0 = 100% black advantage, 1.0 = 100% white advantage)
  double getWhiteRatio(double eval) => (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;

  String get _cacheKey => 'eval_${widget.index}';

  @override
  void initState() {
    super.initState();
    // Restore last valid evaluation from global cache if available
    _lastValidEvaluation = _globalEvaluationCache[_cacheKey];
  }

  @override
  Widget build(BuildContext context) {
    // SMART EVALUATION HANDLING:
    // 1. If we have a valid evaluation and not evaluating -> update cache and use it
    // 2. If we're evaluating -> FREEZE the bar at last valid position (no animation)
    // 3. Only animate when evaluation is complete and different from cached value

    double evalValueForDisplay;
    bool shouldAnimate = true;

    if (widget.evaluation != null) {
      final newEval = widget.evaluation!;
      final oldEval = _lastValidEvaluation;

      if (!widget.isEvaluating &&
          oldEval != null &&
          (newEval - oldEval).abs() < 0.1) {
        evalValueForDisplay = oldEval;
        shouldAnimate = false;
      } else {
        _lastValidEvaluation = newEval;
        _globalEvaluationCache[_cacheKey] = newEval;
        evalValueForDisplay = newEval;
        shouldAnimate = !widget.isEvaluating;
      }
    } else if (_lastValidEvaluation != null) {
      evalValueForDisplay = _lastValidEvaluation!;
      shouldAnimate = false;
    } else {
      evalValueForDisplay = 0.0;
      shouldAnimate = false;
    }

    final whiteRatio = getWhiteRatio(evalValueForDisplay);
    final blackRatio = 1.0 - whiteRatio;

    final whiteHeight = whiteRatio * widget.height;
    final blackHeight = blackRatio * widget.height;

    // Color scheme (consistent regardless of move traversal):
    // - White color (bottom when not flipped) = White advantage
    // - Dark color (top when not flipped) = Black advantage
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
                  shouldAnimate
                      ? const Duration(milliseconds: 300)
                      : Duration.zero,
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
                  shouldAnimate
                      ? const Duration(milliseconds: 300)
                      : Duration.zero,
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
                (widget.evaluation == null && _lastValidEvaluation == null)
                    ? '...'
                    : ((widget.evaluation ?? _lastValidEvaluation)!.abs() >=
                            10.0 &&
                        widget.mate != null &&
                        widget.mate != 0)
                    ? '#${widget.mate!.abs()}'
                    : (widget.evaluation ?? _lastValidEvaluation)!
                        .abs()
                        .toStringAsFixed(1),
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
                isEvaluating: true,
                isFlipped:
                    false, // Game cards always show from white's perspective
              ),
            );
          },
          error: (_, _) {
            return SkeletonWidget(
              child: _Bars(
                width: width,
                height: height,
                whiteHeight: height * 0.5,
                blackHeight: height * 0.5,
                evaluation: 0.0,
                isFlipped:
                    false, // Game cards always show from white's perspective
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
                  isFlipped:
                      false, // Game cards always show from white's perspective
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

            // The cascadeEvalProvider already ensures evaluations are from white's perspective:
            // - Positive evaluation = White advantage
            // - Negative evaluation = Black advantage

            // Calculate color ratios for the evaluation bar
            // evaluation: positive = white advantage, negative = black advantage
            // normalized: 0.0 = full black advantage, 1.0 = full white advantage
            final normalized = (evaluation.clamp(-5.0, 5.0) + 5.0) / 10.0;
            final whiteRatio =
                normalized; // How much white advantage (0.0 to 1.0)
            final blackRatio =
                1.0 - whiteRatio; // How much black advantage (0.0 to 1.0)

            return _Bars(
              width: width,
              height: height,
              blackHeight: blackRatio * height,
              whiteHeight: whiteRatio * height,
              evaluation: evaluation,
              isFlipped:
                  false, // Game cards always show from white's perspective
            );
          },
        );
  }
}

class _Bars extends StatefulWidget {
  const _Bars({
    required this.width,
    required this.height,
    required this.whiteHeight,
    required this.blackHeight,
    required this.evaluation,
    this.isEvaluating = false,
    this.isFlipped = false,
    super.key,
  });

  final double width;
  final double height;
  final double whiteHeight;
  final double blackHeight;
  final double evaluation;
  final bool isEvaluating;
  final bool isFlipped;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
  double? _lastValidEvaluation;

  @override
  Widget build(BuildContext context) {
    // SMART ANIMATION: Same logic as main evaluation bar
    bool shouldAnimate = true;
    double whiteHeightForDisplay = widget.whiteHeight;
    double blackHeightForDisplay = widget.blackHeight;

    if (!widget.isEvaluating && widget.evaluation != 0.0) {
      // Calculation complete - check if evaluation changed significantly
      final newEval = widget.evaluation;
      final oldEval = _lastValidEvaluation;

      if (oldEval != null && (newEval - oldEval).abs() < 0.1) {
        // Evaluation barely changed, don't animate
        shouldAnimate = false;
      } else {
        // Evaluation changed significantly, update cache and animate
        _lastValidEvaluation = newEval;
        shouldAnimate = true;
      }
    } else if (widget.isEvaluating && _lastValidEvaluation != null) {
      // Currently calculating - FREEZE bar at last position, use cached heights
      shouldAnimate = false;

      // Calculate heights from cached evaluation to freeze the bar
      final cachedNormalized =
          (_lastValidEvaluation!.clamp(-5.0, 5.0) + 5.0) / 10.0;
      final cachedWhiteRatio = cachedNormalized;
      final cachedBlackRatio = 1.0 - cachedWhiteRatio;

      whiteHeightForDisplay = cachedWhiteRatio * widget.height;
      blackHeightForDisplay = cachedBlackRatio * widget.height;
    }

    // Color scheme (consistent regardless of move traversal):
    // - White color (bottom when not flipped) = White advantage
    // - Dark color (top when not flipped) = Black advantage
    final topHeight =
        widget.isFlipped ? whiteHeightForDisplay : blackHeightForDisplay;
    final bottomHeight =
        widget.isFlipped ? blackHeightForDisplay : whiteHeightForDisplay;

    final topColor = widget.isFlipped ? kWhiteColor : kPopUpColor;
    final bottomColor = widget.isFlipped ? kPopUpColor : kWhiteColor;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration:
                  shouldAnimate
                      ? const Duration(milliseconds: 200)
                      : Duration.zero,
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
                  shouldAnimate
                      ? const Duration(milliseconds: 200)
                      : Duration.zero,
              curve: Curves.easeInOut,
              width: widget.width,
              height: bottomHeight,
              color: bottomColor,
            ),
          ),
          Container(width: widget.width, height: 2.h, color: kRedColor),
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
                widget.isEvaluating
                    ? '...' // Show loading indicator when evaluating
                    : widget.evaluation.abs() >= 10.0
                    ? "M" // Just show "M" for mate since we don't have the mate count here
                    : widget.evaluation.abs().toStringAsFixed(1),
                textAlign: TextAlign.center,
                maxLines: 1,
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor,
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
